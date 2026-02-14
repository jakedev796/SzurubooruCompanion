"""
WD14 Tagger using wdtagger in-process.
Results are filtered by confidence threshold and max-tag count.
"""

import asyncio
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Optional wdtagger import; WD14 is disabled at runtime if unavailable
try:
    import torch
    from wdtagger import Tagger
    WD14_AVAILABLE = True
except ImportError:
    WD14_AVAILABLE = False
    Tagger = None  # type: ignore[misc, assignment]
    torch = None  # type: ignore[assignment]


@dataclass
class TagResult:
    """Parsed tagging result for a single image."""
    general_tags: List[str] = field(default_factory=list)
    character_tags: List[str] = field(default_factory=list)
    safety: str = "unsafe"
    raw: Optional[Dict] = None


# Lazy-initialized in-process tagger (singleton)
_tagger: Optional["Tagger"] = None
_tagger_lock = asyncio.Lock()


def _get_tagger():
    """Initialize and return the wdtagger Tagger (blocking). Called from executor."""
    global _tagger
    if _tagger is not None:
        return _tagger
    if not WD14_AVAILABLE or Tagger is None:
        raise RuntimeError("WD14 Tagger not available. Install: pip install wdtagger torch torchvision")
    model_name = settings.wd14_model
    device = torch.device("cuda") if torch.cuda.is_available() else torch.device("cpu")
    logger.info("WD14 Tagger using device: %s", device)
    _tagger = Tagger(model_repo=model_name)
    return _tagger


async def _ensure_tagger():
    """Ensure tagger is initialized (thread-safe)."""
    loop = asyncio.get_event_loop()
    async with _tagger_lock:
        if _tagger is None:
            await loop.run_in_executor(None, _get_tagger)


def _clean_tag(tag: str) -> str:
    """Normalise a tag string (strip whitespace, remove trailing confidence, replace spaces with underscores)."""
    tag = re.sub(r"\s*\([\d.]+\)$", "", str(tag))
    tag = tag.strip().replace(" ", "_")
    return tag if len(tag) > 1 else ""


def _process_wdtagger_result(result) -> TagResult:
    """Convert wdtagger result (general_tag_data, character_tag_data, rating_data) to TagResult."""
    out = TagResult()
    threshold = settings.wd14_confidence_threshold
    max_tags = settings.wd14_max_tags

    if hasattr(result, "general_tag_data") and result.general_tag_data:
        items = sorted(result.general_tag_data.items(), key=lambda kv: kv[1], reverse=True)
        for tag, confidence in items:
            if confidence < threshold or len(out.general_tags) >= max_tags:
                if confidence < threshold:
                    break
                continue
            cleaned = _clean_tag(tag)
            if cleaned:
                out.general_tags.append(cleaned)

    if hasattr(result, "character_tag_data") and result.character_tag_data:
        for tag, confidence in result.character_tag_data.items():
            if confidence >= threshold:
                cleaned = _clean_tag(tag)
                if cleaned:
                    out.character_tags.append(cleaned)

    if hasattr(result, "rating_data") and result.rating_data:
        rating_data = result.rating_data
        best_rating = "general"
        best_conf = 0.0
        for rating, conf in rating_data.items():
            if conf > best_conf:
                best_conf = conf
                best_rating = rating
        if best_rating == "explicit":
            out.safety = "unsafe"
        elif best_rating in ("questionable", "sensitive"):
            out.safety = "sketchy"
        else:
            out.safety = "safe"

    return out


async def tag_image(image_path: Path) -> TagResult:
    """
    Tag an image using WD14 (wdtagger) in-process.
    Runs tagging in a thread so the event loop is not blocked.
    """
    if not settings.wd14_enabled:
        logger.debug("WD14 tagging disabled; skipping %s", image_path.name)
        return TagResult()

    if not WD14_AVAILABLE:
        logger.warning("WD14 Tagger not available (wdtagger/torch not installed); skipping %s", image_path.name)
        return TagResult()

    try:
        await _ensure_tagger()
        loop = asyncio.get_event_loop()
        path_str = str(image_path)
        result = await loop.run_in_executor(None, lambda: _tagger.tag(path_str))
        if result is None:
            return TagResult()
        return _process_wdtagger_result(result)
    except Exception as exc:
        logger.warning("WD14 tagger failed for %s: %s", image_path.name, exc)
        return TagResult()
