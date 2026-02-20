"""
Browse service for the swiper feature.
Uses gallery-dl to search booru sites and returns standardized browse items.
"""

import asyncio
import hashlib
import json
import logging
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import SwiperSeenItem
from app.sites.base import SiteHandler
from app.sites.registry import get_handler_by_name

logger = logging.getLogger(__name__)
settings = get_settings()

BROWSE_BATCH_SIZE = 40  # Over-fetch to account for seen items


@dataclass
class BrowseItem:
    """A single browsable item from a booru site."""
    site_name: str
    external_id: str
    post_url: str
    thumbnail_url: str
    preview_url: str
    file_url: str
    tags: List[str] = field(default_factory=list)
    rating: str = "unsafe"
    width: Optional[int] = None
    height: Optional[int] = None
    source: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "site_name": self.site_name,
            "external_id": self.external_id,
            "post_url": self.post_url,
            "thumbnail_url": self.thumbnail_url,
            "preview_url": self.preview_url,
            "file_url": self.file_url,
            "tags": self.tags,
            "rating": self.rating,
            "width": self.width,
            "height": self.height,
            "source": self.source,
        }


@dataclass
class BrowseResult:
    """Result of a browse request."""
    items: List[BrowseItem] = field(default_factory=list)
    has_more: bool = True
    page: int = 1


async def browse_site(
    site_name: str,
    tags: str,
    rating: str,
    page: int,
    limit: int,
    user_id: str,
    user_config: Optional[Dict[str, Dict[str, str]]],
    db: AsyncSession,
    sort: str = "newest",
) -> BrowseResult:
    """
    Browse a site for content, filtering out already-seen items.

    1. Get the handler for the site
    2. Build search URL
    3. Try Redis cache first
    4. If not cached, run gallery-dl to get metadata
    5. Parse results and filter out seen items
    6. Cache and return
    """
    handler = get_handler_by_name(site_name, user_config)
    if not handler or not handler.supports_browse:
        logger.warning("Site '%s' does not support browsing", site_name)
        return BrowseResult(items=[], has_more=False, page=page)

    # Load seen IDs for this user+site
    seen_ids = await get_seen_ids(user_id, site_name, db)

    # Try cache first
    cache_key = _build_cache_key(user_id, site_name, tags, rating, page, sort)
    cached = await _get_cached(cache_key)
    if cached is not None:
        # Filter out any newly-seen items from cached results
        items = [item for item in cached if item.external_id not in seen_ids]
        return BrowseResult(items=items[:limit], has_more=len(items) > limit, page=page)

    # Build search URL and fetch via gallery-dl
    search_url = handler.build_search_url(tags, rating, page, sort)
    if not search_url:
        return BrowseResult(items=[], has_more=False, page=page)

    raw_items = await _run_gallery_dl_browse(handler, search_url, BROWSE_BATCH_SIZE)

    # Parse into BrowseItems
    items: List[BrowseItem] = []
    seen_in_batch: set = set()
    for metadata in raw_items:
        parsed = handler.parse_browse_item(metadata)
        if not parsed:
            continue
        eid = parsed["external_id"]
        # Dedupe within batch
        if eid in seen_in_batch:
            continue
        seen_in_batch.add(eid)

        items.append(BrowseItem(
            site_name=site_name,
            external_id=eid,
            post_url=parsed["post_url"],
            thumbnail_url=parsed.get("thumbnail_url", ""),
            preview_url=parsed.get("preview_url", ""),
            file_url=parsed.get("file_url", ""),
            tags=parsed.get("tags", []),
            rating=parsed.get("rating", "unsafe"),
            width=parsed.get("width"),
            height=parsed.get("height"),
            source=parsed.get("source"),
        ))

    # Cache all parsed items before filtering
    await _set_cached(cache_key, items, ttl=300)

    # Filter out seen items
    unseen = [item for item in items if item.external_id not in seen_ids]

    return BrowseResult(
        items=unseen[:limit],
        has_more=len(unseen) > limit or len(raw_items) >= BROWSE_BATCH_SIZE,
        page=page,
    )


async def get_seen_ids(user_id: str, site_name: str, db: AsyncSession) -> Set[str]:
    """Get set of external IDs the user has already seen on this site."""
    result = await db.execute(
        select(SwiperSeenItem.external_id).where(
            SwiperSeenItem.user_id == user_id,
            SwiperSeenItem.site_name == site_name,
        )
    )
    return {row[0] for row in result.fetchall()}


