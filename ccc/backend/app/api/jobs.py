"""
Job CRUD endpoints.

POST /api/jobs         – create a new job (URL or file upload)
GET  /api/jobs         – list jobs (paginated, filterable)
GET  /api/jobs/{id}    – get single job details
"""

import json
import os
import shutil
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel
from sqlalchemy import cast, func, select, String
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import load_only

from app.config import get_settings
from app.database import Job, JobStatus, JobType, User, get_db
from app.api.deps import get_current_user
from app.sites import normalize_url

router = APIRouter()
settings = get_settings()


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class JobCreateURL(BaseModel):
    url: str
    source: Optional[str] = None
    tags: Optional[List[str]] = None
    safety: Optional[str] = "unsafe"
    skip_tagging: Optional[bool] = False


def _parse_json_tags(raw: Optional[str]) -> Optional[List[str]]:
    if not raw:
        return None
    try:
        out = json.loads(raw)
        return out if isinstance(out, list) else None
    except (json.JSONDecodeError, TypeError):
        return None


class SzuruPostMirror(BaseModel):
    """Mirrors the post as stored on Szurubooru (what we offload to them)."""

    id: int
    tags: List[str] = []
    source: Optional[str] = None
    safety: Optional[str] = None
    relations: List[int] = []


class JobOut(BaseModel):
    id: str
    status: str
    job_type: str
    url: Optional[str] = None
    original_filename: Optional[str] = None
    source_override: Optional[str] = None
    safety: Optional[str] = None
    skip_tagging: bool = False
    szuru_user: Optional[str] = None
    dashboard_username: Optional[str] = None
    szuru_post_id: Optional[int] = None
    related_post_ids: Optional[List[int]] = None
    was_merge: bool = False
    error_message: Optional[str] = None
    tags_applied: Optional[List[str]] = None
    tags_from_source: Optional[List[str]] = None
    tags_from_ai: Optional[List[str]] = None
    retry_count: int = 0
    created_at: datetime
    updated_at: datetime
    post: Optional[SzuruPostMirror] = None

    class Config:
        from_attributes = True


class JobSummaryOut(BaseModel):
    """Slim job representation for list views. Excludes tags and other heavy fields."""
    id: str
    status: str
    job_type: str
    url: Optional[str] = None
    original_filename: Optional[str] = None
    szuru_user: Optional[str] = None
    dashboard_username: Optional[str] = None
    szuru_post_id: Optional[int] = None
    related_post_ids: Optional[List[int]] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


