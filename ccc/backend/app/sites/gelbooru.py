"""Gelbooru (gelbooru.com) handler."""

from typing import Optional

from app.sites.base import CredentialSpec, SiteHandler


class GelbooruHandler(SiteHandler):
    name = "gelbooru"
    gallery_dl_extractor = "gelbooru"
    credentials = [
        CredentialSpec("api-key"),
        CredentialSpec("user-id"),
    ]

    def matches_url(self, url: str) -> bool:
        return "gelbooru.com" in url.lower()

    # -- Browse support --

    @property
    def supports_browse(self) -> bool:
        return True

    @staticmethod
    def _build_sort_tag(sort: str) -> str:
        mapping = {"score": "sort:score", "random": "sort:random"}
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
        pid = (page - 1)
        return f"https://gelbooru.com/index.php?page=post&s=list&tags={query}&pid={pid}"

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
            "post_url": f"https://gelbooru.com/index.php?page=post&s=view&id={post_id}",
            "thumbnail_url": thumbnail_url,
            "preview_url": preview_url,
            "file_url": file_url,
            "tags": tags,
            "rating": self._normalize_rating(metadata.get("rating", "")),
            "width": metadata.get("width"),
            "height": metadata.get("height"),
            "source": metadata.get("source"),
        }
