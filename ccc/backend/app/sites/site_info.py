"""
Curated supported sites shown in Settings > Supported Sites.

Only sites listed here appear in the Supported Sites table. Add entries as sites
are manually tested; the backend still has many more handlers for URL matching
and downloads, but this page is exclusive to tested sites.

Keys: url, notes, config ("required"|"optional"|"none"),
      tag_extraction_supported ("yes"|"no"|"na"), download_supported ("yes"|"no"|"na").
When tag_extraction_supported or download_supported are omitted, the API falls back
to handler/extractor logic and DOWNLOAD_NA/TAG_EXTRACTION_NA for "na".
"""

from typing import Dict, Set

# site_name -> { url, notes, config, tag_extraction_supported?, download_supported? }
SITE_DISPLAY_INFO: Dict[str, Dict[str, str]] = {
    "sankaku": {"url": "sankaku.app, sankakucomplex.com (chan, news)", "notes": "Login required", "config": "required", "tag_extraction_supported": "yes", "download_supported": "yes"},
    "twitter": {"url": "twitter.com, x.com", "notes": "Cookies required", "config": "required", "tag_extraction_supported": "na", "download_supported": "yes"},
    "misskey": {"url": "misskey.io, misskey.art, etc.", "notes": "Optional; required for private posts", "config": "optional", "tag_extraction_supported": "na", "download_supported": "yes"},
    "rule34": {"url": "rule34.xxx", "notes": "Optional API key for rate limits", "config": "optional", "tag_extraction_supported": "yes", "download_supported": "yes"},
    "rule34vault": {"url": "rule34vault.com", "notes": "Some posts may fail (gallery-dl KeyError 32), using generic extractor", "config": "none", "tag_extraction_supported": "yes", "download_supported": "yes"},
    "danbooru": {"url": "danbooru.donmai.us", "notes": "Optional API key for rate limits", "config": "optional", "tag_extraction_supported": "yes", "download_supported": "yes"},
    "gelbooru": {"url": "gelbooru.com", "notes": "API key and user ID required", "config": "required", "tag_extraction_supported": "yes", "download_supported": "yes"},
    "yandere": {"url": "yande.re", "notes": "", "config": "none", "tag_extraction_supported": "yes", "download_supported": "yes"},
    "reddit": {"url": "reddit.com", "notes": "Optional; expect very hit-or-miss behavior because reddit sucks", "config": "optional", "tag_extraction_supported": "na", "download_supported": "yes"},
    "e621": {"url": "e621.net", "notes": "Optional API key for rate limits", "config": "optional", "tag_extraction_supported": "yes", "download_supported": "yes"},
}

# Fallback when a site is not in SITE_DISPLAY_INFO or key is missing (e.g. redirect services)
DOWNLOAD_NA: Set[str] = {"bitly", "tco"}
TAG_EXTRACTION_NA: Set[str] = {"bitly", "tco"}
