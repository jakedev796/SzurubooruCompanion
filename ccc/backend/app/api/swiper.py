"""
Discover API endpoints.
Browse booru sites, track seen items, manage presets, proxy images.
"""

import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import List, Optional
from urllib.parse import urlparse

import aiohttp
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import (
    Job,
    JobStatus,
    JobType,
    SwiperPreset,
    SwiperSeenItem,
    User,
    get_db,
)
from app.api.deps import get_current_user
from app.services.browse import BrowseItem, BrowseResult, browse_site, mark_seen
from app.services.config import load_user_config
from app.sites.registry import get_browsable_handlers, get_handler_by_name

logger = logging.getLogger(__name__)
router = APIRouter()

# Allowed domains for image proxy (prevent SSRF)
_PROXY_ALLOWED_DOMAINS = {
    # Danbooru CDN
    "cdn.donmai.us", "danbooru.donmai.us",
    # Gelbooru CDN
    "gelbooru.com", "img3.gelbooru.com", "img4.gelbooru.com",
    # Sankaku CDN
    "s.sankakucomplex.com", "v.sankakucomplex.com", "cs.sankakucomplex.com",
    "chan.sankakucomplex.com", "capi-v2.sankakucomplex.com",
    # Rule34
    "rule34.xxx", "api-cdn.rule34.xxx", "us.rule34.xxx",
    "api-cdn-mp4.rule34.xxx", "wimg.rule34.xxx",
    # Rule34Vault
    "rule34vault.com",
    # Yandere
    "yande.re", "files.yande.re", "assets.yande.re",
}


# ---------------------------------------------------------------------------
# Pydantic schemas
# ---------------------------------------------------------------------------


class BrowseRequest(BaseModel):
    sites: List[str]
    tags: str = ""
    rating: str = "all"
    sort: str = "newest"
    page: int = 1
    limit: int = 20


class BrowseItemOut(BaseModel):
    site_name: str
    external_id: str
    post_url: str
    thumbnail_url: str
    preview_url: str
    file_url: str
    tags: List[str]
    rating: str
    width: Optional[int] = None
    height: Optional[int] = None
    source: Optional[str] = None


class BrowseResponse(BaseModel):
    items: List[BrowseItemOut]
    has_more: bool
    page: int


class SeenRequest(BaseModel):
    site_name: str
    external_id: str
    action: str  # "liked" or "skipped"
    post_url: Optional[str] = None  # Required for "liked" to create job


class SeenResponse(BaseModel):
    ok: bool
    job_id: Optional[str] = None


class SwiperSiteOut(BaseModel):
    name: str
    has_credentials: bool
    requires_credentials: bool


class PresetOut(BaseModel):
    id: str
    name: str
    sites: List[str]
    tags: str
    rating: str
    sort: str
    is_default: bool


