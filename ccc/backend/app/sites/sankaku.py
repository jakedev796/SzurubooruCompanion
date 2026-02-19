"""Sankaku (sankaku.app / sankakucomplex.com) handler."""

import re
from typing import Optional
from urllib.parse import urlparse

from app.sites.base import CredentialSpec, SiteHandler

# Domains that should all normalise to www.sankakucomplex.com
# Note: chan.sankakucomplex.com uses different post ID format (numeric) and should NOT be normalized
_SANKAKU_DOMAINS = {"sankakucomplex.com", "www.sankakucomplex.com", "sankaku.app", "www.sankaku.app"}


class SankakuHandler(SiteHandler):
    name = "sankaku"
    gallery_dl_extractor = "sankaku"
    gallery_dl_tag_options = [("tags", "standard")]
    credentials = [
        CredentialSpec("username"),
        CredentialSpec("password"),
    ]

    def matches_url(self, url: str) -> bool:
        lower = url.lower()
        return "sankaku.app" in lower or "sankakucomplex.com" in lower

    def normalize_url(self, url: str) -> str:
        """
        Rewrite Sankaku domains to www.sankakucomplex.com (required by gallery-dl).
        
        Note: chan.sankakucomplex.com uses numeric post IDs and should NOT be normalized,
        as it uses a different ID format than www.sankakucomplex.com (hash-like IDs).
        
        Known issue: gallery-dl may fail with "'invalid id'" errors for chan.sankakucomplex.com
        numeric post IDs due to API query format limitations. This is a gallery-dl issue, not CCC.
        Ensure gallery-dl is updated to v1.29.0+ for best compatibility.
        """
        if not url or not url.strip():
            return url
        parsed = urlparse(url.strip())
        netloc_lower = parsed.netloc.lower()
        # Don't normalize chan.sankakucomplex.com - it uses different post ID format
        # gallery-dl handles it directly, though numeric IDs may have API compatibility issues
        if netloc_lower == "chan.sankakucomplex.com":
            return url
        if netloc_lower in _SANKAKU_DOMAINS and netloc_lower != "www.sankakucomplex.com":
            return parsed._replace(netloc="www.sankakucomplex.com").geturl()
        return url

    def normalize_url_for_comparison(self, url: str) -> Optional[str]:
        """
        Collapse all Sankaku variants for dedup.

        ``sankaku.app/post/X``, ``sankakucomplex.com/post/X``, and
        ``www.sankakucomplex.com/post/X`` all compare as equal.
        ``chan.sankakucomplex.com/post/X`` is kept separate (different ID format).
        CDN URLs (v.sankakucomplex.com) are left to the default fallback.
        """
        parsed = urlparse(url.strip())
        netloc = parsed.netloc.lower()
        if netloc in _SANKAKU_DOMAINS:
            return f"sankakucomplex.com{parsed.path.rstrip('/')}"
        # chan.sankakucomplex.com uses different ID format, normalize separately
        if netloc == "chan.sankakucomplex.com":
            return f"chan.sankakucomplex.com{parsed.path.rstrip('/')}"
        return None
