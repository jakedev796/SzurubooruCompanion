"""
Background job processor.
Polls the database for PENDING jobs and runs the download -> tag -> upload pipeline.
"""

import asyncio
import json
import logging
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

from sqlalchemy import select

from app.config import get_settings
from app.database import Job, JobStatus, JobType, User, async_session
from app.services import downloader, szurubooru, tag_categories, tagger
from app.services.szurubooru import set_current_user
from app.services import sources as source_utils
from app.services import tag_utils
from app.services.config import load_user_config, load_global_config
from app.services.encryption import decrypt
from app.sites.registry import normalize_url as _normalize_site_url
from app.api.events import publish_job_update

logger = logging.getLogger(__name__)
settings = get_settings()

# Global configuration loaded from database (updated per-job)
_global_config = None

# Mime-extension mapping for images (used to decide if WD14 tagging applies).
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tiff"}
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".avi", ".mov"}

_running = True


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _looks_like_url(s: str) -> bool:
    return s.startswith("http://") or s.startswith("https://")


def _extract_metadata_sources(metadata: Dict) -> List[str]:
    """Extract source URLs from gallery-dl metadata (e.g. ``data.sources``, ``source``)."""
    urls: List[str] = []
    # rule34vault and similar: data.sources list
    data = metadata.get("data")
    if isinstance(data, dict):
        sources = data.get("sources")
        if isinstance(sources, list):
            for s in sources:
                if isinstance(s, str) and s.strip() and _looks_like_url(s.strip()):
                    urls.append(s.strip())
    # Some extractors put a top-level "source" string (some extractors
    # use non-URL values like "removed", so filter those out)
    source = metadata.get("source")
    if isinstance(source, str) and source.strip() and _looks_like_url(source.strip()):
        urls.append(source.strip())
    return urls


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


async def start_worker(worker_id: int = 0) -> None:
    """Main worker loop – polls for pending jobs."""
    global _running
    _running = True
    tag = f"[W{worker_id}]"
    logger.info("%s Worker started.", tag)

    while _running:
        try:
            job = await _claim_next_job()
            if job:
                logger.info("%s Claimed job %s", tag, job.id)
                await _process_job(job, tag)
            else:
                await asyncio.sleep(2)  # nothing to do – wait
        except asyncio.CancelledError:
            break
        except Exception:
            logger.exception("%s Worker loop error", tag)
            await asyncio.sleep(5)


async def stop_worker() -> None:
    global _running
    _running = False


# ---------------------------------------------------------------------------
# Job lifecycle
# ---------------------------------------------------------------------------


async def _claim_next_job():
    """Atomically grab the oldest PENDING job and mark it as DOWNLOADING."""
    async with async_session() as db:
        result = await db.execute(
            select(Job)
            .where(Job.status == JobStatus.PENDING)
            .order_by(Job.created_at.asc())
            .limit(1)
            .with_for_update(skip_locked=True)
        )
        job = result.scalar_one_or_none()
        if job:
            job.status = JobStatus.DOWNLOADING
            job.updated_at = datetime.now(timezone.utc)
            await db.commit()
            await db.refresh(job)
            # Publish SSE update
            await publish_job_update(job_id=job.id, status="downloading", progress=25)
        return job


