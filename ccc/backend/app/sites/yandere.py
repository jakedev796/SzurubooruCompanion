"""Yandere (yande.re) handler."""

from typing import Optional

from app.sites.base import SiteHandler


class YandereHandler(SiteHandler):
    name = "yandere"
    gallery_dl_extractor = "yandere"
    gallery_dl_tag_options = [("tags", "true")]
    credentials = []

    def matches_url(self, url: str) -> bool:
        return "yande.re" in url.lower()

    # -- Browse support --

    @property
    def supports_browse(self) -> bool:
        return True

    @staticmethod
    def _build_sort_tag(sort: str) -> str:
        # Moebooru's order:random returns empty/unreliable results with tag filters
        mapping = {"score": "order:score"}
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
        base = f"https://yande.re/post?tags={query}"
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

        tag_string = metadata.get("tags", "")
        tags = tag_string.split() if isinstance(tag_string, str) else []

        return {
            "external_id": str(post_id),
            "post_url": f"https://yande.re/post/show/{post_id}",
            "thumbnail_url": thumbnail_url,
            "preview_url": preview_url,
            "file_url": file_url,
            "tags": tags,
            "rating": self._normalize_rating(metadata.get("rating", "")),
            "width": metadata.get("width"),
            "height": metadata.get("height"),
            "source": metadata.get("source"),
        }
