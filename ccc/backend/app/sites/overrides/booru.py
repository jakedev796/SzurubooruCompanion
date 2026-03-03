"""Booru browse overrides: build_search_url, parse_browse_item for Danbooru, Gelbooru, Rule34, Yandere."""

from typing import Optional


def _parse_browse_item(
    self,
    metadata: dict,
    post_url_tpl: str,
    tag_key: str,
    file_keys: tuple,
    preview_keys: tuple,
    thumb_keys: tuple,
) -> Optional[dict]:
    """Shared parse logic; keys vary per booru."""
    post_id = metadata.get("id")
    if not post_id:
        return None

    file_url = next((v for k in file_keys if (v := metadata.get(k))), "")
    preview_url = next((v for k in preview_keys if (v := metadata.get(k))), file_url)
    thumbnail_url = next((v for k in thumb_keys if (v := metadata.get(k))), preview_url)

    raw = metadata.get(tag_key, "")
    tags = raw.split() if isinstance(raw, str) else []

    return {
        "external_id": str(post_id),
        "post_url": post_url_tpl.format(id=post_id),
        "thumbnail_url": thumbnail_url,
        "preview_url": preview_url,
        "file_url": file_url,
        "tags": tags,
        "rating": self._normalize_rating(metadata.get("rating", "")),
        "width": metadata.get("width") or metadata.get("image_width"),
        "height": metadata.get("height") or metadata.get("image_height"),
        "source": metadata.get("source"),
    }


class DanbooruBrowseOverride:
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
        return _parse_browse_item(
            self, metadata,
            "https://danbooru.donmai.us/posts/{id}",
            "tag_string",
            ("file_url", "large_file_url"),
            ("large_file_url", "file_url"),
            ("preview_file_url",),
        )


class GelbooruBrowseOverride:
    @staticmethod
    def _build_sort_tag(sort: str) -> str:
        return {"score": "sort:score", "random": "sort:random"}.get(sort, "")

    def build_search_url(self, tags: str, rating: str = "all", page: int = 1, sort: str = "newest") -> Optional[str]:
        parts = tags.strip().split() if tags.strip() else []
        rating_tag = self._build_rating_tag(rating)
        if rating_tag:
            parts.append(rating_tag)
        sort_tag = self._build_sort_tag(sort)
        if sort_tag:
            parts.append(sort_tag)
        query = "+".join(parts) if parts else ""
        pid = page - 1
        return f"https://gelbooru.com/index.php?page=post&s=list&tags={query}&pid={pid}"

    def parse_browse_item(self, metadata: dict) -> Optional[dict]:
        return _parse_browse_item(
            self, metadata,
            "https://gelbooru.com/index.php?page=post&s=view&id={id}",
            "tags",
            ("file_url",),
            ("sample_url", "file_url"),
            ("preview_url",),
        )


class Rule34BrowseOverride:
    @staticmethod
    def _build_sort_tag(sort: str) -> str:
        return {"score": "sort:score", "random": "sort:random"}.get(sort, "")

    def build_search_url(self, tags: str, rating: str = "all", page: int = 1, sort: str = "newest") -> Optional[str]:
        parts = tags.strip().split() if tags.strip() else []
        rating_tag = self._build_rating_tag(rating)
        if rating_tag:
            parts.append(rating_tag)
        sort_tag = self._build_sort_tag(sort)
        if sort_tag:
            parts.append(sort_tag)
        query = "+".join(parts) if parts else ""
        pid = page - 1
        return f"https://rule34.xxx/index.php?page=post&s=list&tags={query}&pid={pid}"

    def parse_browse_item(self, metadata: dict) -> Optional[dict]:
        return _parse_browse_item(
            self, metadata,
            "https://rule34.xxx/index.php?page=post&s=view&id={id}",
            "tags",
            ("file_url",),
            ("sample_url", "file_url"),
            ("preview_url",),
        )


class YandereBrowseOverride:
    @staticmethod
    def _build_sort_tag(sort: str) -> str:
        return {"score": "order:score"}.get(sort, "")

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
        return _parse_browse_item(
            self, metadata,
            "https://yande.re/post/show/{id}",
            "tags",
            ("file_url",),
            ("sample_url", "file_url"),
            ("preview_url",),
        )
