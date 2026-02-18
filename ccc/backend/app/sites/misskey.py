"""Misskey instance handler."""

from urllib.parse import urlparse

from app.sites.base import CredentialSpec, SiteHandler

MISSKEY_DOMAINS = [
    "misskey.io", "misskey.art", "misskey.net", "misskey.love", "misskey.jp",
    "misskey.design", "misskey.xyz", "mi.0px.io", "misskey.pizza",
]


class MisskeyHandler(SiteHandler):
    name = "misskey"
    gallery_dl_extractor = "misskey"
    credentials = [
        CredentialSpec("access-token", "gallery_dl_misskey_access_token"),
        CredentialSpec("username", "gallery_dl_misskey_username"),
        CredentialSpec("password", "gallery_dl_misskey_password"),
    ]

    def matches_url(self, url: str) -> bool:
        try:
            host = (urlparse(url).netloc or "").lower().strip()
            if not host:
                return False
            return host in MISSKEY_DOMAINS or any(
                host.endswith("." + d) for d in MISSKEY_DOMAINS
            )
        except Exception:
            return False

    @property
    def uses_resolve_urls(self) -> bool:
        return True

    @property
    def uses_direct_download(self) -> bool:
        return True
