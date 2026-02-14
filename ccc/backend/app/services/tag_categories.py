"""
Resolve tag names to Szurubooru categories (general, artist, copyright, character, meta).
Uses categorized tag lists from gallery-dl metadata when available (e.g. extractor.yandere.tags).
"""

from typing import Dict, List, Optional

from app.config import get_settings

# Szurubooru category names we use.
SZURU_CATEGORIES = ("general", "artist", "copyright", "character", "meta")

# Metadata keys from gallery-dl when extractor.*.tags is enabled (e.g. yande.re).
# Process general first so artist/character/copyright can override (same tag can appear in multiple).
METADATA_CATEGORY_KEYS = (
    ("tags_general", "general"),
    ("tags", "general"),
    ("tags_artist", "artist"),
    ("tags_character", "character"),
    ("tags_copyright", "copyright"),
    ("tags_circle", "copyright"),
    ("tags_meta", "meta"),
)


def resolve_categories(
    tag_names: List[str],
    metadata: Optional[dict] = None,
    job_url: Optional[str] = None,
) -> Dict[str, str]:
    """
    Resolve each tag to a Szurubooru category.
    When metadata contains categorized lists (from gallery-dl with extractor.*.tags),
    uses those; otherwise assigns SZURU_DEFAULT_TAG_CATEGORY to all.
    """
    settings = get_settings()
    default = settings.szuru_default_tag_category
    if default not in SZURU_CATEGORIES:
        default = "general"

    result: Dict[str, str] = {t: default for t in tag_names if t.strip()}
    if not result or not metadata:
        return result

    # Build tag -> category from metadata categorized lists.
    result_lower = {t.lower(): t for t in result}
    for meta_key, category in METADATA_CATEGORY_KEYS:
        raw = metadata.get(meta_key)
        if raw is None:
            continue
        if isinstance(raw, list):
            for item in raw:
                name = item if isinstance(item, str) else (item.get("name") if isinstance(item, dict) else None)
                if name:
                    key = name.strip().lower()
                    if key in result_lower:
                        result[result_lower[key]] = category
        elif isinstance(raw, str):
            for part in raw.replace(",", " ").split():
                key = part.strip().lower()
                if key and key in result_lower:
                    result[result_lower[key]] = category

    return result
