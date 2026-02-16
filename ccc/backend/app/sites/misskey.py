"""Misskey instance handler."""

from app.sites.base import CredentialSpec, SiteHandler

MISSKEY_DOMAINS = [
    "misskey.io", "misskey.art", "misskey.net", "misskey.love", "misskey.jp",
    "misskey.design", "misskey.xyz", "mi.0px.io", "misskey.pizza",
]


class MisskeyHandler(SiteHandler):
    name = "misskey"
    gallery_dl_extractor = "misskey"
    credentials = [
        CredentialSpec("username", "gallery_dl_misskey_username"),
        CredentialSpec("password", "gallery_dl_misskey_password"),
    ]

    def matches_url(self, url: str) -> bool:
        lower = url.lower()
        return any(domain in lower for domain in MISSKEY_DOMAINS)

    @property
    def uses_resolve_urls(self) -> bool:
        return True

    @property
    def uses_direct_download(self) -> bool:
        return True
