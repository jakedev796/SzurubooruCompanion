"""Gelbooru (gelbooru.com) handler."""

from app.sites.base import CredentialSpec, SiteHandler


class GelbooruHandler(SiteHandler):
    name = "gelbooru"
    gallery_dl_extractor = "gelbooru"
    credentials = [
        CredentialSpec("api-key", "gallery_dl_gelbooru_api_key"),
        CredentialSpec("user-id", "gallery_dl_gelbooru_user_id"),
    ]

    def matches_url(self, url: str) -> bool:
        return "gelbooru.com" in url.lower()
