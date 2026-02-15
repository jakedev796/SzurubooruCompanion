"""
Szurubooru API client.
Handles authentication, post creation, tag creation, and error surfacing.
"""

import base64
import json
import logging
import mimetypes
from pathlib import Path
from typing import Dict, List, Optional

import aiohttp

# Initialize mimetypes to ensure common types are recognized
mimetypes.init()

# Explicitly add common MIME types that might be missing in minimal Docker images
# This ensures detection works even without /etc/mime.types
COMMON_MIME_TYPES = {
    # Images
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
    '.tiff': 'image/tiff',
    '.tif': 'image/tiff',
    '.svg': 'image/svg+xml',
    # Videos
    '.mp4': 'video/mp4',
    '.webm': 'video/webm',
    '.mkv': 'video/x-matroska',
    '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime',
    '.wmv': 'video/x-ms-wmv',
    '.flv': 'video/x-flv',
    # Audio
    '.mp3': 'audio/mpeg',
    '.wav': 'audio/wav',
    '.ogg': 'audio/ogg',
    '.m4a': 'audio/mp4',
}

# Add any missing types to the mimetypes database
for ext, mime in COMMON_MIME_TYPES.items():
    if ext not in mimetypes.types_map:
        mimetypes.add_type(mime, ext)

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Log common MIME types for debugging (after logger is defined)
logger.info("MIME types loaded: .jpg=%s, .png=%s, .mp4=%s", 
             mimetypes.types_map.get('.jpg'), 
             mimetypes.types_map.get('.png'),
             mimetypes.types_map.get('.mp4'))

# ANSI colours for terminal output
RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RESET = "\033[0m"


def _auth_header() -> Dict[str, str]:
    """Build the Szurubooru Token auth header."""
    raw = f"{settings.szuru_username}:{settings.szuru_token}"
    encoded = base64.b64encode(raw.encode()).decode()
    return {"Authorization": f"Token {encoded}"}


# ---------------------------------------------------------------------------
# Connection test
# ---------------------------------------------------------------------------


async def test_connection() -> bool:
    """Return True if we can reach the Szurubooru API and authenticate."""
    url = f"{settings.szuru_url}/api/info"
    try:
        async with aiohttp.ClientSession(headers=_auth_header()) as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    if "serverTime" in data or "config" in data:
                        logger.info("Szurubooru connection OK")
                        return True
                logger.warning("Szurubooru returned %d", resp.status)
                return False
    except Exception as exc:
        logger.error("Szurubooru connection failed: %s", exc)
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
    szuru_api = f"{settings.szuru_url}/api/posts/"
    headers = {**_auth_header(), "Accept": "application/json"}

    metadata: Dict = {"tags": tags, "safety": safety}
    if source:
        metadata["source"] = source

    try:
        data = aiohttp.FormData()
        data.add_field(
            "metadata",
            json.dumps(metadata),
            content_type="application/json",
        )

        with open(file_path, "rb") as f:
            file_bytes = f.read()
        
        # Detect MIME type from file extension
        mime_type, _ = mimetypes.guess_type(str(file_path))
        logger.info("MIME type detection for %s: %s (extension: %s)", file_path.name, mime_type, file_path.suffix)
        if mime_type is None:
            # Fallback to octet-stream if detection fails
            mime_type = "application/octet-stream"
            logger.warning("Could not detect MIME type for %s (suffix: %s), using fallback", file_path.name, file_path.suffix)
        
        data.add_field("content", file_bytes, filename=file_path.name, content_type=mime_type)

        async with aiohttp.ClientSession(headers=headers) as session:
            async with session.post(szuru_api, data=data, timeout=aiohttp.ClientTimeout(total=60)) as resp:
                if resp.status == 200:
                    return await resp.json()
                else:
                    error_text = await resp.text()
                    return {"error": error_text, "status": resp.status}

    except Exception as exc:
        return {"error": str(exc), "status": 0}


# ---------------------------------------------------------------------------
# Tag helpers
# ---------------------------------------------------------------------------


