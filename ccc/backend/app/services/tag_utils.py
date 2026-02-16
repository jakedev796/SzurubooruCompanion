"""
Tag parsing, normalization, and deduplication utilities.

Centralises the logic for:
- Parsing ``category:name`` prefixed tags from browser-ext / initial_tags
- Extracting tags from gallery-dl / yt-dlp metadata
- Deduplicating tags (case-insensitive, first occurrence wins)
- Handling the ``tagme`` sentinel
"""

import json
import re
from typing import Dict, List, Optional, Set, Tuple

from app.services import tag_categories

CATEGORY_PREFIX_RE = re.compile(
    r"^(artist|character|copyright|general|meta):(.+)$",
    re.IGNORECASE,
)
VALID_CATEGORIES = frozenset(tag_categories.get_szuru_categories())


# ---------------------------------------------------------------------------
# Category prefix helpers
# ---------------------------------------------------------------------------


def parse_category_prefix(raw: str) -> Tuple[Optional[str], str]:
    """
    Parse a ``category:name`` tag string.

    Returns ``(category, name)`` when a valid prefix is found,
    or ``(None, raw_stripped)`` otherwise.
    """
    match = CATEGORY_PREFIX_RE.match(raw.strip())
    if match:
        cat, name = match.group(1).lower(), match.group(2).strip()
        if cat in VALID_CATEGORIES and name:
            return cat, name
    return None, raw.strip()


# ---------------------------------------------------------------------------
# Initial-tag parsing
# ---------------------------------------------------------------------------


def parse_initial_tags(
    initial_tags_json: Optional[str],
) -> Tuple[List[str], List[str], Dict[str, str]]:
    """
    Parse initial tags from the JSON stored in ``Job.initial_tags``.

    Handles ``category:name`` prefixes (e.g. ``artist:setosannnnn``) by
    stripping the prefix and recording the category mapping.

    Returns ``(all_tags, tags_from_source, client_tag_categories)``.
    """
    all_tags: List[str] = []
    tags_from_source: List[str] = []
    client_tag_categories: Dict[str, str] = {}

    if not initial_tags_json:
        return all_tags, tags_from_source, client_tag_categories

    try:
        initial = json.loads(initial_tags_json)
        if not isinstance(initial, list):
            return all_tags, tags_from_source, client_tag_categories
    except (json.JSONDecodeError, TypeError):
        return all_tags, tags_from_source, client_tag_categories

    for t in initial:
        if not isinstance(t, str) or not t.strip():
            continue
        raw = t.strip()
        cat, name = parse_category_prefix(raw)
        if cat:
            all_tags.append(name)
            tags_from_source.append(name)
            client_tag_categories[name.lower()] = cat
        else:
            all_tags.append(raw)
            tags_from_source.append(raw)

    return all_tags, tags_from_source, client_tag_categories


# ---------------------------------------------------------------------------
# Metadata tag extraction
# ---------------------------------------------------------------------------


def _parse_metadata_tag_value(raw: object) -> List[str]:
    """Parse a single metadata tag value (list, dict-with-name, or string) into tag names."""
    out: List[str] = []
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, str):
                out.append(item)
            elif isinstance(item, dict) and "name" in item:
                out.append(item["name"])
    elif isinstance(raw, str):
        out.extend(t for t in re.split(r"[,\s]+", raw) if t.strip())
    return out


def extract_tags_from_metadata(metadata: dict) -> List[str]:
    """
    Best-effort tag extraction from gallery-dl / yt-dlp metadata.

    Includes ``tags`` + all ``tags_*`` keys so categorized tags
    (artist, character, copyright) are present for ``resolve_categories``.
    """
    tags: List[str] = []
    seen: Set[str] = set()
    for key in metadata:
        if key != "tags" and not key.startswith("tags_"):
            continue
        raw = metadata.get(key)
        for name in _parse_metadata_tag_value(raw):
            key_lower = name.strip().lower()
            if key_lower and key_lower not in seen:
                seen.add(key_lower)
                tags.append(name.strip())
    return tags


# ---------------------------------------------------------------------------
# Normalisation & deduplication
# ---------------------------------------------------------------------------


def normalize_category_prefixes(
    tags: List[str], categories: Dict[str, str]
) -> Tuple[List[str], Dict[str, str]]:
    """
    Strip ``category:name`` prefixes from all tags, updating *categories* dict.

    Returns ``(normalized_tags, updated_categories)``.
    """
    normalized: List[str] = []
    for raw in tags:
        cat, name = parse_category_prefix(raw)
        if cat:
            normalized.append(name)
            categories[name.lower()] = cat
        else:
            normalized.append(raw.strip())
    return normalized, categories


def sanitize_tag(tag: str) -> str:
    """
    Sanitize a tag name for Szurubooru compatibility.

    Replaces whitespace with underscores (Szurubooru requires ``^\\S+$``).
    """
    return re.sub(r"\s+", "_", tag.strip())


def deduplicate_tags(tags: List[str]) -> List[str]:
    """
    Deduplicate tags case-insensitively (first occurrence wins).

    Sanitizes all tags (spaces → underscores) and handles ``tagme``:
    removed when real tags exist, kept as sole tag when nothing else
    is present.
    """
    seen: Set[str] = set()
    unique: List[str] = []
    for t in tags:
        sanitized = sanitize_tag(t)
        key = sanitized.lower()
        if key and key not in seen:
            seen.add(key)
            unique.append(sanitized)

    if not unique:
        return ["tagme"]

    without_tagme = [t for t in unique if t.lower() != "tagme"]
    return without_tagme if without_tagme else ["tagme"]
