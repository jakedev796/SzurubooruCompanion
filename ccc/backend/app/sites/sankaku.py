"""Sankaku (sankaku.app / sankakucomplex.com) handler."""

import re
from typing import Optional
from urllib.parse import urlparse

from app.sites.base import CredentialSpec, SiteHandler

# Domains that should all normalise to www.sankakucomplex.com
# Note: chan.sankakucomplex.com uses different post ID format (numeric) and should NOT be normalized
_SANKAKU_DOMAINS = {"sankakucomplex.com", "www.sankakucomplex.com", "sankaku.app", "www.sankaku.app"}


class SankakuHandler(SiteHandler):
    name = "sankaku"
    gallery_dl_extractor = "sankaku"
    gallery_dl_tag_options = [("tags", "standard")]
    credentials = [
        CredentialSpec("username"),
        CredentialSpec("password"),
    ]

    def matches_url(self, url: str) -> bool:
        lower = url.lower()
        return "sankaku.app" in lower or "sankakucomplex.com" in lower

    def normalize_url(self, url: str) -> str:
        """
        Rewrite Sankaku domains to www.sankakucomplex.com (required by gallery-dl).

        Note: chan.sankakucomplex.com uses numeric post IDs and should NOT be normalized,
        as it uses a different ID format than www.sankakucomplex.com (hash-like IDs).

        Known issue: gallery-dl may fail with "'invalid id'" errors for chan.sankakucomplex.com
        numeric post IDs due to API query format limitations. This is a gallery-dl issue, not CCC.
        Ensure gallery-dl is updated to v1.29.0+ for best compatibility.
        """
        if not url or not url.strip():
            return url
        parsed = urlparse(url.strip())
        netloc_lower = parsed.netloc.lower()
        # Don't normalize chan.sankakucomplex.com - it uses different post ID format
        # gallery-dl handles it directly, though numeric IDs may have API compatibility issues
        if netloc_lower == "chan.sankakucomplex.com":
            return url
        if netloc_lower in _SANKAKU_DOMAINS and netloc_lower != "www.sankakucomplex.com":
            return parsed._replace(netloc="www.sankakucomplex.com").geturl()
        return url

    def normalize_url_for_comparison(self, url: str) -> Optional[str]:
        """
        Collapse all Sankaku variants for dedup.

        ``sankaku.app/post/X``, ``sankakucomplex.com/post/X``, and
        ``www.sankakucomplex.com/post/X`` all compare as equal.
        ``chan.sankakucomplex.com/post/X`` is kept separate (different ID format).
        CDN URLs (v.sankakucomplex.com) are left to the default fallback.
        """
        parsed = urlparse(url.strip())
        netloc = parsed.netloc.lower()
        if netloc in _SANKAKU_DOMAINS:
            return f"sankakucomplex.com{parsed.path.rstrip('/')}"
        # chan.sankakucomplex.com uses different ID format, normalize separately
        if netloc == "chan.sankakucomplex.com":
            return f"chan.sankakucomplex.com{parsed.path.rstrip('/')}"
        return None

    # -- Browse support --

    @property
    def supports_browse(self) -> bool:
        return True

    @staticmethod
    def _build_sort_tag(sort: str) -> str:
        mapping = {"score": "order:popularity", "random": "order:random"}
        return mapping.get(sort, "")

    def build_search_url(self, tags: str, rating: str = "all", page: int = 1, sort: str = "newest") -> Optional[str]:
        parts = tags.strip().split() if tags.strip() else []
        rating_tag = self._build_rating_tag(rating)
        if rating_tag:
            parts.append(rating_tag)
        sort_tag = self._build_sort_tag(sort)
        if sort_tag:
            parts.append(sort_tag)
        query = "+".join(parts) if parts else ""
        base = f"https://chan.sankakucomplex.com/?tags={query}"
        if page > 1:
            base += f"&page={page}"
        return base

    def parse_browse_item(self, metadata: dict) -> Optional[dict]:
        post_id = metadata.get("id")
        if not post_id:
            return None

        file_url = metadata.get("file_url") or ""
        preview_url = metadata.get("sample_url") or file_url
        thumbnail_url = metadata.get("preview_url") or preview_url

        # Sankaku tags can be a space-separated string or a list of dicts
        raw_tags = metadata.get("tags", "")
        if isinstance(raw_tags, str):
            tags = raw_tags.split()
        elif isinstance(raw_tags, list):
            tags = [t.get("name", str(t)) if isinstance(t, dict) else str(t) for t in raw_tags]
        else:
            tags = []

        return {
            "external_id": str(post_id),
            "post_url": f"https://chan.sankakucomplex.com/post/show/{post_id}",
            "thumbnail_url": thumbnail_url,
            "preview_url": preview_url,
            "file_url": file_url,
            "tags": tags,
            "rating": self._normalize_rating(metadata.get("rating", "")),
            "width": metadata.get("width"),
            "height": metadata.get("height"),
            "source": metadata.get("source"),
        }
