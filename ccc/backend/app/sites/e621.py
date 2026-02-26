"""e621.net handler."""

from app.sites.base import SiteHandler


class E621Handler(SiteHandler):
    name = "e621"
    gallery_dl_extractor = "e621"
    credentials = []

    def matches_url(self, url: str) -> bool:
        return "e621.net" in url.lower()
