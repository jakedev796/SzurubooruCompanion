"""
Szurubooru API client.
Handles authentication, post creation, tag creation, and error surfacing.

Uses a persistent aiohttp session for connection reuse and a two-tier
tag cache (in-memory + PostgreSQL) to minimise redundant API calls.
"""

import asyncio
import base64
import contextvars
import json
import logging
import time
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import quote

import aiohttp

from app.config import get_settings
from app.utils.mime import guess_mime_type

logger = logging.getLogger(__name__)
settings = get_settings()

# ---------------------------------------------------------------------------
# Per-job user context (set by processor, read by _auth_headers)
# ---------------------------------------------------------------------------

_current_user: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    "szuru_user", default=None
)
_current_szuru_token: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    "szuru_token", default=None
)
_current_szuru_url: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    "szuru_url", default=None
)


def set_current_user(username: Optional[str], token: Optional[str] = None, szuru_url: Optional[str] = None) -> None:
    """Set the Szurubooru user context for the current async task."""
    _current_user.set(username)
    _current_szuru_token.set(token)
    _current_szuru_url.set(szuru_url)


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


def _auth_headers() -> Dict[str, str]:
    """Build the Szurubooru Token auth header for the current user context."""
    username = _current_user.get()
    token = _current_szuru_token.get()
    
    if not username or not token:
        raise ValueError("Szurubooru username and token must be set in current context")
    
    raw = f"{username}:{token}"
    encoded = base64.b64encode(raw.encode()).decode()
    return {"Authorization": f"Token {encoded}", "Accept": "application/json"}


# ---------------------------------------------------------------------------
# Persistent HTTP session
# ---------------------------------------------------------------------------

_session: Optional[aiohttp.ClientSession] = None


async def init_session() -> None:
    """Create the persistent aiohttp session.  Call once at startup."""
    global _session
    if _session is None or _session.closed:
        _session = aiohttp.ClientSession()


async def close_session() -> None:
    """Close the persistent aiohttp session.  Call once at shutdown."""
    global _session
    if _session and not _session.closed:
        await _session.close()
    _session = None


async def _request(
    method: str,
    endpoint: str,
    *,
    json_payload: Optional[dict] = None,
    form_data: Optional[aiohttp.FormData] = None,
    params: Optional[dict] = None,
    timeout: float = 30,
    extra_headers: Optional[Dict[str, str]] = None,
) -> dict:
    """
    Make an authenticated request to the Szurubooru API.

    Returns the JSON response on success, or {"error": ..., "status": ...} on failure.
    """
    global _session
    if _session is None or _session.closed:
        await init_session()

    szuru_url = _current_szuru_url.get()
    if not szuru_url:
        raise ValueError("szuru_url not set in current context - user config must be loaded")
    url = f"{szuru_url}{endpoint}"

    # Per-request auth headers (session has no baked-in auth for multi-user support)
    headers: Dict[str, str] = _auth_headers()
    if extra_headers:
        headers.update(extra_headers)
    if json_payload is not None and form_data is None:
        headers["Content-Type"] = "application/json"

    try:
        kwargs: Dict[str, Any] = {
            "timeout": aiohttp.ClientTimeout(total=timeout),
            "headers": headers,
        }
        if json_payload is not None and form_data is None:
            kwargs["json"] = json_payload
        if form_data is not None:
            kwargs["data"] = form_data
        if params is not None:
            kwargs["params"] = params

        async with _session.request(method, url, **kwargs) as resp:
            if resp.status == 200:
                return await resp.json()
            error_text = await resp.text()
            return {"error": error_text, "status": resp.status}
    except Exception as exc:
        return {"error": str(exc), "status": 0}


# ---------------------------------------------------------------------------
# Tag cache (in-memory + PostgreSQL)
# ---------------------------------------------------------------------------

TAG_CACHE_TTL_SECONDS = 30 * 24 * 3600  # 30 days


@dataclass
class _TagCacheEntry:
    category: str        # lowercased
    verified_at: float   # time.time() epoch


_tag_cache: Dict[str, _TagCacheEntry] = {}  # key: tag_name.lower()


