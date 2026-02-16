"""Danbooru (danbooru.donmai.us / safebooru.org) handler."""

from app.sites.base import CredentialSpec, SiteHandler


class DanbooruHandler(SiteHandler):
    name = "danbooru"
    gallery_dl_extractor = "danbooru"
    credentials = [
        CredentialSpec("api-key", "gallery_dl_danbooru_api_key"),
        CredentialSpec("user-id", "gallery_dl_danbooru_user_id"),
    ]

    def matches_url(self, url: str) -> bool:
        lower = url.lower()
        return "danbooru.donmai.us" in lower or "safebooru.org" in lower