class PresetCreate(BaseModel):
    name: str
    sites: List[str]
    tags: str = ""
    rating: str = "all"
    sort: str = "newest"
    is_default: bool = False


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/discover/sites", response_model=List[SwiperSiteOut])
async def list_browsable_sites(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List sites that support browsing, with credential status for the current user."""
    user_config = await _load_user_site_config(db, current_user)
    handlers = get_browsable_handlers(user_config)

    sites = []
    for handler in handlers:
        has_creds = bool(handler.credentials) and bool(
            user_config.get(handler.name, {})
        )
        sites.append(SwiperSiteOut(
            name=handler.name,
            has_credentials=has_creds,
            requires_credentials=bool(handler.credentials),
        ))
    return sites


@router.post("/discover/browse", response_model=BrowseResponse)
async def browse(
    body: BrowseRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Browse one or more sites with tag filters, excluding already-seen items.
    Results from multiple sites are interleaved."""
    if not body.sites:
        raise HTTPException(status_code=400, detail="At least one site is required")
    if body.limit > 50:
        body.limit = 50
    if body.limit < 1:
        body.limit = 1

    user_config = await _load_user_site_config(db, current_user)

    # Per-site limit: request enough from each to fill the total
    per_site_limit = max(body.limit // len(body.sites) + 2, 5)

    # Browse all sites concurrently with per-site timeout.
    # Faster sites return immediately; slow sites are skipped (not blocked on).
    per_site_timeout = 45  # seconds

    async def _browse_one(site: str) -> BrowseResult:
        try:
            return await asyncio.wait_for(
                browse_site(
                    site_name=site,
                    tags=body.tags,
                    rating=body.rating,
                    page=body.page,
                    limit=per_site_limit,
                    user_id=str(current_user.id),
                    user_config=user_config,
                    db=db,
                    sort=body.sort,
                ),
                timeout=per_site_timeout,
            )
        except asyncio.TimeoutError:
            logger.warning("Browse timed out for %s after %ds", site, per_site_timeout)
            return BrowseResult(items=[], has_more=True, page=body.page)
        except Exception as e:
            logger.warning("Browse failed for %s: %s", site, e)
            return BrowseResult(items=[], has_more=False, page=body.page)

    results = await asyncio.gather(*[_browse_one(s) for s in body.sites])

    # Interleave results: round-robin from each site's queue
    site_queues = [list(r.items) for r in results if r.items]
    any_has_more = any(r.has_more for r in results)

    interleaved: list[BrowseItem] = []
    while len(interleaved) < body.limit and any(site_queues):
        for queue in site_queues:
            if queue and len(interleaved) < body.limit:
                interleaved.append(queue.pop(0))
        site_queues = [q for q in site_queues if q]

    items_out = [
        BrowseItemOut(
            site_name=item.site_name,
            external_id=item.external_id,
            post_url=item.post_url,
            thumbnail_url=item.thumbnail_url,
            preview_url=item.preview_url,
            file_url=item.file_url,
            tags=item.tags,
            rating=item.rating,
            width=item.width,
            height=item.height,
            source=item.source,
        )
        for item in interleaved
    ]

    return BrowseResponse(
        items=items_out,
        has_more=any_has_more,
        page=body.page,
    )


@router.post("/discover/seen", response_model=SeenResponse)
async def mark_item_seen(
    body: SeenRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Mark an item as seen (liked or skipped).
    If liked, also creates a job to download/tag/upload the post.
    """
    if body.action not in ("liked", "skipped"):
        raise HTTPException(status_code=400, detail="action must be 'liked' or 'skipped'")

    await mark_seen(
        user_id=str(current_user.id),
        site_name=body.site_name,
        external_id=body.external_id,
        action=body.action,
        db=db,
    )

    job_id = None
    if body.action == "liked" and body.post_url:
        job_id = await _create_job_from_swipe(body.post_url, current_user, db)

    return SeenResponse(ok=True, job_id=job_id)


@router.post("/discover/seen/batch")
async def mark_items_seen_batch(
    items: List[SeenRequest],
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Batch mark items as seen."""
    results = []
    for item in items:
        if item.action not in ("liked", "skipped"):
            continue
        await mark_seen(
            user_id=str(current_user.id),
            site_name=item.site_name,
            external_id=item.external_id,
            action=item.action,
            db=db,
        )
        job_id = None
        if item.action == "liked" and item.post_url:
            job_id = await _create_job_from_swipe(item.post_url, current_user, db)
        results.append({"external_id": item.external_id, "ok": True, "job_id": job_id})

    return results


@router.get("/discover/image")
async def proxy_image(
    url: str = Query(..., description="URL-encoded source image URL"),
    current_user: User = Depends(get_current_user),
):
    """
    Proxy endpoint for booru thumbnails/previews.
    Validates domain against allowlist to prevent SSRF.
    """
    parsed = urlparse(url)
    domain = parsed.netloc.lower()

    if domain not in _PROXY_ALLOWED_DOMAINS:
        raise HTTPException(status_code=400, detail=f"Domain not allowed: {domain}")

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                if resp.status != 200:
                    raise HTTPException(status_code=resp.status, detail="Upstream image fetch failed")

                content_type = resp.headers.get("Content-Type", "application/octet-stream")
                content = await resp.read()

                if len(content) > 20 * 1024 * 1024:  # 20MB limit
                    raise HTTPException(status_code=413, detail="Image too large")

                return StreamingResponse(
                    iter([content]),
                    media_type=content_type,
                    headers={
                        "Cache-Control": "public, max-age=3600",
                        "Content-Length": str(len(content)),
                    },
                )
    except aiohttp.ClientError as e:
        logger.warning("Image proxy failed for %s: %s", url, e)
        raise HTTPException(status_code=502, detail="Failed to fetch image")


# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------


@router.get("/discover/presets", response_model=List[PresetOut])
async def list_presets(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get user's saved swiper filter presets."""
    result = await db.execute(
        select(SwiperPreset)
        .where(SwiperPreset.user_id == current_user.id)
        .order_by(SwiperPreset.is_default.desc(), SwiperPreset.name)
    )
    presets = result.scalars().all()
    return [
        PresetOut(
            id=str(p.id),
            name=p.name,
            sites=p.sites or [],
            tags=p.tags or "",
            rating=p.rating or "all",
            sort=getattr(p, "sort", None) or "newest",
            is_default=bool(p.is_default),
        )
        for p in presets
    ]


@router.post("/discover/presets", response_model=PresetOut, status_code=201)
async def create_preset(
    body: PresetCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new swiper preset."""
    # If this is set as default, unset any existing default
    if body.is_default:
        await db.execute(
            update(SwiperPreset)
            .where(SwiperPreset.user_id == current_user.id)
            .values(is_default=0)
        )

    preset = SwiperPreset(
        user_id=current_user.id,
        name=body.name,
        sites=body.sites,
        tags=body.tags,
        rating=body.rating,
        sort=body.sort,
        is_default=1 if body.is_default else 0,
    )
    db.add(preset)
    await db.commit()
    await db.refresh(preset)

    return PresetOut(
        id=str(preset.id),
        name=preset.name,
        sites=preset.sites or [],
        tags=preset.tags or "",
        rating=preset.rating or "all",
        sort=getattr(preset, "sort", None) or "newest",
        is_default=bool(preset.is_default),
    )


@router.post("/discover/presets/{preset_id}/default", response_model=PresetOut)
async def set_preset_default(
    preset_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Toggle a preset as the default. Unsets any other default for this user."""
    result = await db.execute(
        select(SwiperPreset).where(
            SwiperPreset.id == preset_id,
            SwiperPreset.user_id == current_user.id,
        )
    )
    preset = result.scalar_one_or_none()
    if not preset:
        raise HTTPException(status_code=404, detail="Preset not found")

    new_default = not bool(preset.is_default)

    # Unset all other defaults for this user
    await db.execute(
        update(SwiperPreset)
        .where(SwiperPreset.user_id == current_user.id)
        .values(is_default=0)
    )

    if new_default:
        preset.is_default = 1
    else:
        preset.is_default = 0

    await db.commit()
    await db.refresh(preset)

    return PresetOut(
        id=str(preset.id),
        name=preset.name,
        sites=preset.sites or [],
        tags=preset.tags or "",
        rating=preset.rating or "all",
        sort=getattr(preset, "sort", None) or "newest",
        is_default=bool(preset.is_default),
    )


@router.put("/discover/presets/{preset_id}", response_model=PresetOut)
async def update_preset(
    preset_id: str,
    body: PresetCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update an existing preset's filters."""
    result = await db.execute(
        select(SwiperPreset).where(
            SwiperPreset.id == preset_id,
            SwiperPreset.user_id == current_user.id,
        )
    )
    preset = result.scalar_one_or_none()
    if not preset:
        raise HTTPException(status_code=404, detail="Preset not found")

    if body.is_default:
        await db.execute(
            update(SwiperPreset)
            .where(SwiperPreset.user_id == current_user.id)
            .values(is_default=0)
        )

    preset.name = body.name
    preset.sites = body.sites
    preset.tags = body.tags
    preset.rating = body.rating
    preset.sort = body.sort
    preset.is_default = 1 if body.is_default else 0

    await db.commit()
    await db.refresh(preset)

    return PresetOut(
        id=str(preset.id),
        name=preset.name,
        sites=preset.sites or [],
        tags=preset.tags or "",
        rating=preset.rating or "all",
        sort=getattr(preset, "sort", None) or "newest",
        is_default=bool(preset.is_default),
    )


@router.delete("/discover/presets/{preset_id}", status_code=204)
async def delete_preset(
    preset_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a swiper preset."""
    result = await db.execute(
        select(SwiperPreset).where(
            SwiperPreset.id == preset_id,
            SwiperPreset.user_id == current_user.id,
        )
    )
    preset = result.scalar_one_or_none()
    if not preset:
        raise HTTPException(status_code=404, detail="Preset not found")

    await db.delete(preset)
    await db.commit()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _load_user_site_config(db: AsyncSession, user: User) -> dict:
    """Load decrypted site credentials for the current user."""
    if not user.id:
        return {}
    config = await load_user_config(db, str(user.id))
    if config:
        return config.site_credentials
    return {}


async def _create_job_from_swipe(post_url: str, user: User, db: AsyncSession) -> Optional[str]:
    """Create a job from a liked swipe. Returns job ID or None."""
    try:
        from app.sites import normalize_url

        normalized_url = normalize_url(post_url)

        job = Job(
            status=JobStatus.PENDING,
            job_type=JobType.URL,
            url=normalized_url,
            safety="unsafe",
            skip_tagging=0,
            szuru_user=user.szuru_username,
        )
        db.add(job)
        await db.commit()
        await db.refresh(job)

        logger.info("Created job %s from swiper like: %s", job.id, normalized_url)
        return str(job.id)
    except Exception as e:
        logger.error("Failed to create job from swipe: %s", e)
        return None