async def load_tag_cache() -> None:
    """Warm-start the in-memory tag cache from PostgreSQL.  Call at startup."""
    from app.database import TagCache, async_session
    from sqlalchemy import select

    cutoff = datetime.now(timezone.utc) - timedelta(seconds=TAG_CACHE_TTL_SECONDS)
    async with async_session() as db:
        result = await db.execute(
            select(TagCache).where(TagCache.verified_at >= cutoff)
        )
        rows = result.scalars().all()
        for row in rows:
            _tag_cache[row.tag_name.lower()] = _TagCacheEntry(
                category=row.category.lower(),
                verified_at=row.verified_at.timestamp(),
            )
    logger.info("Tag cache: loaded %d entries from database", len(_tag_cache))


async def _update_tag_cache_db(tag_name: str, category: str) -> None:
    """Upsert a tag cache entry into PostgreSQL."""
    from app.database import TagCache, async_session
    from sqlalchemy.dialects.postgresql import insert as pg_insert

    now = datetime.now(timezone.utc)
    try:
        async with async_session() as db:
            stmt = pg_insert(TagCache).values(
                tag_name=tag_name.lower(),
                category=category.lower(),
                verified_at=now,
            ).on_conflict_do_update(
                index_elements=["tag_name"],
                set_={"category": category.lower(), "verified_at": now},
            )
            await db.execute(stmt)
            await db.commit()
    except Exception:
        logger.debug("Failed to persist tag cache entry for %s", tag_name, exc_info=True)


def _cache_tag(tag_name: str, category: str) -> None:
    """Update the in-memory cache for a tag."""
    _tag_cache[tag_name.lower()] = _TagCacheEntry(
        category=category.lower(),
        verified_at=time.time(),
    )


# ---------------------------------------------------------------------------
# Connection test
# ---------------------------------------------------------------------------


async def test_connection() -> bool:
    """Return True if we can reach the Szurubooru API and authenticate."""
    result = await _request("GET", "/api/info", timeout=10)
    if "error" not in result and ("serverTime" in result or "config" in result):
        logger.info("Szurubooru connection OK")
        return True
    logger.warning("Szurubooru connection failed: %s", result.get("error", "unknown"))
    return False


# ---------------------------------------------------------------------------
# Upload post
# ---------------------------------------------------------------------------


async def upload_post(
    file_path: Path,
    tags: List[str],
    safety: str = "unsafe",
    source: Optional[str] = None,
) -> Dict:
    """
    Upload a file as a new post to Szurubooru.
    Returns the post JSON on success, or {"error": ..., "status": ...} on failure.
    """
    metadata: Dict = {"tags": tags, "safety": safety}
    if source:
        metadata["source"] = source

    data = aiohttp.FormData()
    data.add_field(
        "metadata",
        json.dumps(metadata),
        content_type="application/json",
    )

    with open(file_path, "rb") as f:
        file_bytes = f.read()

    mime_type = guess_mime_type(str(file_path))
    data.add_field("content", file_bytes, filename=file_path.name, content_type=mime_type)

    return await _request("POST", "/api/posts/", form_data=data, timeout=60)


# ---------------------------------------------------------------------------
# Tag helpers
# ---------------------------------------------------------------------------


async def _get_tag_by_name(tag_name: str) -> Optional[Dict]:
    """Fetch a tag by exact name. Returns the tag resource or None."""
    result = await _request(
        "GET",
        f"/api/tags/?query=name:{quote(tag_name, safe='')}&limit=1",
        timeout=10,
    )
    if "error" in result:
        return None
    results = result.get("results") or []
    for tag in results:
        names = tag.get("names") or []
        if any(n.lower() == tag_name.lower() for n in names):
            return tag
    return None


