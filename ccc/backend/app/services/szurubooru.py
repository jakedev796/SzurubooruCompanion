"""
Szurubooru API client.
Handles authentication, post creation, tag creation, and error surfacing.
"""

import base64
import json
import logging
from pathlib import Path
from typing import Dict, List, Optional

import aiohttp

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

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
        data.add_field("content", file_bytes, filename=file_path.name)

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