def _job_to_summary(job: Job, dashboard_username: Optional[str] = None) -> JobSummaryOut:
    return JobSummaryOut(
        id=str(job.id),
        status=job.status.value if isinstance(job.status, JobStatus) else job.status,
        job_type=job.job_type.value if isinstance(job.job_type, JobType) else job.job_type,
        url=job.url,
        original_filename=job.original_filename,
        szuru_user=job.szuru_user,
        dashboard_username=dashboard_username,
        szuru_post_id=job.szuru_post_id,
        related_post_ids=job.related_post_ids,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


def _job_to_out(job: Job, dashboard_username: Optional[str] = None) -> JobOut:
    tags_applied = _parse_json_tags(job.tags_applied)
    post = None
    if job.szuru_post_id is not None:
        post = SzuruPostMirror(
            id=job.szuru_post_id,
            tags=tags_applied or [],
            source=job.source_override,
            safety=job.safety,
            relations=job.related_post_ids or [],
        )
    return JobOut(
        id=str(job.id),
        status=job.status.value if isinstance(job.status, JobStatus) else job.status,
        job_type=job.job_type.value if isinstance(job.job_type, JobType) else job.job_type,
        url=job.url,
        original_filename=job.original_filename,
        source_override=job.source_override,
        safety=job.safety,
        skip_tagging=bool(job.skip_tagging),
        szuru_user=job.szuru_user,
        dashboard_username=dashboard_username,
        szuru_post_id=job.szuru_post_id,
        related_post_ids=job.related_post_ids,
        was_merge=bool(job.was_merge),
        error_message=job.error_message,
        tags_applied=tags_applied,
        tags_from_source=_parse_json_tags(job.tags_from_source),
        tags_from_ai=_parse_json_tags(job.tags_from_ai),
        retry_count=job.retry_count,
        created_at=job.created_at,
        updated_at=job.updated_at,
        post=post,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/jobs", response_model=JobOut, status_code=201)
async def create_job_url(
    body: JobCreateURL,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a job from a URL."""
    url = normalize_url(body.url)
    job = Job(
        job_type=JobType.URL,
        url=url,
        source_override=body.source,
        initial_tags=json.dumps(body.tags) if body.tags else None,
        safety=body.safety or "unsafe",
        skip_tagging=1 if body.skip_tagging else 0,
        szuru_user=current_user.szuru_username,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)
    return _job_to_out(job)


@router.post("/jobs/upload", response_model=JobOut, status_code=201)
async def create_job_file(
    file: UploadFile = File(...),
    safety: str = Form("unsafe"),
    skip_tagging: bool = Form(False),
    tags: Optional[str] = Form(None),
    source: Optional[str] = Form(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a job from a file upload."""
    job_id = uuid.uuid4()
    job_dir = os.path.join(settings.job_data_dir, str(job_id))
    os.makedirs(job_dir, exist_ok=True)

    dest = os.path.join(job_dir, file.filename or "upload")
    with open(dest, "wb") as f:
        shutil.copyfileobj(file.file, f)

    # Parse tags from comma-separated string or JSON array
    parsed_tags = _parse_json_tags(tags) if tags else None
    if parsed_tags is None and tags:
        # Try parsing as comma-separated string
        parsed_tags = [t.strip() for t in tags.split(',') if t.strip()]

    job = Job(
        id=job_id,
        job_type=JobType.FILE,
        original_filename=file.filename,
        source_override=source,
        initial_tags=json.dumps(parsed_tags) if parsed_tags else None,
        safety=safety,
        skip_tagging=1 if skip_tagging else 0,
        szuru_user=current_user.szuru_username,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)
    return _job_to_out(job)


@router.get("/jobs", response_model=dict)
async def list_jobs(
    status: Optional[str] = Query(None),
    was_merge: Optional[bool] = Query(None),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List jobs for current user with optional status and was_merge filter, paginated."""
    valid_statuses = {s.value.lower() for s in JobStatus}
    if status:
        status_lower = status.strip().lower()
        if status_lower not in valid_statuses:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid status: {status!r}. Must be one of: {sorted(valid_statuses)}.",
            )

    try:
        query = select(Job).options(
            load_only(
                Job.id, Job.status, Job.job_type, Job.url,
                Job.original_filename, Job.szuru_user,
                Job.szuru_post_id, Job.related_post_ids,
                Job.created_at, Job.updated_at,
            )
        )
        count_query = select(func.count(Job.id))

        if status:
            status_lower = status.strip().lower()
            query = query.where(func.lower(cast(Job.status, String)) == status_lower)
            count_query = count_query.where(func.lower(cast(Job.status, String)) == status_lower)
        if was_merge is not None:
            query = query.where(Job.was_merge == (1 if was_merge else 0))
            count_query = count_query.where(Job.was_merge == (1 if was_merge else 0))

        # Auto-filter by current user's szuru_username (JWT auth)
        if current_user.szuru_username:
            query = query.where(Job.szuru_user == current_user.szuru_username)
            count_query = count_query.where(Job.szuru_user == current_user.szuru_username)

        query = query.order_by(Job.created_at.desc()).offset(offset).limit(limit)

        result = await db.execute(query)
        jobs = result.scalars().all()

        total_result = await db.execute(count_query)
        total = total_result.scalar() or 0

        # Batch lookup dashboard usernames for all jobs
        szuru_users = {j.szuru_user for j in jobs if j.szuru_user}
        username_map = {}
        if szuru_users:
            user_result = await db.execute(
                select(User.szuru_username, User.username).where(User.szuru_username.in_(szuru_users))
            )
            username_map = {row[0]: row[1] for row in user_result.all()}

        return {
            "results": [_job_to_summary(j, username_map.get(j.szuru_user)) for j in jobs],
            "total": total,
            "offset": offset,
            "limit": limit,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"Jobs list temporarily unavailable: {str(e)[:200]}",
        ) from e

@router.get("/jobs/{job_id}", response_model=JobOut)
async def get_job(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a single job by ID."""
    result = await db.execute(select(Job).where(Job.id == uuid.UUID(job_id)))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    # Look up dashboard username for this job's szuru_user
    dashboard_username = None
    if job.szuru_user:
        user_result = await db.execute(
            select(User.username).where(User.szuru_username == job.szuru_user)
        )
        dashboard_username = user_result.scalar_one_or_none()

    return _job_to_out(job, dashboard_username)


# ---------------------------------------------------------------------------
# Job Control Endpoints
# ---------------------------------------------------------------------------


@router.post("/jobs/{job_id}/start", response_model=JobOut)
async def start_job(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Start a pending job.
    Only works if job status is 'pending'.
    Sets status to 'pending' and triggers worker to process it.
    """
    from app.api.events import publish_job_update

    result = await db.execute(select(Job).where(Job.id == uuid.UUID(job_id)))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    if job.status != JobStatus.PENDING:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot start job with status '{job.status.value}'. Job must be in 'pending' status."
        )

    # Job is already pending, just broadcast the update to trigger processing
    await db.refresh(job)
    await publish_job_update(job_id=job.id, status="pending")
    return _job_to_out(job)


@router.post("/jobs/{job_id}/pause", response_model=JobOut)
async def pause_job(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Pause a running job.
    Only works if job status is 'downloading', 'tagging', or 'uploading'.
    Sets status to 'paused'.
    """
    from app.api.events import publish_job_update

    result = await db.execute(select(Job).where(Job.id == uuid.UUID(job_id)))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    allowed_statuses = {JobStatus.DOWNLOADING, JobStatus.TAGGING, JobStatus.UPLOADING}
    if job.status not in allowed_statuses:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot pause job with status '{job.status.value}'. Job must be in 'downloading', 'tagging', or 'uploading' status."
        )

    job.status = JobStatus.PAUSED
    job.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(job)

    await publish_job_update(job_id=job.id, status="paused")
    return _job_to_out(job)


@router.post("/jobs/{job_id}/stop", response_model=JobOut)
async def stop_job(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Stop a job.
    Works on any non-terminal status (not 'completed' or 'failed').
    Sets status to 'stopped'.
    """
    from app.api.events import publish_job_update

    result = await db.execute(select(Job).where(Job.id == uuid.UUID(job_id)))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    terminal_statuses = {JobStatus.COMPLETED, JobStatus.MERGED, JobStatus.FAILED}
    if job.status in terminal_statuses:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot stop job with status '{job.status.value}'. Job is already in a terminal state."
        )

    job.status = JobStatus.STOPPED
    job.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(job)

    await publish_job_update(job_id=job.id, status="stopped")
    return _job_to_out(job)


@router.delete("/jobs/{job_id}")
async def delete_job(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Delete a job.
    Deletes the job from database and any downloaded files in the job's temp directory.
    """
    result = await db.execute(select(Job).where(Job.id == uuid.UUID(job_id)))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    # Delete job's temp directory if it exists
    job_dir = os.path.join(settings.job_data_dir, job_id)
    if os.path.isdir(job_dir):
        try:
            shutil.rmtree(job_dir, ignore_errors=True)
        except Exception:
            pass  # Ignore cleanup errors

    # Delete the job from database
    await db.delete(job)
    await db.commit()

    return {"message": f"Job {job_id} deleted successfully"}


@router.post("/jobs/{job_id}/resume", response_model=JobOut)
async def resume_job(
    job_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Resume a paused or stopped job.
    Only works if job status is 'paused' or 'stopped'.
    Sets status to 'pending' to re-queue for processing.
    """
    from app.api.events import publish_job_update

    result = await db.execute(select(Job).where(Job.id == uuid.UUID(job_id)))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    allowed_statuses = {JobStatus.PAUSED, JobStatus.STOPPED}
    if job.status not in allowed_statuses:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot resume job with status '{job.status.value}'. Job must be in 'paused' or 'stopped' status."
        )

    job.status = JobStatus.PENDING
    job.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(job)

    await publish_job_update(job_id=job.id, status="pending")
    return _job_to_out(job)