async def ensure_tag(tag_name: str, category: str = "default") -> bool:
    """
    Create a tag if it doesn't already exist, or update its category if needed.

    Uses a two-tier cache (memory + PostgreSQL) with 30-day TTL to skip
    redundant API calls.
    """
    cache_key = tag_name.lower()
    now = time.time()

    # Check in-memory cache
    entry = _tag_cache.get(cache_key)
    if (entry
            and entry.category == category.lower()
            and (now - entry.verified_at) < TAG_CACHE_TTL_SECONDS):
        return True  # Fresh cache hit — skip all API calls

    # Cache miss or stale — try to create the tag
    result = await _request(
        "POST", "/api/tags",
        json_payload={"names": [tag_name], "category": category},
        timeout=10,
    )

    if "error" not in result:
        # Tag created successfully
        _cache_tag(tag_name, category)
        await _update_tag_cache_db(tag_name, category)
        return True

    error_text = result.get("error", "")
    if "TagAlreadyExistsError" not in error_text and result.get("status") != 409:
        logger.warning("Failed to create tag %s (%s): %s", tag_name, category, error_text)
        return False

    # Tag already exists — fetch it and check category
    existing = await _get_tag_by_name(tag_name)
    if not existing:
        # Can't fetch but it exists — cache optimistically
        _cache_tag(tag_name, category)
        await _update_tag_cache_db(tag_name, category)
        return True

    current_cat = existing.get("category")
    if isinstance(current_cat, dict):
        current_cat = (current_cat.get("name") or "").strip().lower()
    else:
        current_cat = (current_cat or "").strip().lower()

    if current_cat == category.lower():
        # Category already matches
        _cache_tag(tag_name, category)
        await _update_tag_cache_db(tag_name, category)
        return True

    # Category differs — update via PUT using the tag *name* (not numeric ID)
    logger.debug("Tag %s category mismatch: szuru=%s, desired=%s — updating",
                 tag_name, current_cat, category)
    version = existing.get("version")
    if version is None:
        logger.warning("Tag %s has no version field, cannot update category", tag_name)
        _cache_tag(tag_name, category)
        await _update_tag_cache_db(tag_name, category)
        return True

    encoded_name = quote(tag_name, safe="")
    put_result = await _request(
        "PUT", f"/api/tag/{encoded_name}",
        json_payload={"version": version, "category": category},
        timeout=10,
    )
    if "error" not in put_result:
        logger.debug("Updated tag %s category: %s -> %s", tag_name, current_cat, category)
    else:
        logger.warning("Failed to update tag %s category: %s", tag_name, put_result["error"])

    _cache_tag(tag_name, category)
    await _update_tag_cache_db(tag_name, category)
    return True


# ---------------------------------------------------------------------------
# Batch tag ensure (concurrent with semaphore)
# ---------------------------------------------------------------------------

_TAG_CONCURRENCY = 10


async def ensure_tags_batch(tags_with_categories: List[Tuple[str, str]]) -> None:
    """
    Ensure multiple tags exist concurrently.

    Args:
        tags_with_categories: List of ``(tag_name, category)`` tuples.
    """
    if not tags_with_categories:
        return

    sem = asyncio.Semaphore(_TAG_CONCURRENCY)

    async def _limited(name: str, cat: str) -> None:
        async with sem:
            await ensure_tag(name, cat)

    await asyncio.gather(
        *(_limited(n, c) for n, c in tags_with_categories)
    )


# ---------------------------------------------------------------------------
# Post retrieval and listing
# ---------------------------------------------------------------------------


async def get_post(post_id: int) -> dict:
    """Fetch a post by ID. Returns the full post resource or {"error": ..., "status": ...}."""
    return await _request("GET", f"/api/post/{post_id}", timeout=10)


async def search_posts(query: str, limit: int = 100, offset: int = 0) -> dict:
    """
    Search/list posts. Returns {"results": [...], "query": "...", ...} or {"error": ..., "status": ...}.
    """
    return await _request(
        "GET",
        "/api/posts/",
        params={"query": query, "limit": limit, "offset": offset},
        timeout=60,
    )


