"""
Resolve tag names to the user's Szurubooru category names.
Uses categorized tag lists from gallery-dl metadata when extractor.*.tags is enabled.
Source names (author, circle, studio, etc.) are mapped in code to logical slots;
each slot's Szurubooru category name comes from env (SZURU_CATEGORY_*).
"""

import re
from typing import Dict, List, Optional, Tuple

from app.config import get_settings

# Logical slots we support; env gives the user's Szurubooru category name for each.
SLOTS = ("general", "artist", "character", "copyright", "meta")

# Source names (from gallery-dl metadata keys tags_<name>) that map to each slot. In code so we
# normalize author/circle/studio etc. to the right slot; user only sets their category names in env.
SOURCE_NAMES_FOR_SLOT: Dict[str, List[str]] = {
    "general": ["general", "genre", "medium"],
    "artist": ["artist", "author", "studio"],
    "character": ["character"],
    "copyright": ["copyright", "circle"],
    "meta": ["meta", "faults"],
}


def get_szuru_categories() -> Tuple[str, ...]:
    """User's Szurubooru category names from env (so they can use e.g. Creator instead of artist)."""
    s = get_settings()
    out: List[str] = []
    for slot in SLOTS:
        name = (getattr(s, f"szuru_category_{slot}", None) or "").strip() or slot
        out.append(name)
    return tuple(out)


def _get_source_to_szuru_mapping() -> Dict[str, str]:
    """
    Build source_name -> user's Szurubooru category name.
    Source names (author, circle, etc.) are fixed in SOURCE_NAMES_FOR_SLOT; env supplies the
    category name the user's instance uses for each slot.
    """
    s = get_settings()
    mapping: Dict[str, str] = {}
    for slot in SLOTS:
        user_cat = (getattr(s, f"szuru_category_{slot}", None) or "").strip() or slot
        for source_name in SOURCE_NAMES_FOR_SLOT.get(slot, [slot]):
            mapping[source_name.lower()] = user_cat
    return mapping


def resolve_categories(
    tag_names: List[str],
    metadata: Optional[dict] = None,
    job_url: Optional[str] = None,
    user_category_mappings: Optional[Dict[str, str]] = None,
) -> Dict[str, str]:
    """
    Resolve each tag to the user's Szurubooru category name.
    When metadata has categorized lists (tags_artist, tags_author, etc.), we map those source
    names to slots via SOURCE_NAMES_FOR_SLOT, then to the user's category name.

    Args:
        tag_names: List of tag names to categorize
        metadata: Optional metadata dict from downloader
        job_url: Optional job URL (for debugging)
        user_category_mappings: Per-user category mappings from database (e.g., {"general": "general", "artist": "creator"})
                                If None, falls back to ENV settings.
    """
    # Use per-user mappings if provided, otherwise fall back to ENV
    if user_category_mappings:
        # Build source_to_szuru mapping from user's settings
        source_to_szuru: Dict[str, str] = {}
        for slot in SLOTS:
            user_cat = user_category_mappings.get(slot, slot)
            for source_name in SOURCE_NAMES_FOR_SLOT.get(slot, [slot]):
                source_to_szuru[source_name.lower()] = user_cat
        default = user_category_mappings.get("general", "general")
    else:
        # Fallback to "general" if not in user categories
        user_categories = get_szuru_categories()
        default = "general"
        if default not in user_categories:
            default = user_categories[0] if user_categories else "general"
        source_to_szuru = _get_source_to_szuru_mapping()

    result: Dict[str, str] = {t: default for t in tag_names if t.strip()}
    if not result or not metadata:
        return result
    result_lower = {t.lower(): t for t in result}

    def category_for_meta_key(key: str) -> Optional[str]:
        if key == "tags":
            return source_to_szuru.get("general")
        if key.startswith("tags_"):
            source_cat = key[5:].lower()
            return source_to_szuru.get(source_cat)
        return None

    meta_keys = [k for k in metadata if k == "tags" or (k.startswith("tags_") and metadata.get(k))]
    # Process flat/general first, then specific (artist, character, etc.) so specific categories are not overwritten by tags_general
    meta_keys.sort(key=lambda k: (0 if k in ("tags", "tags_general") else 1, k))

    for meta_key in meta_keys:
        category = category_for_meta_key(meta_key)
        if not category:
            continue
        raw = metadata.get(meta_key)
        if isinstance(raw, list):
            for item in raw:
                name = item if isinstance(item, str) else (item.get("name") if isinstance(item, dict) else None)
                if name:
                    key = name.strip().lower()
                    if key in result_lower:
                        result[result_lower[key]] = category
        elif isinstance(raw, str):
            for part in re.split(r"[,\s]+", raw):
                key = part.strip().lower()
                if key and key in result_lower:
                    result[result_lower[key]] = category

    return result


# Backwards compatibility.
SZURU_CATEGORIES = ("general", "artist", "copyright", "character", "meta")
