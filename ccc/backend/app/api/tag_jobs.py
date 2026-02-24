"""
Tag-jobs API: discover existing Szurubooru posts to retag and abort all pending tag jobs.
"""

import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import Job, JobStatus, JobType, User, get_db
from app.api.deps import get_current_user
from app.services.szurubooru import search_posts, set_current_user, test_connection
from app.services.encryption import decrypt

router = APIRouter()


class TagJobsDiscoverRequest(BaseModel):
    tag_filter: Optional[str] = None
    max_tag_count: Optional[int] = None
    replace_original_tags: bool = False
    limit: int = 100


class TagJobsDiscoverResponse(BaseModel):
    job_ids: List[str]
    created: int


class TagJobsAbortResponse(BaseModel):
    aborted: int


async def _ensure_szuru_context(current_user: User, db: AsyncSession):
    """Load user's Szurubooru config and set API context. Raises HTTPException if not configured."""
    if not current_user.szuru_username:
        raise HTTPException(
            status_code=400,
            detail="Szurubooru username not configured. Set it in Settings.",
        )
    result = await db.execute(select(User).where(User.id == current_user.id))
    user = result.scalar_one_or_none()
    if not user or not user.szuru_url:
        raise HTTPException(
            status_code=400,
            detail="Szurubooru URL not configured. Set it in Settings.",
        )
    token = None
    if user.szuru_token_encrypted:
        try:
            token = decrypt(user.szuru_token_encrypted)
        except Exception:
            raise HTTPException(
                status_code=400,
                detail="Failed to decrypt Szurubooru token.",
            )
    if not token:
        raise HTTPException(
            status_code=400,
            detail="Szurubooru token not configured. Set it in Settings.",
        )
    set_current_user(user.szuru_username, token, user.szuru_url)
    if not await test_connection():
        raise HTTPException(
            status_code=502,
            detail="Cannot connect to Szurubooru. Check URL and token.",
        )


@router.post("/tag-jobs/discover", response_model=TagJobsDiscoverResponse, status_code=201)
async def discover_tag_jobs(
    body: TagJobsDiscoverRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Find Szurubooru posts matching criteria and create one tag job per post.
    Exactly one of tag_filter or max_tag_count must be set.
    """
    if (body.tag_filter is None) == (body.max_tag_count is None):
        raise HTTPException(
            status_code=400,
            detail="Set exactly one of tag_filter or max_tag_count.",
        )
    if body.tag_filter is not None and not str(body.tag_filter).strip():
        raise HTTPException(status_code=400, detail="tag_filter must be non-empty.")
    if body.max_tag_count is not None and (body.max_tag_count < 0 or body.max_tag_count > 1000):
        raise HTTPException(
            status_code=400,
            detail="max_tag_count must be between 0 and 1000.",
        )
    if body.limit < 1:
        raise HTTPException(status_code=400, detail="limit must be at least 1.")

    await _ensure_szuru_context(current_user, db)

    uploader_filter = f"uploader:{current_user.szuru_username}" if current_user.szuru_username else ""
    if not uploader_filter:
        raise HTTPException(
            status_code=400,
            detail="Szurubooru username not set. Tagger only runs against posts uploaded by your Szuru user.",
        )

    existing_post_ids = set()
    result = await db.execute(
        select(Job.target_szuru_post_id).where(
            Job.job_type == JobType.TAG_EXISTING,
            Job.szuru_user == current_user.szuru_username,
            Job.target_szuru_post_id.isnot(None),
        )
    )
    for row in result.all():
        if row[0] is not None:
            existing_post_ids.add(row[0])

    candidate_post_ids: List[int] = []
    replace = 1 if body.replace_original_tags else 0

    if body.tag_filter is not None:
        tag = str(body.tag_filter).strip()
        offset = 0
        page_size = min(body.limit, 100)
        while len(candidate_post_ids) < body.limit:
            query = f"tag:{tag} {uploader_filter}".strip()
            resp = await search_posts(query=query, limit=page_size, offset=offset)
            if "error" in resp:
                raise HTTPException(
                    status_code=502,
                    detail=f"Szurubooru search failed: {resp.get('error', 'unknown')}",
                )
            results = resp.get("results") or []
            if not results:
                break
            for post in results:
                pid = post.get("id") if isinstance(post, dict) else getattr(post, "id", None)
                if pid is not None and pid not in existing_post_ids:
                    candidate_post_ids.append(pid)
                    existing_post_ids.add(pid)
                    if len(candidate_post_ids) >= body.limit:
                        break
            if len(results) < page_size:
                break
            offset += page_size
    else:
        max_count = body.max_tag_count
        offset = 0
        page_size = min(body.limit * 2, 200)
        while len(candidate_post_ids) < body.limit:
            query = f"sort:id {uploader_filter}".strip()
            resp = await search_posts(query=query, limit=page_size, offset=offset)
            if "error" in resp:
                raise HTTPException(
                    status_code=502,
                    detail=f"Szurubooru search failed: {resp.get('error', 'unknown')}",
                )
            results = resp.get("results") or []
            if not results:
                break
            for post in results:
                pid = post.get("id") if isinstance(post, dict) else getattr(post, "id", None)
                if pid is None or pid in existing_post_ids:
                    continue
                tags = post.get("tags") if isinstance(post, dict) else getattr(post, "tags", [])
                tag_count = post.get("tagCount", len(tags)) if isinstance(post, dict) else len(tags)
                if tag_count < max_count:
                    candidate_post_ids.append(pid)
                    existing_post_ids.add(pid)
                    if len(candidate_post_ids) >= body.limit:
                        break
            if len(results) < page_size:
                break
            offset += page_size

    job_ids = []
    for post_id in candidate_post_ids:
        job = Job(
            id=uuid.uuid4(),
            job_type=JobType.TAG_EXISTING,
            target_szuru_post_id=post_id,
            replace_original_tags=replace,
            szuru_user=current_user.szuru_username,
        )
        db.add(job)
        job_ids.append(str(job.id))
    await db.commit()

    from app.api.events import publish_job_update
    for jid in job_ids:
        await publish_job_update(job_id=jid, status="pending", progress=0)

    return TagJobsDiscoverResponse(job_ids=job_ids, created=len(job_ids))


@router.post("/tag-jobs/abort", response_model=TagJobsAbortResponse)
async def abort_all_tag_jobs(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Set all pending or paused tag jobs for the current user to stopped."""
    result = await db.execute(
        select(Job).where(
            Job.job_type == JobType.TAG_EXISTING,
            Job.szuru_user == current_user.szuru_username,
            Job.status.in_([JobStatus.PENDING, JobStatus.PAUSED]),
        )
    )
    jobs = result.scalars().all()
    aborted = 0
    for job in jobs:
        job.status = JobStatus.STOPPED
        aborted += 1
    await db.commit()
    from app.api.events import publish_job_update
    for job in jobs:
        await publish_job_update(job_id=job.id, status="stopped", progress=0)
    return TagJobsAbortResponse(aborted=aborted)
