"""Site handler registry. Maps URLs to handlers."""

from __future__ import annotations

import logging
from typing import List, Optional

from app.config import Settings, get_settings
from app.sites.base import SiteHandler

logger = logging.getLogger(__name__)

_handlers: List[SiteHandler] = []
_initialized = False


def _init_handlers(settings: Settings) -> None:
    """Import and instantiate all site handlers. Called once."""
    global _handlers, _initialized
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

    _handlers = [
        SankakuHandler(settings),
        TwitterHandler(settings),
        MisskeyHandler(settings),
        Rule34Handler(settings),
        Rule34VaultHandler(settings),
        DanbooruHandler(settings),
        GelbooruHandler(settings),
        YandereHandler(settings),
        RedditHandler(settings),
    ]
    _initialized = True
    logger.info("Registered %d site handlers", len(_handlers))


def get_handler(url: str) -> Optional[SiteHandler]:
    """Return the first handler that matches the URL, or None for generic/yt-dlp fallback."""
    settings = get_settings()
    _init_handlers(settings)

    for handler in _handlers:
        if handler.matches_url(url):
            return handler
    return None


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
