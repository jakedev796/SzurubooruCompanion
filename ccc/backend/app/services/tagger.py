"""
WD14 Tagger client.
Communicates with the wd14-tagger-api HTTP service to tag images.
Results are filtered by confidence threshold and max-tag count.
"""

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import aiohttp

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


@dataclass
class TagResult:
    """Parsed tagging result for a single image."""
    general_tags: List[str] = field(default_factory=list)
    character_tags: List[str] = field(default_factory=list)
    safety: str = "unsafe"
    raw: Optional[Dict] = None


async def tag_image(image_path: Path) -> TagResult:
    """
    Send an image to the WD14 Tagger API and return parsed tags.
    The wd14-tagger-api exposes a POST endpoint that accepts an image file.
    """
    if not settings.wd14_enabled:
        logger.debug("WD14 tagging disabled; skipping %s", image_path.name)
        return TagResult()

    tagger_url = settings.wd14_tagger_url.rstrip("/")
    endpoint = f"{tagger_url}/api/predict"

    try:
        async with aiohttp.ClientSession() as session:
            data = aiohttp.FormData()
            data.add_field(
                "file",
                open(image_path, "rb"),
                filename=image_path.name,
            )
            async with session.post(endpoint, data=data, timeout=aiohttp.ClientTimeout(total=60)) as resp:
                if resp.status != 200:
                    body = await resp.text()
                    logger.warning("WD14 tagger returned %d: %s", resp.status, body)
                    return TagResult()

                payload = await resp.json()
                return _parse_tagger_response(payload)

    except aiohttp.ClientError as exc:
        logger.warning("WD14 tagger connection error: %s", exc)
        return TagResult()
    except Exception as exc:
        logger.exception("Unexpected error calling WD14 tagger")
        return TagResult()


def _parse_tagger_response(payload: Dict) -> TagResult:
    """
    Parse the JSON response from the WD14 tagger API.
    Expected shape varies by implementation; adapt as needed once tested.
    Common shape:
      { "general": {"tag": score, ...},
        "character": {"tag": score, ...},
        "rating": {"general": 0.8, "sensitive": 0.1, ...} }
    """
    result = TagResult(raw=payload)
    threshold = settings.wd14_confidence_threshold
    max_tags = settings.wd14_max_tags

    # --- General tags ---
    general_raw = payload.get("general", {})
    if isinstance(general_raw, dict):
        sorted_tags = sorted(general_raw.items(), key=lambda kv: kv[1], reverse=True)
        for tag, score in sorted_tags:
            if score < threshold:
                break
            cleaned = _clean_tag(tag)
            if cleaned and len(result.general_tags) < max_tags:
                result.general_tags.append(cleaned)

    # --- Character tags ---
    character_raw = payload.get("character", {})
    if isinstance(character_raw, dict):
        for tag, score in character_raw.items():
            if score >= threshold:
                cleaned = _clean_tag(tag)
                if cleaned:
                    result.character_tags.append(cleaned)

    # --- Safety / rating ---
    rating_raw = payload.get("rating", {})
    if isinstance(rating_raw, dict):
        best_rating = max(rating_raw, key=rating_raw.get, default="general")
        if best_rating == "explicit":
            result.safety = "unsafe"
        elif best_rating in ("questionable", "sensitive"):
            result.safety = "sketchy"
        else:
            result.safety = "safe"

    return result


def _clean_tag(tag: str) -> str:
    """Normalise a tag string (strip whitespace, replace spaces with underscores)."""
    import re
    tag = re.sub(r"\s*\([\d.]+\)$", "", tag)  # remove trailing confidence "(0.95)"
    tag = tag.strip().replace(" ", "_")
    return tag if len(tag) > 1 else ""
