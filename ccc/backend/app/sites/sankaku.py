"""Sankaku (sankaku.app / sankakucomplex.com) handler."""

import re
from typing import Optional
from urllib.parse import urlparse

from app.sites.base import CredentialSpec, SiteHandler

# Domains that should all normalise to www.sankakucomplex.com
_SANKAKU_DOMAINS = {"sankakucomplex.com", "www.sankakucomplex.com", "chan.sankakucomplex.com", "sankaku.app", "www.sankaku.app"}


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
        """Rewrite all Sankaku domains to www.sankakucomplex.com (required by gallery-dl)."""
        if not url or not url.strip():
            return url
        parsed = urlparse(url.strip())
        if parsed.netloc.lower() in _SANKAKU_DOMAINS and parsed.netloc.lower() != "www.sankakucomplex.com":
            return parsed._replace(netloc="www.sankakucomplex.com").geturl()
        return url

    def normalize_url_for_comparison(self, url: str) -> Optional[str]:
        """
        Collapse all Sankaku variants for dedup.

        ``sankaku.app/post/X``, ``sankakucomplex.com/post/X``, and
        ``www.sankakucomplex.com/post/X`` all compare as equal.
        CDN URLs (v.sankakucomplex.com) are left to the default fallback.
        """
        parsed = urlparse(url.strip())
        netloc = parsed.netloc.lower()
        if netloc in _SANKAKU_DOMAINS:
            return f"sankakucomplex.com{parsed.path.rstrip('/')}"
        return None
