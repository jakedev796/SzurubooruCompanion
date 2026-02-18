"""Rule34 (rule34.xxx) handler."""

from app.sites.base import CredentialSpec, SiteHandler


class Rule34Handler(SiteHandler):
    name = "rule34"
    gallery_dl_extractor = "rule34"
    credentials = [
        CredentialSpec("api-key"),
        CredentialSpec("user-id"),
    ]

    def matches_url(self, url: str) -> bool:
        return "rule34.xxx" in url.lower()
