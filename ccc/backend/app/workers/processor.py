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
from typing import List

from sqlalchemy import select

from app.config import get_settings
from app.database import Job, JobStatus, JobType, async_session
from app.services import downloader, szurubooru, tagger

logger = logging.getLogger(__name__)
settings = get_settings()

_running = True

# Mime-extension mapping for images (used to decide if WD14 tagging applies).
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tiff"}
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".avi", ".mov"}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


async def start_worker() -> None:
    """Main worker loop – polls for pending jobs."""
    global _running
    _running = True
    logger.info("Worker started.")

    while _running:
        try:
            job = await _claim_next_job()
            if job:
                await _process_job(job)
            else:
                await asyncio.sleep(2)  # nothing to do – wait
        except asyncio.CancelledError:
            break
        except Exception:
            logger.exception("Worker loop error")
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
        return job


async def _process_job(job: Job) -> None:
    """Run the full pipeline for a single job."""
    job_dir = os.path.join(settings.job_data_dir, str(job.id))
    os.makedirs(job_dir, exist_ok=True)

    try:
        # ---- Step 1: Acquire files ----
        files: List[Path] = []
        source_url = job.url
        metadata = {}

        if job.job_type == JobType.URL:
            dl = await downloader.download_url(job.url, job_dir)
            files = dl.files
            source_url = dl.source_url or job.url
            metadata = dl.metadata

            if not files:
                await _fail_job(job, dl.error or "No files downloaded.")
                return
        else:
            # FILE job – file was already saved during upload.
            for fn in os.listdir(job_dir):
                fp = Path(job_dir) / fn
                if fp.is_file() and not fn.endswith(".json"):
                    files.append(fp)

            if not files:
                await _fail_job(job, "No files found in job directory.")
                return

        # ---- Step 2: Tag (if enabled and image) ----
        await _set_status(job, JobStatus.TAGGING)

        all_tags: List[str] = []
        safety = job.safety or "unsafe"

        # Pull any tags from metadata (e.g. gallery-dl parsed tags).
        if metadata:
            parsed_tags = _extract_tags_from_metadata(metadata)
            all_tags.extend(parsed_tags)

        for fp in files:
            ext = fp.suffix.lower()
            if ext in IMAGE_EXTENSIONS and not job.skip_tagging:
                tag_result = await tagger.tag_image(fp)
                all_tags.extend(tag_result.general_tags)
                all_tags.extend(tag_result.character_tags)
                # Use tagger-derived safety if available.
                if tag_result.safety:
                    safety = tag_result.safety

                # Ensure character tags exist with the correct category.
                for ct in tag_result.character_tags:
                    await szurubooru.ensure_tag(ct, "character")
            elif ext in VIDEO_EXTENSIONS:
                all_tags.append("video")

        # Deduplicate while preserving order.
        seen = set()
        unique_tags = []
        for t in all_tags:
            key = t.strip().lower()
            if key and key not in seen:
                seen.add(key)
                unique_tags.append(t.strip())
        all_tags = unique_tags

        if not all_tags:
            all_tags = ["tagme"]

        # ---- Step 3: Upload to Szurubooru ----
        await _set_status(job, JobStatus.UPLOADING)

        uploaded_post_id = None
        last_error = None

        for fp in files:
            result = await szurubooru.upload_post(
                file_path=fp,
                tags=all_tags,
                safety=safety,
                source=source_url,
            )
            if "error" in result:
                error_text = result["error"]
                # Szurubooru duplicate detection – not a fatal error.
                if any(kw in error_text.lower() for kw in ("already uploaded", "duplicate", "content checksum")):
                    logger.info("Duplicate detected for %s: %s", fp.name, error_text)
                    last_error = f"Duplicate: {error_text}"
                else:
                    last_error = error_text
            else:
                uploaded_post_id = result.get("id")

        # ---- Step 4: Finalise ----
        if uploaded_post_id:
            await _complete_job(job, uploaded_post_id, all_tags)
        elif last_error:
            await _fail_job(job, last_error)
        else:
            await _fail_job(job, "Upload produced no result.")

    except Exception as exc:
        logger.exception("Job %s failed", job.id)
        await _fail_job(job, str(exc))
    finally:
        # Cleanup temp files.
        try:
            if os.path.isdir(job_dir):
                shutil.rmtree(job_dir, ignore_errors=True)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _extract_tags_from_metadata(metadata: dict) -> List[str]:
    """Best-effort tag extraction from gallery-dl / yt-dlp metadata."""
    tags = []
    # gallery-dl often stores tags as a list.
    raw = metadata.get("tags", [])
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, str):
                tags.append(item)
            elif isinstance(item, dict) and "name" in item:
                tags.append(item["name"])
    elif isinstance(raw, str):
        tags.extend(t.strip() for t in raw.split(",") if t.strip())
    return tags


async def _set_status(job: Job, status: JobStatus) -> None:
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one()
        j.status = status
        j.updated_at = datetime.now(timezone.utc)
        await db.commit()


async def _fail_job(job: Job, error: str) -> None:
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one()
        j.status = JobStatus.FAILED
        j.error_message = error[:4000]  # Truncate long errors
        j.updated_at = datetime.now(timezone.utc)
        await db.commit()
    logger.error("Job %s failed: %s", job.id, error[:200])


async def _complete_job(job: Job, szuru_post_id: int, tags: List[str]) -> None:
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one()
        j.status = JobStatus.COMPLETED
        j.szuru_post_id = szuru_post_id
        j.tags_applied = json.dumps(tags)
        j.updated_at = datetime.now(timezone.utc)
        await db.commit()
    logger.info("Job %s completed -> Szuru post %d", job.id, szuru_post_id)
