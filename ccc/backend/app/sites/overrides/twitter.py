"""Twitter override: normalize_url_for_comparison."""

import re
from typing import Optional
from urllib.parse import urlparse


class TwitterOverride:
    """Mixin for Twitter-specific logic."""

    def normalize_url_for_comparison(self, url: str) -> Optional[str]:
        parsed = urlparse(url)
        netloc = parsed.netloc.lower()
        path = parsed.path.rstrip("/")

        if netloc in ("x.com", "twitter.com"):
            m = re.search(r"/status/(\d+)", path, re.IGNORECASE)
            if m:
                return f"x.com/status/{m.group(1)}"

        if netloc in ("pbs.twimg.com", "video.twimg.com"):
            m = re.match(r"/media/([A-Za-z0-9_-]+)", path, re.IGNORECASE)
            if m:
                return f"twimg.com/media/{m.group(1)}"

        return None
