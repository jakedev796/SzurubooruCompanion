"""Sankaku override: normalize_url, normalize_url_for_comparison, build_search_url, parse_browse_item."""

from typing import Optional
from urllib.parse import urlparse

_SANKAKU_DOMAINS = {"sankakucomplex.com", "www.sankakucomplex.com", "sankaku.app", "www.sankaku.app"}


class SankakuOverride:
    """Mixin for Sankaku-specific logic."""

    def normalize_url(self, url: str) -> str:
        if not url or not url.strip():
            return url
        parsed = urlparse(url.strip())
        netloc_lower = parsed.netloc.lower()
        if netloc_lower == "chan.sankakucomplex.com":
            return url
        if netloc_lower in _SANKAKU_DOMAINS and netloc_lower != "www.sankakucomplex.com":
            return parsed._replace(netloc="www.sankakucomplex.com").geturl()
        return url

    def normalize_url_for_comparison(self, url: str) -> Optional[str]:
        parsed = urlparse(url.strip())
        netloc = parsed.netloc.lower()
        if netloc in _SANKAKU_DOMAINS:
            return f"sankakucomplex.com{parsed.path.rstrip('/')}"
        if netloc == "chan.sankakucomplex.com":
            return f"chan.sankakucomplex.com{parsed.path.rstrip('/')}"
        return None

    # -- Browse support --

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
