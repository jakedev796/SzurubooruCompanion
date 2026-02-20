"""Site handler registry. Maps URLs to handlers."""

from __future__ import annotations

import logging
from typing import Dict, List, Optional, Type

from app.config import Settings, get_settings
from app.sites.base import SiteHandler

logger = logging.getLogger(__name__)

# List of handler classes (not instances)
_HANDLER_CLASSES: List[Type[SiteHandler]] = []
_initialized = False


def _init_handler_classes() -> None:
    """Import all site handler classes. Called once."""
    global _HANDLER_CLASSES, _initialized
    if _initialized:
        return

    from app.sites.sankaku import SankakuHandler
    from app.sites.twitter import TwitterHandler
    from app.sites.misskey import MisskeyHandler
    from app.sites.rule34 import Rule34Handler
    from app.sites.danbooru import DanbooruHandler
    from app.sites.gelbooru import GelbooruHandler
    from app.sites.yandere import YandereHandler
    from app.sites.reddit import RedditHandler
    from app.sites.rule34vault import Rule34VaultHandler

    _HANDLER_CLASSES = [
        SankakuHandler,
        TwitterHandler,
        MisskeyHandler,
        Rule34Handler,
        Rule34VaultHandler,
        DanbooruHandler,
        GelbooruHandler,
        YandereHandler,
        RedditHandler,
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
        # Create instance with settings and user_config
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
