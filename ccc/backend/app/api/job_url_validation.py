"""
Job URL validation: reject feed/home and bare-domain URLs that cannot be processed.
"""

import re
from urllib.parse import urlparse

from app.sites import get_handler


def is_rejected_job_url(url: str) -> bool:
    """
    Return True if the URL must not be accepted as a job URL.

    Rejects:
    - Twitter/X feed URLs (x.com/home, twitter.com/home) which are not a specific post.
    - Reddit base or subreddit-only URLs (e.g. reddit.com, reddit.com/r/DIY); only post URLs with /comments/ are allowed.
    - Bare domain URLs for known sites (e.g. gelbooru.com, misskey.art) with no path or only "/".
    """
    if not url or not url.strip():
        return True
    url = url.strip()
    try:
        parsed = urlparse(url)
    except Exception:
        return True
    scheme = (parsed.scheme or "").lower()
    netloc = (parsed.netloc or "").lower().strip()
    if scheme not in ("http", "https") or not netloc:
        return True
    path = (parsed.path or "").strip().rstrip("/") or "/"
    path_lower = path.lower()

    # Block Twitter/X home/feed URLs (not a specific post)
    if netloc in ("x.com", "www.x.com", "twitter.com", "www.twitter.com"):
        if path_lower == "/home" or path_lower.startswith("/home?"):
            return True

    # Block Reddit base or subreddit-only; require a post (path must contain /comments/)
    if "reddit.com" in netloc:
        if path == "/" or path == "":
            return True
        if re.match(r"^/r/[^/]+/?$", path, re.IGNORECASE):
            return True
        if "/comments/" not in path_lower:
            return True

    # For any known site handler, reject bare domain (no meaningful path)
    handler = get_handler(url)
    if not handler:
        return False
    if path == "/" or path == "":
        return True
    return False
