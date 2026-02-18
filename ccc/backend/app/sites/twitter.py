"""Twitter/X (twitter.com / x.com) handler."""

from __future__ import annotations

import logging
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Optional
from urllib.parse import urlparse

from app.config import Settings
from app.sites.base import CredentialSpec, SiteHandler

logger = logging.getLogger(__name__)


class TwitterHandler(SiteHandler):
    name = "twitter"
    gallery_dl_extractor = "twitter"
    # Twitter only needs cookies (auth_token)
    credentials = []

    def __init__(self, settings: Settings, user_config: Optional[Dict[str, Dict[str, str]]] = None):
        super().__init__(settings, user_config)
        self._cookie_path: Optional[Path] = None

    def matches_url(self, url: str) -> bool:
        lower = url.lower()
        return "twitter.com" in lower or "x.com" in lower

    @property
    def uses_resolve_urls(self) -> bool:
        return True

    @property
    def uses_direct_download(self) -> bool:
        return True

    def normalize_url_for_comparison(self, url: str) -> Optional[str]:
        """Extract Twitter status ID or media ID for duplicate detection."""
        parsed = urlparse(url)
        netloc = parsed.netloc.lower()
        path = parsed.path.rstrip("/")

        # Twitter/X status URLs - extract the status ID
        if netloc in ("x.com", "twitter.com"):
            m = re.search(r"/status/(\d+)", path, re.IGNORECASE)
            if m:
                return f"x.com/status/{m.group(1)}"

        # Twitter media URLs - extract the media ID
        if netloc in ("pbs.twimg.com", "video.twimg.com"):
            m = re.match(r"/media/([A-Za-z0-9_-]+)", path, re.IGNORECASE)
            if m:
                return f"twimg.com/media/{m.group(1)}"

        return None

    def gallery_dl_options(self) -> List[str]:
        """Override to add cookie temp file handling (cookies from user config only)."""
        opts = super().gallery_dl_options()
        site_creds = self.user_config.get(self.name, {})
        cookies_content = (site_creds.get("cookies") or "").strip()
        if cookies_content:
            try:
                fd = tempfile.NamedTemporaryFile(
                    mode="w",
                    delete=False,
                    suffix=".txt",
                    prefix="ccc_twitter_cookies_",
                    encoding="utf-8",
                )
                fd.write(cookies_content)
                fd.close()
                self._cookie_path = Path(fd.name)
                opts.extend(["-o", f"extractor.twitter.cookies={fd.name}"])
            except Exception as e:
                logger.warning("Failed to write Twitter cookies temp file: %s", e)
                self._cookie_path = None

        return opts

    def gallery_dl_cleanup_paths(self) -> List[Path]:
        path = self._cookie_path
        self._cookie_path = None
        return [path] if path else []