async def _process_job(job: Job, tag: str = "[W0]") -> None:
    """
    Run the full pipeline for a single job.

    1. Load user-specific configuration from database
    2. Extract direct media URLs from the source
    3. For each media: download, tag, upload
    4. Create relations between posts from multi-file sources
    """
    job_dir = os.path.join(settings.job_data_dir, str(job.id))
    os.makedirs(job_dir, exist_ok=True)

    # Load configurations from database
    global _global_config
    user_config_obj = None
    user_config_dict = None

    async with async_session() as db:
        # Load global configuration
        _global_config = await load_global_config(db)
        logger.debug("%s Job %s: Loaded global config (WD14: %s, worker: %d, gallery-dl timeout: %ds)",
                    tag, job.id, _global_config.wd14_enabled, _global_config.worker_concurrency,
                    _global_config.gallery_dl_timeout)

        # Load user configuration and category mappings
        user_category_mappings = None
        szuru_token = None
        szuru_url = None
        if job.szuru_user:
            result = await db.execute(select(User).where(User.szuru_username == job.szuru_user))
            user = result.scalar_one_or_none()
            if user:
                user_config_obj = await load_user_config(db, str(user.id))
                if user_config_obj:
                    user_config_dict = user_config_obj.site_credentials
                    logger.info("%s Job %s: Loaded config for user %s", tag, job.id, job.szuru_user)
                else:
                    logger.warning("%s Job %s: No config found for user %s", tag, job.id, job.szuru_user)
                # Load category mappings from user's settings
                user_category_mappings = user.szuru_category_mappings or {}
                if user_category_mappings:
                    logger.debug("%s Job %s: Using per-user category mappings: %s", tag, job.id, user_category_mappings)
                # Decrypt szuru token for API authentication
                if user.szuru_token_encrypted:
                    try:
                        szuru_token = decrypt(user.szuru_token_encrypted)
                    except Exception as e:
                        logger.error("%s Job %s: Failed to decrypt szuru token for user %s: %s", tag, job.id, job.szuru_user, e)
                # Get user's szuru_url (internal/API URL)
                szuru_url = user.szuru_url
            else:
                logger.warning("%s Job %s: User %s not found in database", tag, job.id, job.szuru_user)

    # Set current user context for Szurubooru API calls (with decrypted credentials and URL)
    set_current_user(job.szuru_user, szuru_token, szuru_url)

    # Snapshot retry policy from global config (DB-backed)
    max_retries = _global_config.max_retries
    retry_delay = _global_config.retry_delay

    try:
        if await _abort_if_paused_or_stopped(job):
            return

        # ---- Phase 1: Extract media URLs ----
        extracted_media = await _extract_media(job, job_dir, user_config_dict)
        if extracted_media is None:
            return  # already failed

        # ---- Phase 2: Process each media file ----
        created_posts: List[dict] = []
        all_sources: List[str] = []
        last_error: Optional[str] = None

        for idx, media in enumerate(extracted_media):
            logger.info("%s Job %s: Processing media %d/%d - %s",
                        tag, job.id, idx + 1, len(extracted_media), media.filename)
            media_dir = os.path.join(job_dir, f"media_{idx}")
            os.makedirs(media_dir, exist_ok=True)

            try:
                if await _abort_if_paused_or_stopped(job):
                    return

                post_info = await _process_single_media(job, media, media_dir, user_config_dict, user_category_mappings)
                if post_info:
                    created_posts.append(post_info)
                    all_sources.append(media.source_url)
                elif post_info is None:
                    # None means download or upload failed
                    last_error = f"Failed to process {media.filename}"
            except Exception as exc:
                logger.exception("%s Job %s: Failed to process media %d (%s)",
                                 tag, job.id, idx, media.filename)
                last_error = str(exc)

        # ---- Phase 3: Create relations ----
        if len(created_posts) > 1:
            await _create_relations(job, created_posts)

        # ---- Finalise ----
        if created_posts:
            primary = created_posts[0]
            related_ids = [p["post"]["id"] for p in created_posts[1:]]
            await _complete_job(
                job,
                primary["post"]["id"],
                primary["tags"],
                primary["tags_from_source"],
                primary["tags_from_ai"],
                related_post_ids=related_ids,
                stored_sources=primary.get("final_source"),
                was_merge=primary.get("merged", False),
            )
        elif last_error:
            await _fail_job(job, last_error, max_retries=max_retries, retry_delay=retry_delay)
        else:
            await _fail_job(job, "No posts created.", max_retries=max_retries, retry_delay=retry_delay)

    except Exception as exc:
        logger.exception("%s Job %s failed", tag, job.id)
        await _fail_job(job, str(exc), max_retries=max_retries, retry_delay=retry_delay)
    finally:
        try:
            if os.path.isdir(job_dir):
                shutil.rmtree(job_dir, ignore_errors=True)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Phase helpers
# ---------------------------------------------------------------------------


