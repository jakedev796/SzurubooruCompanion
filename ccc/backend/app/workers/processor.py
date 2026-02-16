"""
Background job processor.
Polls the database for PENDING jobs and runs the download -> tag -> upload pipeline.
"""

import asyncio
import json
import logging
import os
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Set
from urllib.parse import urlparse, parse_qs, urlencode, urlunparse

from sqlalchemy import select

from app.config import get_settings
from app.database import Job, JobStatus, JobType, async_session
from app.services import downloader, szurubooru, tag_categories, tagger
from app.api.events import publish_job_update

logger = logging.getLogger(__name__)
settings = get_settings()

# Browser-ext can send tags as "category:name" (e.g. artist:setosannnnn). We parse these and set the tag category in Szurubooru.
CATEGORY_PREFIX_RE = re.compile(
    r"^(artist|character|copyright|general|meta):(.+)$",
    re.IGNORECASE,
)
VALID_CATEGORIES = frozenset(tag_categories.SZURU_CATEGORIES)

_running = True

# Mime-extension mapping for images (used to decide if WD14 tagging applies).
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tiff"}
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".avi", ".mov"}


# ---------------------------------------------------------------------------
# URL Normalization for duplicate detection
# ---------------------------------------------------------------------------


def _normalize_url_for_comparison(url: str) -> str:
    """
    Normalize a URL for similarity comparison.
    
    This function extracts identifying information from URLs to detect
    "similar enough" URLs that refer to the same content:
    
    - Twitter/X status URLs: Extract status ID (e.g., x.com/user/status/123/photo/1 -> x.com/status/123)
    - Twitter media URLs: Extract media ID from pbs.twimg.com/media/ABC?... -> pbs.twimg.com/media/ABC
    - Other URLs: Strip query parameters and trailing slashes
    
    Args:
        url: The URL to normalize
        
    Returns:
        A normalized form suitable for comparison
    """
    if not url:
        return ""
    
    url = url.strip()
    
    try:
        parsed = urlparse(url)
        netloc = parsed.netloc.lower()
        path = parsed.path.rstrip("/")
        
        # Twitter/X status URLs - extract the status ID
        # Patterns: x.com/USER/status/ID or x.com/USER/status/ID/photo/N
        if netloc in ("x.com", "twitter.com"):
            status_match = re.search(r"/status/(\d+)", path, re.IGNORECASE)
            if status_match:
                status_id = status_match.group(1)
                return f"x.com/status/{status_id}"
        
        # Twitter media URLs - extract the media ID
        # Pattern: pbs.twimg.com/media/MEDIA_ID?format=...&name=...
        if netloc == "pbs.twimg.com" or netloc == "video.twimg.com":
            media_match = re.match(r"/media/([A-Za-z0-9_-]+)", path, re.IGNORECASE)
            if media_match:
                media_id = media_match.group(1)
                return f"twimg.com/media/{media_id}"
        
        # For other URLs, strip query parameters and use path only
        # This helps with URLs that have different tracking params but same content
        return f"{netloc}{path}"
        
    except Exception:
        # If parsing fails, return the original URL stripped
        return url.strip().lower()


def _get_normalized_sources(source_string: Optional[str]) -> Set[str]:
    """
    Parse a source string (newline-separated URLs) into a set of normalized forms.
    
    Args:
        source_string: The source field from a post (may be None or empty)
        
    Returns:
        Set of normalized URL strings for comparison
    """
    if not source_string:
        return set()
    
    normalized = set()
    for url in source_string.split("\n"):
        url = url.strip()
        if url:
            normalized.add(_normalize_url_for_comparison(url))
    
    return normalized


def _source_already_exists(existing_source: Optional[str], new_source: str) -> bool:
    """
    Check if a new source URL already exists (or is similar to) existing sources.
    
    Args:
        existing_source: The current source string (newline-separated URLs)
        new_source: The new source URL to check
        
    Returns:
        True if the new source is already present or similar to an existing one
    """
    if not new_source:
        return True  # Empty source, nothing to add
    
    existing_normalized = _get_normalized_sources(existing_source)
    new_normalized = _normalize_url_for_comparison(new_source)
    
    return new_normalized in existing_normalized


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
            # Publish SSE update
            await publish_job_update(job_id=job.id, status="downloading")
        return job