async def ensure_tag(tag_name: str, category: str = "default") -> bool:
    """Create a tag if it doesn't already exist. Returns True on success or already-exists."""
    url = f"{settings.szuru_url}/api/tags"
    headers = {**_auth_header(), "Accept": "application/json", "Content-Type": "application/json"}
    payload = {"names": [tag_name], "category": category}

    try:
        async with aiohttp.ClientSession(headers=headers) as session:
            async with session.post(url, json=payload, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status == 200:
                    return True
                text = await resp.text()
                if "TagAlreadyExistsError" in text or resp.status == 409:
                    return True
                logger.warning("Failed to create tag %s (%s): %s", tag_name, category, text)
                return False
    except Exception as exc:
        logger.warning("Exception creating tag %s: %s", tag_name, exc)
        return False


# ---------------------------------------------------------------------------
# Post retrieval
# ---------------------------------------------------------------------------


async def get_post(post_id: int) -> dict:
    """
    Fetch a post by ID.

    Returns the full post resource including version, tags, source, relations.
    Returns {"error": ..., "status": ...} on failure.
    """
    url = f"{settings.szuru_url}/api/post/{post_id}"
    headers = {**_auth_header(), "Accept": "application/json"}

    try:
        async with aiohttp.ClientSession(headers=headers) as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status == 200:
                    return await resp.json()
                error_text = await resp.text()
                return {"error": error_text, "status": resp.status}
    except Exception as exc:
        return {"error": str(exc), "status": 0}


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

    Args:
        post_id: The ID of the post to update.
        version: Required for optimistic locking (must match current post version).
        tags: If provided, REPLACES existing tags (must fetch and merge manually).
        source: If provided, REPLACES existing source.
        relations: If provided, REPLACES existing relations (list of post IDs).
        safety: If provided, updates the safety rating.

    Returns:
        The updated post JSON on success, or {"error": ..., "status": ...} on failure.
    """
    url = f"{settings.szuru_url}/api/post/{post_id}"
    headers = {**_auth_header(), "Accept": "application/json", "Content-Type": "application/json"}

    payload: Dict = {"version": version}
    if tags is not None:
        payload["tags"] = tags
    if source is not None:
        payload["source"] = source
    if relations is not None:
        payload["relations"] = relations
    if safety is not None:
        payload["safety"] = safety

    try:
        async with aiohttp.ClientSession(headers=headers) as session:
            async with session.put(url, json=payload, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                if resp.status == 200:
                    return await resp.json()
                error_text = await resp.text()
                return {"error": error_text, "status": resp.status}
    except Exception as exc:
        return {"error": str(exc), "status": 0}


# ---------------------------------------------------------------------------
# Reverse image search
# ---------------------------------------------------------------------------


async def reverse_search(file_path: Path) -> dict:
    """
    Perform reverse image search to find exact and similar posts.

    Args:
        file_path: Path to the image file to search for.

    Returns:
        {"exactPost": {...} or None, "similarPosts": [...]} on success,
        or {"error": ..., "status": ...} on failure.
    """
    url = f"{settings.szuru_url}/api/posts/reverse-search"
    headers = {**_auth_header(), "Accept": "application/json"}

    try:
        data = aiohttp.FormData()
        with open(file_path, "rb") as f:
            file_bytes = f.read()
        
        # Detect MIME type from file extension
        mime_type, _ = mimetypes.guess_type(str(file_path))
        if mime_type is None:
            mime_type = "application/octet-stream"
        
        data.add_field("content", file_bytes, filename=file_path.name, content_type=mime_type)

        async with aiohttp.ClientSession(headers=headers) as session:
            async with session.post(url, data=data, timeout=aiohttp.ClientTimeout(total=60)) as resp:
                if resp.status == 200:
                    return await resp.json()
                error_text = await resp.text()
                return {"error": error_text, "status": resp.status}
    except Exception as exc:
        return {"error": str(exc), "status": 0}


# ---------------------------------------------------------------------------
# Checksum search
# ---------------------------------------------------------------------------


async def search_by_checksum(checksum: str) -> List[dict]:
    """
    Search posts by SHA1 content checksum.

    Args:
        checksum: The SHA1 content checksum to search for.

    Returns:
        A list of matching posts, or an empty list if none found.
        Returns [{"error": ..., "status": ...}] on failure.
    """
    url = f"{settings.szuru_url}/api/posts/"
    headers = {**_auth_header(), "Accept": "application/json"}
    params = {"query": f"content-checksum:{checksum}"}

    try:
        async with aiohttp.ClientSession(headers=headers) as session:
            async with session.get(url, params=params, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    # Szurubooru returns {"results": [...]} for list endpoints
                    return data.get("results", [])
                error_text = await resp.text()
                return [{"error": error_text, "status": resp.status}]
    except Exception as exc:
        return [{"error": str(exc), "status": 0}]


# ---------------------------------------------------------------------------
# Source helper
# ---------------------------------------------------------------------------


def append_source(existing_source: Optional[str], new_source: str) -> str:
    """
    Append a new source URL to existing sources (newline-separated).
    Deduplicate if the source already exists.

    Args:
        existing_source: The current source string (may be None or empty).
        new_source: The new source URL to append.

    Returns:
        The combined source string with the new source appended (if not duplicate).
    """
    if not existing_source:
        return new_source

    if not new_source:
        return existing_source

    # Split existing sources by newline and strip whitespace
    existing_sources = [s.strip() for s in existing_source.split("\n") if s.strip()]

    # Check if the new source already exists (case-insensitive comparison)
    new_source_stripped = new_source.strip()
    for existing in existing_sources:
        if existing.lower() == new_source_stripped.lower():
            # Already exists, return unchanged
            return existing_source

    # Append the new source
    existing_sources.append(new_source_stripped)
    return "\n".join(existing_sources)