async def _extract_media(
    job: Job, job_dir: str, user_config: Optional[Dict] = None
) -> Optional[List[downloader.ExtractedMedia]]:
    """
    Phase 1: Determine the list of media items to process.

    For URL jobs uses gallery-dl extraction; for FILE jobs builds a
    synthetic ExtractedMedia from the uploaded file.

    Returns None (and marks the job as failed) when nothing is found.
    """
    if job.job_type == JobType.URL:
        logger.info("Job %s: Phase 1 - Extracting media URLs from %s", job.id, job.url)
        extracted = await downloader.extract_media_urls(job.url, user_config)
        logger.info("Job %s: Found %d media file(s)", job.id, len(extracted))
        return extracted

    # FILE job – file was already saved during upload
    for fn in os.listdir(job_dir):
        fp = Path(job_dir) / fn
        if fp.is_file() and not fn.endswith(".json"):
            return [downloader.ExtractedMedia(
                url=f"file://{fn}",
                source_url=f"file://{fn}",
                filename=fn,
                metadata=None,
            )]

    await _fail_job(job, "No files found in job directory.")
    return None


async def _process_single_media(
    job: Job,
    media: downloader.ExtractedMedia,
    media_dir: str,
    user_config: Optional[Dict] = None,
    user_category_mappings: Optional[Dict] = None,
) -> Optional[dict]:
    """
    Download, tag, and upload a single media item.

    Returns a dict ``{"post": ..., "tags": ..., "tags_from_source": ..., "tags_from_ai": ...}``
    on success, or None on failure.
    """
    # ---- Download ----
    files, metadata = await _download_media(job, media, media_dir, user_config)
    if not files:
        logger.warning("Job %s: No files downloaded for %s", job.id, media.filename)
        return None

    fp = files[0]

    if await _abort_if_paused_or_stopped(job):
        return None  # caller checks too

    # ---- Tag ----
    await _set_status(job, JobStatus.TAGGING)
    tag_result = await _tag_file(job, fp, metadata, user_category_mappings)

    if await _abort_if_paused_or_stopped(job):
        return None

    # ---- Upload ----
    await _set_status(job, JobStatus.UPLOADING)
    return await _upload_file(job, fp, media, tag_result, metadata)


async def _download_media(
    job: Job,
    media: downloader.ExtractedMedia,
    media_dir: str,
    user_config: Optional[Dict] = None,
) -> tuple:
    """Download a single media item. Returns ``(files, metadata)``."""
    if job.job_type != JobType.URL:
        # FILE job — file already exists in the parent job_dir
        job_dir = os.path.join(settings.job_data_dir, str(job.id))
        return [Path(job_dir) / media.filename], {}

    if media.source_url and media.source_url != media.url:
        logger.info("Job %s: Downloading from direct media URL: %s", job.id, media.source_url)
        dl = await downloader.download_direct_media_url(
            media.source_url, media_dir, filename=media.filename
        )
        # Fall back to gallery-dl if direct download failed (e.g. hotlink protection)
        if dl.error:
            logger.info("Job %s: Direct download failed (%s), falling back to gallery-dl", job.id, dl.error)
            dl = await downloader.download_url(media.url, media_dir, source_url=media.source_url, user_config=user_config)
    else:
        dl = await downloader.download_url(media.url, media_dir, source_url=media.source_url, user_config=user_config)

    merged_meta = {**(media.metadata or {}), **dl.metadata}
    return dl.files, merged_meta


