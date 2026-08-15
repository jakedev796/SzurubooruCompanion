"""
Job URL validation: reject feed/home and bare-domain URLs that cannot be processed,
and URLs whose host resolves to an address the backend must not fetch.

Every rejection carries a machine-readable code so clients can react to the reason
(e.g. fall back to a byte upload only when the address itself was blocked).
"""

import re
from dataclasses import dataclass
from typing import Optional
from urllib.parse import urlparse

from app.sites import get_handler
from app.utils.network import (
    ERROR_BLOCKED_ADDRESS,
    ERROR_DNS_RESOLUTION_FAILED,
    check_host,
)

ERROR_UNSUPPORTED_SCHEME = "unsupported_scheme"
ERROR_UNSUPPORTED_URL = "unsupported_url"

_UNSUPPORTED_URL_MESSAGE = (
    "URL is not allowed: use a direct link to a post or media, not a feed or site homepage."
)


@dataclass(frozen=True)
class JobUrlRejection:
    """Why a job URL was refused, in both human and machine readable form."""

    error_code: str
    message: str


def check_job_url_shape(url: str) -> Optional[JobUrlRejection]:
    """
    Reject URLs that cannot be processed regardless of where they point.

    Rejects:
    - Non-http(s) or unparseable URLs.
    - Twitter/X feed URLs (x.com/home, twitter.com/home) which are not a specific post.
    - Reddit base or subreddit-only URLs (e.g. reddit.com, reddit.com/r/DIY); only post URLs with /comments/ are allowed.
    - Bare domain URLs for known sites (e.g. gelbooru.com, misskey.art) with no path or only "/".
    """
    if not url or not url.strip():
        return JobUrlRejection(ERROR_UNSUPPORTED_SCHEME, "URL is empty.")
    url = url.strip()
    try:
        parsed = urlparse(url)
        netloc = (parsed.netloc or "").lower().strip()
    except ValueError:
        return JobUrlRejection(ERROR_UNSUPPORTED_SCHEME, "URL could not be parsed.")
    scheme = (parsed.scheme or "").lower()
    if scheme not in ("http", "https") or not netloc:
        return JobUrlRejection(
            ERROR_UNSUPPORTED_SCHEME, "URL is not allowed: only http and https URLs can be processed."
        )
    path = (parsed.path or "").strip().rstrip("/") or "/"
    path_lower = path.lower()

    # Block Twitter/X home/feed URLs (not a specific post)
    if netloc in ("x.com", "www.x.com", "twitter.com", "www.twitter.com"):
        if path_lower == "/home" or path_lower.startswith("/home?"):
            return JobUrlRejection(ERROR_UNSUPPORTED_URL, _UNSUPPORTED_URL_MESSAGE)

    # Block Reddit base or subreddit-only; require a post (path must contain /comments/)
    if "reddit.com" in netloc:
        if path == "/" or path == "":
            return JobUrlRejection(ERROR_UNSUPPORTED_URL, _UNSUPPORTED_URL_MESSAGE)
        if re.match(r"^/r/[^/]+/?$", path, re.IGNORECASE):
            return JobUrlRejection(ERROR_UNSUPPORTED_URL, _UNSUPPORTED_URL_MESSAGE)
        if "/comments/" not in path_lower:
            return JobUrlRejection(ERROR_UNSUPPORTED_URL, _UNSUPPORTED_URL_MESSAGE)

    # For any known site handler, reject bare domain (no meaningful path)
    handler = get_handler(url)
    if not handler:
        return None
    if path == "/" or path == "":
        return JobUrlRejection(ERROR_UNSUPPORTED_URL, _UNSUPPORTED_URL_MESSAGE)
    return None


async def check_job_url(url: str) -> Optional[JobUrlRejection]:
    """
    Full job URL check: shape first, then the addresses the host resolves to.

    The host is taken from urlparse and classified by resolved address only; site
    handlers match domains by substring and must never inform this decision.
    """
    shape_rejection = check_job_url_shape(url)
    if shape_rejection is not None:
        return shape_rejection

    parsed = urlparse(url.strip())
    try:
        host = parsed.hostname or ""
        port = parsed.port or 0
    except ValueError:
        return JobUrlRejection(ERROR_UNSUPPORTED_SCHEME, "URL could not be parsed.")

    result = await check_host(host, port)
    if result.allowed:
        return None
    return JobUrlRejection(
        result.error_code or ERROR_BLOCKED_ADDRESS,
        result.message or "URL host could not be verified.",
    )


def is_rejected_job_url(url: str) -> bool:
    """
    Boolean form of the shape check only, mirrored by the browser extension's
    utils/job_url_validation.ts. Address checks live in check_job_url.
    """
    return check_job_url_shape(url) is not None


__all__ = [
    "ERROR_BLOCKED_ADDRESS",
    "ERROR_DNS_RESOLUTION_FAILED",
    "ERROR_UNSUPPORTED_SCHEME",
    "ERROR_UNSUPPORTED_URL",
    "JobUrlRejection",
    "check_job_url",
    "check_job_url_shape",
    "is_rejected_job_url",
]
