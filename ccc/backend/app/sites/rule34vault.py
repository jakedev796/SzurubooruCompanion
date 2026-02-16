"""Rule34Vault (rule34vault.com) handler."""

from app.sites.base import SiteHandler


class Rule34VaultHandler(SiteHandler):
    name = "rule34vault"
    gallery_dl_extractor = "rule34vault"

    def matches_url(self, url: str) -> bool:
        return "rule34vault.com" in url.lower()
