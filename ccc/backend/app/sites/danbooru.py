"""Danbooru (danbooru.donmai.us / safebooru.org) handler."""

from typing import Optional

from app.sites.base import CredentialSpec, SiteHandler


class DanbooruHandler(SiteHandler):
    name = "danbooru"
    gallery_dl_extractor = "danbooru"
    credentials = [
        CredentialSpec("api-key"),
        CredentialSpec("user-id"),
    ]

    def matches_url(self, url: str) -> bool:
        lower = url.lower()
        return "danbooru.donmai.us" in lower or "safebooru.org" in lower

    # -- Browse support --

    @property
    def supports_browse(self) -> bool:
        return True

    def build_search_url(self, tags: str, rating: str = "all", page: int = 1, sort: str = "newest") -> Optional[str]:
        parts = tags.strip().split() if tags.strip() else []
        rating_tag = self._build_rating_tag(rating)
        if rating_tag:
            parts.append(rating_tag)
        sort_tag = self._build_sort_tag(sort)
        if sort_tag:
            parts.append(sort_tag)
        query = "+".join(parts) if parts else ""
        base = f"https://danbooru.donmai.us/posts?tags={query}"
        if page > 1:
            base += f"&page={page}"
        return base

    def parse_browse_item(self, metadata: dict) -> Optional[dict]:
        post_id = metadata.get("id")
        if not post_id:
            return None

        file_url = metadata.get("file_url") or metadata.get("large_file_url") or ""
        preview_url = metadata.get("large_file_url") or metadata.get("file_url") or ""
        thumbnail_url = metadata.get("preview_file_url") or preview_url

        tag_string = metadata.get("tag_string", "")
        tags = tag_string.split() if isinstance(tag_string, str) else []

        return {
            "external_id": str(post_id),
            "post_url": f"https://danbooru.donmai.us/posts/{post_id}",
            "thumbnail_url": thumbnail_url,
            "preview_url": preview_url,
            "file_url": file_url,
            "tags": tags,
            "rating": self._normalize_rating(metadata.get("rating", "")),
            "width": metadata.get("image_width"),
            "height": metadata.get("image_height"),
            "source": metadata.get("source"),
        }