async def download_post_content(post_id: int, dest_path: Path) -> Optional[Path]:
    """
    Fetch post by ID, then download its content to dest_path using contentUrl.
    Returns dest_path on success, None on failure. Caller must set user context.
    """
    post = await get_post(post_id)
    if "error" in post:
        logger.warning("Failed to get post %d: %s", post_id, post.get("error"))
        return None
    content_url = post.get("contentUrl") or post.get("content_url")
    if not content_url:
        logger.warning("Post %d has no contentUrl", post_id)
        return None
    szuru_url = _current_szuru_url.get()
    if not szuru_url:
        return None
    if content_url.startswith("http://") or content_url.startswith("https://"):
        url = content_url
    else:
        base = szuru_url.rstrip("/")
        url = f"{base}{content_url}" if content_url.startswith("/") else f"{base}/{content_url}"
    global _session
    if _session is None or _session.closed:
        await init_session()
    try:
        headers = _auth_headers()
        async with _session.get(
            url, headers=headers, timeout=aiohttp.ClientTimeout(total=120)
        ) as resp:
            if resp.status != 200:
                logger.warning("Post %d content fetch failed: HTTP %s", post_id, resp.status)
                return None
            content = await resp.read()
    except Exception as exc:
        logger.warning("Post %d content download failed: %s", post_id, exc)
        return None
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    dest_path.write_bytes(content)
    return dest_path


# ---------------------------------------------------------------------------
# Post update
# ---------------------------------------------------------------------------


async def update_post(
    post_id: int,
    version: int,
    tags: Optional[List[str]] = None,
    source: Optional[str] = None,
    relations: Optional[List[int]] = None,
    safety: Optional[str] = None,
) -> dict:
    """
    Update an existing post.
    Returns the updated post JSON on success, or {"error": ..., "status": ...} on failure.
    """
    payload: Dict = {"version": version}
    if tags is not None:
        payload["tags"] = tags
    if source is not None:
        payload["source"] = source
    if relations is not None:
        payload["relations"] = relations
    if safety is not None:
        payload["safety"] = safety

    return await _request("PUT", f"/api/post/{post_id}", json_payload=payload, timeout=30)


# ---------------------------------------------------------------------------
# Reverse image search
# ---------------------------------------------------------------------------


async def reverse_search(file_path: Path) -> dict:
    """
    Perform reverse image search to find exact and similar posts.
    Returns {"exactPost": {...} or None, "similarPosts": [...]} or {"error": ...}.
    """
    data = aiohttp.FormData()
    with open(file_path, "rb") as f:
        file_bytes = f.read()

    mime_type = guess_mime_type(str(file_path))
    data.add_field("content", file_bytes, filename=file_path.name, content_type=mime_type)

    return await _request("POST", "/api/posts/reverse-search", form_data=data, timeout=60)


# ---------------------------------------------------------------------------
# Checksum search
# ---------------------------------------------------------------------------


async def search_by_checksum(checksum: str) -> List[dict]:
    """
    Search posts by SHA1 content checksum.
    Returns a list of matching posts, or an empty list if none found.
    """
    result = await _request(
        "GET", "/api/posts/",
        params={"query": f"content-checksum:{checksum}"},
        timeout=30,
    )
    if "error" in result:
        return [result]
    return result.get("results", [])


# ---------------------------------------------------------------------------
# Tag categories
# ---------------------------------------------------------------------------


async def fetch_tag_categories(szuru_url: str, username: str, token: str) -> dict:
    """
    Fetch tag categories from a Szurubooru/Oxibooru instance.

    Uses the provided credentials directly (not the per-job context vars),
    since this is called from the settings endpoint with user-supplied creds.

    Returns {"results": [...]} with the category list, or {"error": ...} on failure.
    """
    global _session
    if _session is None or _session.closed:
        await init_session()

    raw = f"{username}:{token}"
    encoded = base64.b64encode(raw.encode()).decode()
    headers = {"Authorization": f"Token {encoded}", "Accept": "application/json"}

    try:
        url = f"{szuru_url}/api/tag-categories"
        async with _session.get(url, headers=headers, timeout=aiohttp.ClientTimeout(total=10)) as resp:
            data = await resp.json()
            if resp.status == 200:
                return data
            return {"error": f"HTTP {resp.status}", "details": data}
    except asyncio.TimeoutError:
        logger.error("Timeout fetching tag categories from %s", szuru_url)
        return {"error": "Timeout"}
    except Exception as exc:
        logger.exception("Error fetching tag categories from %s", szuru_url)
        return {"error": str(exc)}
