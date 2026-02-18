"""Reddit (reddit.com) handler."""

from typing import List

from app.sites.base import CredentialSpec, SiteHandler


class RedditHandler(SiteHandler):
    name = "reddit"
    gallery_dl_extractor = "reddit"
    credentials = [
        CredentialSpec("client-id"),
        CredentialSpec("client-secret"),
        CredentialSpec("username"),
    ]

    def matches_url(self, url: str) -> bool:
        return "reddit.com" in url.lower()

    def gallery_dl_options(self) -> List[str]:
        """Override to inject computed user-agent (username from user config only)."""
        opts = super().gallery_dl_options()
        site_creds = self.user_config.get(self.name, {})
        username = (site_creds.get("username") or "").strip()
        if username:
            ua = f"Python:ExtendedUploader:v1.0 (by /u/{username})"
            opts.extend(["-o", f"extractor.{self.gallery_dl_extractor}.user-agent={ua}"])
        return opts