async def mark_seen(
    user_id: str,
    site_name: str,
    external_id: str,
    action: str,
    db: AsyncSession,
) -> None:
    """Record that user has seen this item. Upserts on conflict."""
    from sqlalchemy.dialects.postgresql import insert

    stmt = insert(SwiperSeenItem).values(
        user_id=user_id,
        site_name=site_name,
        external_id=external_id,
        action=action,
    ).on_conflict_do_update(
        constraint="uq_swiper_seen",
        set_={"action": action},
    )
    await db.execute(stmt)
    await db.commit()


async def _run_gallery_dl_browse(
    handler: SiteHandler,
    search_url: str,
    max_items: int,
) -> List[dict]:
    """
    Run gallery-dl --dump-json --no-download on a search URL.
    Returns raw metadata dicts from gallery-dl output.
    """
    opts = handler.gallery_dl_options()
    cmd = [
        "gallery-dl",
        "--dump-json",
        "--no-download",
        "--range", f"1-{max_items}",
        *opts,
        search_url,
    ]

    logger.info("Browsing %s: %s (range 1-%d)", handler.name, search_url, max_items)

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=120)

        if proc.returncode != 0:
            err = stderr.decode(errors="replace").strip()
            logger.warning("gallery-dl browse exited %d for %s: %s", proc.returncode, handler.name, err)
            return []

        output = stdout.decode("utf-8", errors="replace").strip()
        if not output:
            logger.info("gallery-dl browse produced no output for %s", handler.name)
            return []

        # Parse JSON output
        try:
            data = json.loads(output)
        except json.JSONDecodeError as e:
            logger.warning("Failed to parse gallery-dl browse JSON for %s: %s", handler.name, e)
            return []

        if isinstance(data, dict):
            data = [data]

        # Unwrap gallery-dl's [type_id, dict] or [type_id, url, dict] format
        results: List[dict] = []
        for raw_item in data:
            item = _unwrap_gallery_dl_item(raw_item)
            if item:
                results.append(item)

        logger.info("gallery-dl browse returned %d items for %s", len(results), handler.name)
        return results

    except asyncio.TimeoutError:
        logger.error("gallery-dl browse timed out for %s", handler.name)
        return []
    except FileNotFoundError:
        logger.error("gallery-dl binary not found")
        return []
    except Exception:
        logger.exception("gallery-dl browse unexpected error for %s", handler.name)
        return []


def _unwrap_gallery_dl_item(raw) -> Optional[dict]:
    """Unwrap gallery-dl JSON item format to get the metadata dict."""
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, list) and len(raw) >= 2 and isinstance(raw[-1], dict):
        return raw[-1]
    return None


# ---------------------------------------------------------------------------
# Redis caching
# ---------------------------------------------------------------------------

_redis = None


async def _get_redis():
    """Lazy-init Redis connection for browse caching."""
    global _redis
    if _redis is None:
        try:
            import redis.asyncio as aioredis
            _redis = aioredis.from_url(settings.redis_url, decode_responses=True)
        except Exception as e:
            logger.warning("Failed to connect to Redis for browse cache: %s", e)
            return None
    return _redis


def _build_cache_key(user_id: str, site_name: str, tags: str, rating: str, page: int, sort: str = "newest") -> str:
    tags_hash = hashlib.md5(tags.encode()).hexdigest()[:8]
    return f"swiper:browse:{user_id}:{site_name}:{tags_hash}:{rating}:{sort}:{page}"


async def _get_cached(key: str) -> Optional[List[BrowseItem]]:
    """Get cached browse results from Redis."""
    r = await _get_redis()
    if not r:
        return None
    try:
        raw = await r.get(key)
        if raw:
            items_data = json.loads(raw)
            return [BrowseItem(**item) for item in items_data]
    except Exception as e:
        logger.debug("Browse cache miss for %s: %s", key, e)
    return None


async def _set_cached(key: str, items: List[BrowseItem], ttl: int = 300) -> None:
    """Cache browse results in Redis."""
    r = await _get_redis()
    if not r:
        return
    try:
        data = json.dumps([item.to_dict() for item in items])
        await r.set(key, data, ex=ttl)
    except Exception as e:
        logger.debug("Failed to cache browse results: %s", e)
