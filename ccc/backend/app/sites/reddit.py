"""Reddit (reddit.com) handler."""

from typing import List

from app.sites.base import CredentialSpec, SiteHandler


class RedditHandler(SiteHandler):
    name = "reddit"
    gallery_dl_extractor = "reddit"
    credentials = [
        CredentialSpec("client-id", "gallery_dl_reddit_client_id"),
        CredentialSpec("client-secret", "gallery_dl_reddit_client_secret"),
    ]

    def matches_url(self, url: str) -> bool:
        return "reddit.com" in url.lower()

    def gallery_dl_options(self) -> List[str]:
        """Override to inject computed user-agent."""
        opts = super().gallery_dl_options()
        username = (self.settings.gallery_dl_reddit_username or "").strip()
        if username:
            ua = f"Python:ExtendedUploader:v1.0 (by /u/{username})"
            opts.extend(["-o", f"extractor.{self.gallery_dl_extractor}.user-agent={ua}"])
        return opts
