"""
Source URL handling for Szurubooru posts.
Builds, deduplicates, and merges source strings (newline-separated URLs).

Uses site-handler normalization so that URL variants like
``sankakucomplex.com/post/123`` vs ``www.sankakucomplex.com/post/123``
are treated as duplicates.
"""

from typing import List, Optional, Set
from urllib.parse import urlparse

from app.sites import normalize_url_for_comparison as _site_normalize_url


# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------


def normalize_for_comparison(url: str) -> str:
    """
    Normalize a URL for similarity comparison.
    Delegates to the site handler first; falls back to stripping query params
    and trailing slashes.
    """
    if not url:
        return ""
    url = url.strip()

    result = _site_normalize_url(url)
    if result is not None:
        return result

    try:
        parsed = urlparse(url)
        return f"{parsed.netloc.lower()}{parsed.path.rstrip('/')}"
    except Exception:
        return url.lower()


def get_normalized_set(source_string: Optional[str]) -> Set[str]:
    """Parse a newline-separated source string into a set of normalized forms."""
    if not source_string:
        return set()
    return {
        normalize_for_comparison(u)
        for u in source_string.split("\n")
        if u.strip()
    }


# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------


def source_already_exists(existing_source: Optional[str], new_url: str) -> bool:
    """Return True if *new_url* (or a normalized equivalent) is already in *existing_source*."""
    if not new_url:
        return True
    return normalize_for_comparison(new_url) in get_normalized_set(existing_source)


def append_source(existing: Optional[str], url: str) -> str:
    """Append *url* to *existing* (newline-separated) if not already present."""
    url = url.strip()
    if not url:
        return existing or ""
    if not existing:
        return url
    if source_already_exists(existing, url):
        return existing
    return f"{existing}\n{url}"


def build_source_string(
    direct_media_url: Optional[str],
    original_page_url: Optional[str],
    override_source: Optional[str] = None,
) -> Optional[str]:
    """
    Build the source string for a Szurubooru post.

    Order: override → direct media URL → original page URL.
    Duplicates (including normalised variants such as ``www.`` prefixes)
    are suppressed.
    """
    sources: List[str] = []
    seen: Set[str] = set()

    def _add(raw: Optional[str]) -> None:
        if not raw:
            return
        raw = raw.strip()
        if not raw:
            return
        norm = normalize_for_comparison(raw)
        if norm not in seen:
            seen.add(norm)
            sources.append(raw)

    _add(override_source)
    _add(direct_media_url)
    _add(original_page_url)

    return "\n".join(sources) if sources else None
