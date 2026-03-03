"""Misskey override: gallery_dl_options (root from URL), matches_url (subdomain support)."""

from typing import List, Optional
from urllib.parse import urlparse

MISSKEY_DOMAINS = [
    "misskey.io", "misskey.art", "misskey.net", "misskey.love", "misskey.jp",
    "misskey.design", "misskey.xyz", "mi.0px.io", "misskey.pizza",
]


class MisskeyOverride:
    """Mixin for Misskey-specific logic."""

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

    def gallery_dl_options(self, url: Optional[str] = None) -> List[str]:
        opts = super().gallery_dl_options(url)
        if url:
            try:
                parsed = urlparse(url)
                if parsed.scheme and parsed.netloc:
                    root = f"{parsed.scheme}://{parsed.netloc}"
                    opts.extend(["-o", f"extractor.{self.gallery_dl_extractor}.root={root}"])
            except Exception:
                pass
        return opts