async def _process_job(job: Job) -> None:
    """
    Run the full pipeline for a single job.
    
    Two-phase processing:
    1. Phase 1: Extract direct media URLs from the source
    2. Phase 2: Download each file, check for duplicates, and create posts
    3. Create relations between posts from multi-file sources
    """
    job_dir = os.path.join(settings.job_data_dir, str(job.id))
    os.makedirs(job_dir, exist_ok=True)

    try:
        # Check if job was paused/stopped before starting
        if await _abort_if_paused_or_stopped(job):
            return

        # ---- Phase 1: Extract media URLs ----
        extracted_media: List[downloader.ExtractedMedia] = []
        
        if job.job_type == JobType.URL:
            logger.info("Job %s: Phase 1 - Extracting media URLs from %s", job.id, job.url)
            extracted_media = await downloader.extract_media_urls(job.url)
            logger.info("Job %s: Found %d media file(s)", job.id, len(extracted_media))
        else:
            # FILE job – file was already saved during upload.
            # Create a synthetic ExtractedMedia for the uploaded file
            for fn in os.listdir(job_dir):
                fp = Path(job_dir) / fn
                if fp.is_file() and not fn.endswith(".json"):
                    extracted_media.append(downloader.ExtractedMedia(
                        url=f"file://{fn}",
                        source_url=f"file://{fn}",
                        filename=fn,
                        metadata=None
                    ))
                    break  # Only one file for FILE jobs

            if not extracted_media:
                await _fail_job(job, "No files found in job directory.")
                return

        # ---- Phase 2: Process each media file ----
        created_posts: List[dict] = []
        all_sources: List[str] = []
        last_error: Optional[str] = None

        for idx, media in enumerate(extracted_media):
            logger.info("Job %s: Processing media %d/%d - %s", job.id, idx + 1, len(extracted_media), media.filename)
            
            # Create a subdirectory for each media file to avoid conflicts
            media_dir = os.path.join(job_dir, f"media_{idx}")
            os.makedirs(media_dir, exist_ok=True)

            try:
                # Check if job was paused/stopped before processing this media
                if await _abort_if_paused_or_stopped(job):
                    return

                # Download the file
                if job.job_type == JobType.URL:
                    # Check if we have a direct media URL different from the page URL
                    # (e.g., for Twitter/Misskey multi-file posts)
                    if media.source_url and media.source_url != media.url:
                        # Download directly from the media URL for individual file
                        logger.info("Job %s: Downloading from direct media URL: %s", job.id, media.source_url)
                        dl = await downloader.download_direct_media_url(
                            media.source_url, 
                            media_dir, 
                            filename=media.filename
                        )
                        files = dl.files
                        metadata = {**(media.metadata or {}), **dl.metadata}
                    else:
                        # Use gallery-dl for other sites
                        dl = await downloader.download_url(media.url, media_dir, source_url=media.source_url)
                        files = dl.files
                        metadata = {**(media.metadata or {}), **dl.metadata}
                else:
                    # FILE job - file already exists in job_dir
                    files = [Path(job_dir) / media.filename]
                    metadata = {}

                if not files:
                    logger.warning("Job %s: No files downloaded for media %d", job.id, idx)
                    last_error = f"No files downloaded for {media.filename}"
                    continue

                # Process the first file (typically only one per media)
                fp = files[0]

                # Check if job was paused/stopped before tagging
                if await _abort_if_paused_or_stopped(job):
                    return

                # Tag the file
                await _set_status(job, JobStatus.TAGGING)
                
                all_tags: List[str] = []
                tags_from_source: List[str] = []
                tags_from_ai: List[str] = []
                safety = job.safety or "unsafe"

                # Tags from client (e.g. browser-ext page extractor).
                # Supports "category:name" format (e.g. artist:setosannnnn) so we set the right Szurubooru category.
                client_tag_categories: Dict[str, str] = {}
                if job.initial_tags:
                    try:
                        initial = json.loads(job.initial_tags)
                        if isinstance(initial, list):
                            for t in initial:
                                if not isinstance(t, str) or not t.strip():
                                    continue
                                raw = t.strip()
                                match = CATEGORY_PREFIX_RE.match(raw)
                                if match:
                                    cat, name = match.group(1).lower(), match.group(2).strip()
                                    if cat in VALID_CATEGORIES and name:
                                        all_tags.append(name)
                                        tags_from_source.append(name)
                                        client_tag_categories[name.lower()] = cat
                                    else:
                                        all_tags.append(raw)
                                        tags_from_source.append(raw)
                                else:
                                    all_tags.append(raw)
                                    tags_from_source.append(raw)
                    except (json.JSONDecodeError, TypeError):
                        pass

                # Pull tags from metadata
                if metadata:
                    parsed_tags = _extract_tags_from_metadata(metadata)
                    for t in parsed_tags:
                        if t.strip():
                            all_tags.append(t.strip())
                            tags_from_source.append(t.strip())

                # WD14 tagging for images
                wd14_character_tags: set = set()
                ext = fp.suffix.lower()
                if ext in IMAGE_EXTENSIONS and not job.skip_tagging:
                    tag_result = await tagger.tag_image(fp)
                    for t in tag_result.general_tags + tag_result.character_tags:
                        if t.strip():
                            all_tags.append(t.strip())
                            tags_from_ai.append(t.strip())
                    wd14_character_tags.update(tag_result.character_tags)
                    if tag_result.safety:
                        safety = tag_result.safety
                elif ext in VIDEO_EXTENSIONS:
                    all_tags.append("video")
                    tags_from_source.append("video")

                # Normalize any "category:name" tags (from initial or metadata) to bare name + category
                # so we never send the literal "artist:username" to Szurubooru.
                normalized_tags: List[str] = []
                for t in all_tags:
                    raw = t.strip()
                    match = CATEGORY_PREFIX_RE.match(raw)
                    if match:
                        cat, name = match.group(1).lower(), match.group(2).strip()
                        if cat in VALID_CATEGORIES and name:
                            normalized_tags.append(name)
                            client_tag_categories[name.lower()] = cat
                            continue
                    normalized_tags.append(raw)
                all_tags = normalized_tags

                # Deduplicate tags
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
                else:
                    # Remove tagme when we have other tags (e.g. from AI or source); only keep tagme when it's the sole tag
                    all_tags = [t for t in all_tags if t.strip().lower() != "tagme"]
                    if not all_tags:
                        all_tags = ["tagme"]

                # Resolve tag categories (metadata + client category:name overrides)
                tag_to_category = tag_categories.resolve_categories(
                    all_tags, metadata=metadata, job_url=job.url
                )
                for t in wd14_character_tags:
                    tag_to_category[t] = "character"
                for tag in all_tags:
                    tag_lower = tag.strip().lower()
                    if tag_lower in client_tag_categories:
                        tag_to_category[tag] = client_tag_categories[tag_lower]

                for tag in all_tags:
                    category = tag_to_category.get(tag) or settings.szuru_default_tag_category
                    await szurubooru.ensure_tag(tag, category)

                # Check if job was paused/stopped before uploading
                if await _abort_if_paused_or_stopped(job):
                    return

                # ---- Upload to Szurubooru ----
                await _set_status(job, JobStatus.UPLOADING)

                # Build source string - combine original page URL with direct media URL
                # For Twitter/Misskey: source = "direct_media_url\noriginal_page_url"
                # For other sites: source = "direct_media_url" or original URL
                primary_source = (job.source_override or "").strip() or None
                direct_media_url = media.source_url.strip() if media.source_url else None
                original_page_url = job.url.strip() if job.url else None
                
                # Combine: direct media URL + original page URL + any override
                final_source = _build_source_string(direct_media_url, original_page_url, primary_source)

                # Check for duplicates using reverse search
                existing = await szurubooru.reverse_search(fp)
                post: Optional[dict] = None

                if existing.get("exactPost"):
                    # Merge with existing post
                    logger.info("Job %s: Duplicate found for %s, merging with existing post %d",
                               job.id, media.filename, existing["exactPost"]["id"])
                    post = await _merge_with_existing(
                        existing["exactPost"],
                        all_tags,
                        final_source,
                        wd14_character_tags
                    )
                    if post:
                        all_sources.append(media.source_url)
                        created_posts.append({
                            "post": post,
                            "tags": all_tags,
                            "tags_from_source": tags_from_source,
                            "tags_from_ai": tags_from_ai,
                            "merged": True,
                        })
                        post = None  # skip the generic created_posts.append below
                else:
                    # Create new post
                    result = await szurubooru.upload_post(
                        file_path=fp,
                        tags=all_tags,
                        safety=safety,
                        source=final_source,
                    )
                    if "error" in result:
                        error_text = result["error"]
                        if any(kw in error_text.lower() for kw in ("already uploaded", "duplicate", "content checksum")):
                            logger.info("Job %s: Upload duplicate detected for %s", job.id, media.filename)
                            last_error = f"Duplicate: {error_text}"
                        else:
                            logger.warning("Job %s: Upload failed for %s: %s", job.id, media.filename, error_text)
                            last_error = error_text
                    else:
                        post = result
                        all_sources.append(media.source_url)
                        logger.info("Job %s: Created post %d for %s", job.id, post["id"], media.filename)

                if post:
                    created_posts.append({
                        "post": post,
                        "tags": all_tags,
                        "tags_from_source": tags_from_source,
                        "tags_from_ai": tags_from_ai,
                        "merged": False,
                    })

            except Exception as exc:
                logger.exception("Job %s: Failed to process media %d (%s)", job.id, idx, media.filename)
                last_error = str(exc)
                # Continue with other files

        # ---- Create relations between posts ----
        if len(created_posts) > 1:
            logger.info("Job %s: Creating relations between %d posts", job.id, len(created_posts))
            post_ids = [p["post"]["id"] for p in created_posts]
            for post_info in created_posts:
                post = post_info["post"]
                other_ids = [pid for pid in post_ids if pid != post["id"]]
                if other_ids:
                    result = await szurubooru.update_post(
                        post_id=post["id"],
                        version=post["version"],
                        relations=other_ids
                    )
                    if "error" in result:
                        logger.warning("Job %s: Failed to create relations for post %d: %s",
                                      job.id, post["id"], result["error"])
                    else:
                        # Update version for potential future updates
                        post_info["post"]["version"] = result.get("version", post["version"])

        # ---- Finalise ----
        if created_posts:
            primary_post = created_posts[0]
            related_ids = [p["post"]["id"] for p in created_posts[1:]]
            # Store the same source string we uploaded to Szurubooru (primary post)
            primary_media = extracted_media[0]
            stored_sources = _build_source_string(
                primary_media.source_url.strip() if primary_media.source_url else None,
                job.url.strip() if job.url else None,
                (job.source_override or "").strip() or None,
            )
            await _complete_job(
                job,
                primary_post["post"]["id"],
                primary_post["tags"],
                primary_post["tags_from_source"],
                primary_post["tags_from_ai"],
                related_post_ids=related_ids,
                stored_sources=stored_sources,
                was_merge=primary_post.get("merged", False),
            )
        elif last_error:
            await _fail_job(job, last_error)
        else:
            await _fail_job(job, "No posts created.")

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


