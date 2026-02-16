"""Yandere (yande.re) handler."""

from app.sites.base import SiteHandler


class YandereHandler(SiteHandler):
    name = "yandere"
    gallery_dl_extractor = "yandere"
    gallery_dl_tag_options = [("tags", "true")]
    credentials = []

    def matches_url(self, url: str) -> bool:
        return "yande.re" in url.lower()
