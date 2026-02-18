"""Gelbooru (gelbooru.com) handler."""

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