async def _merge_with_existing(
    existing_post: dict, 
    new_tags: List[str], 
    source_url: Optional[str],
    character_tags: Optional[set] = None
) -> Optional[dict]:
    """
    Merge new content with existing post.
    - Append source URL if not already present (using similarity detection)
    - Append any new tags
    
    Args:
        existing_post: The existing post dict from Szurubooru
        new_tags: Tags to potentially add
        source_url: Source URL to potentially add (may be newline-separated)
        character_tags: Set of character tags to ensure proper category
    
    Returns:
        Updated post dict or None on failure
    """
    try:
        # Get current post data
        current_source = existing_post.get("source", "")
        current_tags = [t["names"][0] if isinstance(t, dict) else t for t in existing_post.get("tags", [])]
        
        # Merge sources with similarity detection
        new_source = current_source
        if source_url:
            # Split the new source into individual URLs
            new_urls = [u.strip() for u in source_url.split("\n") if u.strip()]
            
            for url in new_urls:
                # Only add if this URL (or a similar one) doesn't already exist
                if not _source_already_exists(new_source, url):
                    new_source = szurubooru.append_source(new_source, url)
        
        # Merge tags (deduplicate) - always merge tags regardless of source changes
        merged_tags = list(current_tags)
        for tag in new_tags:
            tag_lower = tag.lower()
            if not any(t.lower() == tag_lower for t in merged_tags):
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
                source=new_source
            )
            if "error" in result:
                logger.warning("Failed to merge with existing post %d: %s", 
                              existing_post["id"], result["error"])
                return existing_post
            return result
        else:
            # No changes needed
            return existing_post
            
    except Exception as exc:
        logger.exception("Error merging with existing post %d", existing_post["id"])
        return existing_post


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _build_source_string(
    direct_media_url: Optional[str],
    original_page_url: Optional[str],
    override_source: Optional[str] = None
) -> Optional[str]:
    """
    Build the source string for Szurubooru.
    
    The source should contain:
    1. Direct media URL (the actual image/video file URL)
    2. Original page URL (the tweet/note/page where it was found)
    3. Any override source provided by the user
    
    All URLs are combined with newlines, deduplicated.
    """
    sources: List[str] = []
    
    # Add override source first (highest priority)
    if override_source:
        sources.append(override_source.strip())
    
    # Add direct media URL
    if direct_media_url:
        url = direct_media_url.strip()
        if url and url not in sources:
            sources.append(url)
    
    # Add original page URL
    if original_page_url:
        url = original_page_url.strip()
        if url and url not in sources:
            # Also check for normalized duplicates (trailing slash)
            normalized = url.rstrip("/")
            if not any(s.rstrip("/") == normalized for s in sources):
                sources.append(url)
    
    if not sources:
        return None
    
    return "\n".join(sources)


