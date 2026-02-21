"""
Base site handler. Subclass and override what differs per site.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from app.config import Settings

logger = logging.getLogger(__name__)


@dataclass
class CredentialSpec:
    """One credential option to inject into gallery-dl (from user config only)."""
    gallery_dl_key: str  # e.g. "username", "api-key"


class SiteHandler:
    """
    Base handler for a media source site.

    Subclass responsibilities:
      - Set `name` and `gallery_dl_extractor` class attributes.
      - Override `matches_url()` to claim URLs.
      - Override other methods only where the site differs from defaults.
    """

    name: str = "generic"
    gallery_dl_extractor: str = ""
    credentials: List[CredentialSpec] = []
    gallery_dl_tag_options: List[Tuple[str, str]] = []

    def __init__(self, settings: Settings, user_config: Optional[Dict[str, Dict[str, str]]] = None):
        """
        Initialize site handler.

        Args:
            settings: Global settings from ENV
            user_config: Per-user credentials from database
                        Format: {site_name: {credential_key: value}}
                        Example: {"twitter": {"cookies": "..."}, "sankaku": {"username": "user", "password": "pass"}}
        """
        self.settings = settings
        self.user_config = user_config or {}

    # -- URL matching --

    def matches_url(self, url: str) -> bool:
        return False

    # -- URL normalization --

    def normalize_url(self, url: str) -> str:
        """Normalize the URL before any processing. Default: no-op."""
        return url

    def normalize_url_for_comparison(self, url: str) -> Optional[str]:
        """
        Return a normalized form for duplicate detection, or None
        to fall through to the default strip-query-params logic.
        """
        return None

    # -- Extraction mode --

    @property
    def uses_resolve_urls(self) -> bool:
        """True if this site needs --resolve-urls instead of --dump-json."""
        return False

    @property
    def uses_direct_download(self) -> bool:
        """True if individual files should be downloaded via HTTP (not gallery-dl)."""
        return False

    # -- gallery-dl CLI options --

    def gallery_dl_options(self) -> List[str]:
        """
        Extra -o flags for gallery-dl.
        Built from `credentials` and `gallery_dl_tag_options`; credentials from user config (dashboard) only.
        """
        opts: List[str] = []
        ext = self.gallery_dl_extractor
        if not ext:
            return opts

        for opt_key, opt_value in self.gallery_dl_tag_options:
            opts.extend(["-o", f"extractor.{ext}.{opt_key}={opt_value}"])

        for spec in self.credentials:
            site_creds = self.user_config.get(self.name, {})
            value = site_creds.get(spec.gallery_dl_key)
            if value and (cleaned := (value or "").strip()):
                opts.extend(["-o", f"extractor.{ext}.{spec.gallery_dl_key}={cleaned}"])

        return opts

    def gallery_dl_cleanup_paths(self) -> List[Path]:
        """Temp files to clean up after gallery-dl. Default: none."""
        return []

    # -- Browse / swiper support --

    @property
    def supports_browse(self) -> bool:
        """Whether this site supports browsing/searching via tag queries."""
        return False

    def build_search_url(self, tags: str, rating: str = "all", page: int = 1, sort: str = "newest") -> Optional[str]:
        """
        Build a search URL for browsing. Override per-site.

        Args:
            tags: Space-separated tag query (e.g. "cat girl")
            rating: "safe", "sketchy", "unsafe", or "all"
            page: 1-indexed page number
            sort: "newest", "score", or "random"
        """
        return None

    def parse_browse_item(self, metadata: dict) -> Optional[dict]:
        """
        Parse gallery-dl JSON metadata into a standardized browse item.

        Returns dict with keys:
            external_id, post_url, thumbnail_url, preview_url, file_url,
            tags, rating, width, height, source
        Or None if the item cannot be parsed.
        """
        return None

    @staticmethod
    def _normalize_rating(raw: str) -> str:
        """Map site-specific ratings to szurubooru terms."""
        r = str(raw).lower().strip()
        if r in ("s", "safe", "general", "g"):
            return "safe"
        if r in ("q", "questionable", "sensitive"):
            return "sketchy"
        if r in ("e", "explicit"):
            return "unsafe"
        return "unsafe"

    @staticmethod
    def _build_rating_tag(rating: str) -> str:
        """Convert our rating filter to a booru search tag."""
        mapping = {"safe": "rating:safe", "sketchy": "rating:questionable", "unsafe": "rating:explicit"}
        return mapping.get(rating, "")

    @staticmethod
    def _build_sort_tag(sort: str) -> str:
        """Convert our sort option to a booru search metatag. Default: order: prefix (Danbooru/Yandere)."""
        mapping = {"score": "order:score", "random": "order:random"}
        return mapping.get(sort, "")