async def _tag_file(job: Job, fp: Path, metadata: Dict, user_category_mappings: Optional[Dict] = None) -> dict:
    """
    Collect tags from all sources (initial, metadata, WD14) and return a dict with:

    ``all_tags``, ``tags_from_source``, ``tags_from_ai``, ``safety``,
    ``client_tag_categories``, ``wd14_character_tags``, ``tag_to_category``.
    """
    # Parse initial (client-submitted) tags
    all_tags, tags_from_source, client_tag_categories = tag_utils.parse_initial_tags(
        job.initial_tags
    )

    # Metadata tags
    if metadata:
        for t in tag_utils.extract_tags_from_metadata(metadata):
            if t.strip():
                all_tags.append(t.strip())
                tags_from_source.append(t.strip())

    # WD14 tagging for images
    tags_from_ai: List[str] = []
    wd14_character_tags: set = set()
    safety = job.safety or "unsafe"
    ext = fp.suffix.lower()

    if ext in IMAGE_EXTENSIONS and not job.skip_tagging:
        wd14 = await tagger.tag_image(fp)
        for t in wd14.general_tags + wd14.character_tags:
            if t.strip():
                all_tags.append(t.strip())
                tags_from_ai.append(t.strip())
        wd14_character_tags.update(wd14.character_tags)
        if wd14.safety:
            safety = wd14.safety
    elif ext in VIDEO_EXTENSIONS:
        all_tags.append("video")
        tags_from_source.append("video")

        if _global_config and _global_config.video_tagging_enabled and not job.skip_tagging:
            wd14 = await tagger.tag_video(
                fp,
                scene_threshold=_global_config.video_scene_threshold,
                max_frames=_global_config.video_max_frames,
                min_frame_ratio=_global_config.video_tag_min_frame_ratio,
            )
            for t in wd14.general_tags + wd14.character_tags:
                if t.strip():
                    all_tags.append(t.strip())
                    tags_from_ai.append(t.strip())
            wd14_character_tags.update(wd14.character_tags)
            if wd14.safety:
                safety = wd14.safety

    # Normalize category prefixes and deduplicate
    all_tags, client_tag_categories = tag_utils.normalize_category_prefixes(
        all_tags, client_tag_categories
    )
    all_tags = tag_utils.deduplicate_tags(all_tags)

    # Resolve tag categories (using per-user mappings if available)
    tag_to_category = tag_categories.resolve_categories(
        all_tags, metadata=metadata, job_url=job.url, user_category_mappings=user_category_mappings
    )
    for t in wd14_character_tags:
        tag_to_category[t] = "character"
    for tag in all_tags:
        tag_lower = tag.strip().lower()
        if tag_lower in client_tag_categories:
            tag_to_category[tag] = client_tag_categories[tag_lower]

    # Ensure all tags exist in Szurubooru with correct categories (concurrent)
    tags_with_categories = [
        (tag, tag_to_category.get(tag) or "general")
        for tag in all_tags
    ]
    await szurubooru.ensure_tags_batch(tags_with_categories)

    return {
        "all_tags": all_tags,
        "tags_from_source": tags_from_source,
        "tags_from_ai": tags_from_ai,
        "safety": safety,
        "wd14_character_tags": wd14_character_tags,
    }


async def _upload_file(
    job: Job,
    fp: Path,
    media: downloader.ExtractedMedia,
    tag_result: dict,
    metadata: Optional[Dict] = None,
) -> Optional[dict]:
    """
    Upload a single file to Szurubooru (or merge with an existing duplicate).

    Returns ``{"post": ..., "tags": ..., ...}`` on success, or None.
    """
    all_tags = tag_result["all_tags"]
    safety = tag_result["safety"]

    # Build source string using normalized deduplication
    # FILE jobs have no meaningful source URLs (media.source_url is "file://...")
    primary_source = (job.source_override or "").strip() or None
    if job.job_type == JobType.URL:
        direct_media_url = media.source_url.strip() if media.source_url else None
        original_page_url = _normalize_site_url(job.url.strip()) if job.url else None
    else:
        direct_media_url = None
        original_page_url = None
    final_source = source_utils.build_source_string(
        direct_media_url, original_page_url, primary_source
    )

    # Append source URLs from metadata (e.g. rule34vault data.sources)
    if metadata and final_source is not None:
        for url in _extract_metadata_sources(metadata):
            final_source = source_utils.append_source(final_source, url)
    elif metadata:
        meta_sources = _extract_metadata_sources(metadata)
        if meta_sources:
            final_source = "\n".join(meta_sources)

    # Check for duplicates via reverse search
    existing = await szurubooru.reverse_search(fp)
    post: Optional[dict] = None
    merged = False

    if existing.get("exactPost"):
        logger.info("Job %s: Duplicate found for %s, merging with existing post %d",
                     job.id, media.filename, existing["exactPost"]["id"])
        post = await _merge_with_existing(
            existing["exactPost"],
            all_tags,
            final_source,
            tag_result.get("wd14_character_tags"),
        )
        merged = True
    else:
        result = await szurubooru.upload_post(
            file_path=fp, tags=all_tags, safety=safety, source=final_source,
        )
        if "error" in result:
            error_text = result["error"]
            if any(kw in error_text.lower() for kw in ("already uploaded", "duplicate", "content checksum")):
                logger.info("Job %s: Upload duplicate detected for %s", job.id, media.filename)
            else:
                logger.warning("Job %s: Upload failed for %s: %s", job.id, media.filename, error_text)
            return None
        post = result
        logger.info("Job %s: Created post %d for %s", job.id, post["id"], media.filename)

    if not post:
        return None

    return {
        "post": post,
        "tags": all_tags,
        "tags_from_source": tag_result["tags_from_source"],
        "tags_from_ai": tag_result["tags_from_ai"],
        "merged": merged,
        "final_source": final_source,
    }