def _combine_sources(primary: Optional[str], grab: Optional[str]) -> Optional[str]:
    """Combine primary (actual image source) and grab (page we got it from). Szurubooru source is one string; use newline to list both."""
    if not primary and not grab:
        return None
    if not primary:
        return grab
    if not grab:
        return primary
    if primary.strip().rstrip("/") == grab.strip().rstrip("/"):
        return primary
    return f"{primary}\n{grab}"


def _extract_tags_from_metadata(metadata: dict) -> List[str]:
    """Best-effort tag extraction from gallery-dl / yt-dlp metadata."""
    tags = []
    raw = metadata.get("tags", [])
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, str):
                tags.append(item)
            elif isinstance(item, dict) and "name" in item:
                tags.append(item["name"])
    elif isinstance(raw, str):
        # gallery-dl may use space-separated (e.g. yande.re) or comma-separated.
        tags.extend(t for t in re.split(r"[,\s]+", raw) if t.strip())
    return tags


async def _set_status(job: Job, status: JobStatus) -> None:
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one()
        j.status = status
        j.updated_at = datetime.now(timezone.utc)
        await db.commit()
    # Publish SSE update
    await publish_job_update(job_id=job.id, status=status.value)


async def _check_job_status(job: Job) -> Optional[JobStatus]:
    """
    Check the current status of a job in the database.
    Returns the current status, or None if job was deleted.
    Used to detect if a job was paused/stopped during processing.
    """
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one_or_none()
        if j:
            return j.status
        return None


