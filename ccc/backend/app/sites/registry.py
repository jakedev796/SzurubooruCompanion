"""Site handler registry. Builds handlers from site_registry + overrides."""

from __future__ import annotations

import logging
from typing import Dict, List, Optional, Type

from app.config import Settings, get_settings
from app.sites.base import CredentialSpec, SiteHandler
from app.sites.site_registry import get_auth_site_defs, get_no_auth_site_defs
from app.sites.overrides import get_override

logger = logging.getLogger(__name__)

_HANDLER_CLASSES: List[Type[SiteHandler]] = []
_initialized = False


def _make_handler_class(defn: dict) -> Type[SiteHandler]:
    """Build a SiteHandler class from a registry definition."""
    sid = defn["id"]
    extractor = defn["extractor"]
    domains = defn["domains"]
    cred_names = defn["credentials"]
    tags_value = defn.get("tags_value")
    override_key = defn.get("override_key")
    uses_resolve_urls = defn.get("uses_resolve_urls", False)
    uses_direct_download = defn.get("uses_direct_download", False)
    retry_on_empty = defn.get("retry_on_empty", False)
    supports_browse = defn.get("supports_browse", False)

    credentials = [CredentialSpec(name) for name in cred_names]
    gallery_dl_tag_options = [("tags", tags_value)] if tags_value else []

    def _matches_url(self, url: str) -> bool:
        return any(d in url.lower() for d in domains)

    attrs = {
        "name": sid,
        "gallery_dl_extractor": extractor,
        "credentials": credentials,
        "gallery_dl_tag_options": gallery_dl_tag_options,
        "matches_url": _matches_url,
        "uses_resolve_urls": property(lambda self: uses_resolve_urls),
        "uses_direct_download": property(lambda self: uses_direct_download),
        "retry_on_empty": property(lambda self: retry_on_empty),
        "supports_browse": property(lambda self: supports_browse),
    }

    base_class: Type[SiteHandler] = type(
        f"RegistryHandler_{sid}",
        (SiteHandler,),
        attrs,
    )

    override_cls = get_override(override_key)
    if override_cls:
        final_class = type(
            f"Handler_{sid}",
            (override_cls, base_class),
            {},
        )
    else:
        final_class = base_class

    final_class.__name__ = f"Handler_{sid.replace('-', '_')}"
    return final_class


def _init_handler_classes() -> None:
    """Build handler classes from registry. Called once."""
    global _HANDLER_CLASSES, _initialized
    if _initialized:
        return

    auth_defs = get_auth_site_defs()
    no_auth_defs = get_no_auth_site_defs()

    _HANDLER_CLASSES = [
        _make_handler_class(d) for d in auth_defs + no_auth_defs
    ]
    _initialized = True
    logger.debug("Registered %d site handler classes", len(_HANDLER_CLASSES))


def get_handler(url: str, user_config: Optional[Dict[str, Dict[str, str]]] = None) -> Optional[SiteHandler]:
    """
    Return the first handler that matches the URL, or None for generic/yt-dlp fallback.

    Args:
        url: The URL to match
        user_config: Per-user credentials from database
                    Format: {site_name: {credential_key: value}}
    """
    settings = get_settings()
    _init_handler_classes()

    for handler_cls in _HANDLER_CLASSES:
        handler = handler_cls(settings, user_config)
        if handler.matches_url(url):
            return handler
    return None


def get_handler_by_name(name: str, user_config: Optional[Dict[str, Dict[str, str]]] = None) -> Optional[SiteHandler]:
    """Get a specific handler by its site name (e.g. 'danbooru', 'gelbooru')."""
    settings = get_settings()
    _init_handler_classes()

    for handler_cls in _HANDLER_CLASSES:
        handler = handler_cls(settings, user_config)
        if handler.name == name:
            return handler
    return None


def get_browsable_handlers(user_config: Optional[Dict[str, Dict[str, str]]] = None) -> List[SiteHandler]:
    """Return all handler instances that support browsing."""
    settings = get_settings()
    _init_handler_classes()

    handlers = []
    for handler_cls in _HANDLER_CLASSES:
        handler = handler_cls(settings, user_config)
        if handler.supports_browse:
            handlers.append(handler)
    return handlers


def get_all_handlers(user_config: Optional[Dict[str, Dict[str, str]]] = None) -> List[SiteHandler]:
    """Return all handler instances."""
    settings = get_settings()
    _init_handler_classes()

    return [handler_cls(settings, user_config) for handler_cls in _HANDLER_CLASSES]


def normalize_url(url: str) -> str:
    """Run site-specific URL normalization. Falls through to identity if no handler matches."""
    handler = get_handler(url)
    if handler:
        return handler.normalize_url(url)
    return url


def normalize_url_for_comparison(url: str) -> Optional[str]:
    """Delegate to site handler for comparison normalization. Returns None if no site-specific logic."""
    handler = get_handler(url)
    if handler:
        return handler.normalize_url_for_comparison(url)
    return None