async def _merge_with_existing(
    existing_post: dict,
    new_tags: List[str],
    source_url: Optional[str],
    character_tags: Optional[set] = None,
) -> Optional[dict]:
    """
    Merge new content with an existing post.
    Appends source URLs (with normalised dedup) and any new tags.
    """
    try:
        current_source = existing_post.get("source", "")
        current_tags = [
            t["names"][0] if isinstance(t, dict) else t
            for t in existing_post.get("tags", [])
        ]

        # Merge sources with similarity detection
        new_source = current_source
        if source_url:
            for url in source_url.split("\n"):
                url = url.strip()
                if url:
                    new_source = source_utils.append_source(new_source, url)

        # Merge tags (deduplicate)
        merged_tags = list(current_tags)
        for tag in new_tags:
            if not any(t.lower() == tag.lower() for t in merged_tags):
                merged_tags.append(tag)

        # Ensure character tags have proper category
        if character_tags:
            for tag in character_tags:
                await szurubooru.ensure_tag(tag, "character")

        # Only update if there are changes
        if merged_tags != current_tags or new_source != current_source:
            result = await szurubooru.update_post(
                post_id=existing_post["id"],
                version=existing_post["version"],
                tags=merged_tags,
                source=new_source,
            )
            if "error" in result:
                logger.warning("Failed to merge with existing post %d: %s",
                               existing_post["id"], result["error"])
                return existing_post
            return result

        return existing_post

    except Exception:
        logger.exception("Error merging with existing post %d", existing_post["id"])
        return existing_post


async def _create_relations(job: Job, created_posts: List[dict]) -> None:
    """Create bidirectional relations between all posts in a multi-file upload."""
    logger.info("Job %s: Creating relations between %d posts", job.id, len(created_posts))
    post_ids = [p["post"]["id"] for p in created_posts]
    for post_info in created_posts:
        post = post_info["post"]
        other_ids = [pid for pid in post_ids if pid != post["id"]]
        if other_ids:
            result = await szurubooru.update_post(
                post_id=post["id"],
                version=post["version"],
                relations=other_ids,
            )
            if "error" in result:
                logger.warning("Job %s: Failed to create relations for post %d: %s",
                               job.id, post["id"], result["error"])
            else:
                post_info["post"]["version"] = result.get("version", post["version"])


# ---------------------------------------------------------------------------
# Status helpers
# ---------------------------------------------------------------------------


def _progress_for_status(status: JobStatus) -> int:
    if status == JobStatus.TAGGING:
        return 50
    if status == JobStatus.UPLOADING:
        return 75
    return 0


async def _set_status(job: Job, status: JobStatus) -> None:
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one()
        j.status = status
        j.updated_at = datetime.now(timezone.utc)
        await db.commit()
    progress = _progress_for_status(status)
    await publish_job_update(job_id=job.id, status=status.value, progress=progress if progress else None)


async def _check_job_status(job: Job) -> Optional[JobStatus]:
    """Check the current status of a job in the database."""
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one_or_none()
        if j:
            return j.status
        return None


async def _abort_if_paused_or_stopped(job: Job) -> bool:
    """Return True if the job has been paused or stopped externally."""
    current_status = await _check_job_status(job)
    if current_status in (JobStatus.PAUSED, JobStatus.STOPPED):
        logger.info("Job %s was %s, aborting processing", job.id, current_status.value)
        return True
    return False