async def _abort_if_paused_or_stopped(job: Job) -> bool:
    """
    Check if job has been paused or stopped. Returns True if job should abort.
    If job is paused or stopped, leaves the status as-is and returns True.
    """
    current_status = await _check_job_status(job)
    if current_status in (JobStatus.PAUSED, JobStatus.STOPPED):
        logger.info("Job %s was %s, aborting processing", job.id, current_status.value)
        return True
    return False


async def _fail_job(job: Job, error: str) -> None:
    async with async_session() as db:
        result = await db.execute(select(Job).where(Job.id == job.id))
        j = result.scalar_one()
        j.status = JobStatus.FAILED
        j.error_message = error[:4000]  # Truncate long errors
        j.updated_at = datetime.now(timezone.utc)
        await db.commit()
    logger.error("Job %s failed: %s", job.id, error[:200])
    # Publish SSE update
    await publish_job_update(job_id=job.id, status="failed", error=error[:500])


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
        j.related_post_ids = related_post_ids or []
        j.was_merge = 1 if was_merge else 0
        j.tags_applied = json.dumps(tags)
        j.tags_from_source = json.dumps(tags_from_source)
        j.tags_from_ai = json.dumps(tags_from_ai)
        if stored_sources:
            j.source_override = stored_sources  # Full source list we uploaded to Szurubooru
        j.updated_at = datetime.now(timezone.utc)
        await db.commit()
    logger.info("Job %s completed -> Szuru post %d (related: %s)", 
                job.id, szuru_post_id, related_post_ids or [])
    # Publish SSE update
    await publish_job_update(
        job_id=job.id,
        status="merged" if was_merge else "completed",
        szuru_post_id=szuru_post_id,
        tags=tags,
        was_merge=was_merge,
    )
