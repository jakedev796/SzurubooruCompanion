"""Danbooru (danbooru.donmai.us / safebooru.org) handler."""

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
