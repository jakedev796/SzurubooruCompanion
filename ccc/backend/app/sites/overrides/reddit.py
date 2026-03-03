"""Reddit override: gallery_dl_options (user-agent from username)."""

from typing import List, Optional


class RedditOverride:
    """Mixin for Reddit-specific logic."""

    def gallery_dl_options(self, url: Optional[str] = None) -> List[str]:
        opts = super().gallery_dl_options(url)
        site_creds = self.user_config.get(self.name, {})
        username = (site_creds.get("username") or "").strip()
        if username:
            ua = f"Python:ExtendedUploader:v1.0 (by /u/{username})"
            opts.extend(["-o", f"extractor.{self.gallery_dl_extractor}.user-agent={ua}"])
        return opts