async def _fail_job(
    job: Job,
    error: str,
    *,
    max_retries: int = 0,
    retry_delay: float = 0.0,
) -> None:
    """
    Mark a job as failed and, if configured, schedule an automatic retry using the same job ID.
    When retry_delay > 0, the job remains in FAILED status during the delay, then is set to PENDING.
    """
    expected_retry_count: int
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one()

        # Increment retry counter
        current_retries = j.retry_count or 0
        current_retries += 1
        j.retry_count = current_retries
        expected_retry_count = current_retries

        should_retry = max_retries > 0 and current_retries <= max_retries

        j.error_message = error[:4000]
        j.updated_at = datetime.now(timezone.utc)

        if should_retry and retry_delay > 0:
            # Keep job as FAILED during delay - will be set to PENDING after delay
            j.status = JobStatus.FAILED
        elif should_retry:
            # Immediate retry - set to PENDING now
            j.status = JobStatus.PENDING
        else:
            j.status = JobStatus.FAILED

        await db.commit()

    if should_retry and retry_delay > 0:
        async def _delayed_retry() -> None:
            # Wait for the delay, then set job to PENDING if it's still eligible
            await asyncio.sleep(retry_delay)
            async with async_session() as db:
                result = await db.execute(select(Job).where(Job.id == job.id))
                j = result.scalar_one_or_none()
                if not j:
                    return
                # Only retry if still in FAILED status and retry count hasn't changed
                if j.status != JobStatus.FAILED:
                    return
                if (j.retry_count or 0) != expected_retry_count:
                    return
                # Set to PENDING so worker can pick it up
                j.status = JobStatus.PENDING
                j.updated_at = datetime.now(timezone.utc)
                await db.commit()
            # Set retries_exhausted=False since we're retrying
            await publish_job_update(
                job_id=job.id, 
                status="pending", 
                progress=0, 
                error=error[:500],
                retries_exhausted=False
            )

        asyncio.create_task(_delayed_retry())
        # Publish FAILED status immediately so UI shows the error
        # Set retries_exhausted=False since we're retrying
        await publish_job_update(
            job_id=job.id, 
            status="failed", 
            progress=0, 
            error=error[:500],
            retries_exhausted=False
        )
    elif should_retry:
        # Immediate retry without delay
        # Set retries_exhausted=False since we're retrying
        await publish_job_update(
            job_id=job.id, 
            status="pending", 
            progress=0, 
            error=error[:500],
            retries_exhausted=False
        )
    else:
        logger.error("Job %s failed: %s", job.id, error[:200])
        # All retries exhausted - set retries_exhausted=True and include retry_count
        await publish_job_update(
            job_id=job.id, 
            status="failed", 
            progress=0, 
            error=error[:500],
            retries_exhausted=True,
            retry_count=current_retries
        )


async def _complete_job(
    job: Job,
    szuru_post_id: int,
    tags: List[str],
    tags_from_source: List[str],
    tags_from_ai: List[str],
    related_post_ids: Optional[List[int]] = None,
    stored_sources: Optional[str] = None,
    was_merge: bool = False,
) -> None:
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one()
        j.status = JobStatus.MERGED if was_merge else JobStatus.COMPLETED
        j.szuru_post_id = szuru_post_id
        # Exclude primary post from relations so a post is never its own relation
        raw = related_post_ids or []
        j.related_post_ids = [pid for pid in raw if pid != szuru_post_id]
        j.was_merge = 1 if was_merge else 0
        j.tags_applied = json.dumps(tags)
        j.tags_from_source = json.dumps(tags_from_source)
        j.tags_from_ai = json.dumps(tags_from_ai)
        if stored_sources:
            j.source_override = stored_sources

        j.updated_at = datetime.now(timezone.utc)
        await db.commit()
    logger.info("Job %s completed -> Szuru post %d (related: %s)",
                job.id, szuru_post_id, related_post_ids or [])
    await publish_job_update(
        job_id=job.id,
        status="merged" if was_merge else "completed",
        progress=100,
        szuru_post_id=szuru_post_id,
        related_post_ids=related_post_ids,
        tags=tags,
        was_merge=was_merge,
    )
