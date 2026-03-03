"""Site overrides for custom logic. Lazy-loaded by override_key."""

from typing import Any, Callable, Dict, Optional, Type

_OVERRIDE_MODULES: Dict[str, Type[Any]] = {}


def get_override(key: Optional[str]) -> Optional[Type[Any]]:
    """Return override class for key, or None."""
    if not key:
        return None
    if key not in _OVERRIDE_MODULES:
        mod = _load_override(key)
        _OVERRIDE_MODULES[key] = mod
    return _OVERRIDE_MODULES.get(key)


def _load_override(key: str) -> Optional[Type[Any]]:
    """Load override module by key."""
    try:
        if key == "sankaku":
            from app.sites.overrides.sankaku import SankakuOverride
            return SankakuOverride
        if key == "twitter":
            from app.sites.overrides.twitter import TwitterOverride
            return TwitterOverride
        if key == "misskey":
            from app.sites.overrides.misskey import MisskeyOverride
            return MisskeyOverride
        if key == "reddit":
            from app.sites.overrides.reddit import RedditOverride
            return RedditOverride
        if key == "rule34":
            from app.sites.overrides.booru import Rule34BrowseOverride
            return Rule34BrowseOverride
        if key == "danbooru":
            from app.sites.overrides.booru import DanbooruBrowseOverride
            return DanbooruBrowseOverride
        if key == "gelbooru":
            from app.sites.overrides.booru import GelbooruBrowseOverride
            return GelbooruBrowseOverride
        if key == "yandere":
            from app.sites.overrides.booru import YandereBrowseOverride
            return YandereBrowseOverride
    except ImportError as e:
        import logging
        logging.getLogger(__name__).warning("Failed to load override %s: %s", key, e)
    return None
