"""
Unified site registry. All gallery-dl sites (auth + no-auth) defined in one place.
Sites needing custom logic use overrides in app.sites.overrides.
"""

from typing import Any, Dict, List, Optional, Tuple

from app.sites.no_auth_list import NO_AUTH_SITES

# Extractors that support categorized tags. Value: "true" (moebooru) or "extended" (gelbooru-style).
NO_AUTH_TAG_OPTIONS: Dict[str, List[tuple]] = {
    "3dbooru": [("tags", "true")],
    "furry34": [("tags", "true")],
    "hypnohub": [("tags", "extended")],
    "konachan": [("tags", "true")],
    "lolibooru": [("tags", "true")],
    "realbooru": [("tags", "extended")],
    "rule34us": [("tags", "extended")],
    "safebooru": [("tags", "extended")],
    "sakugabooru": [("tags", "true")],
    "tbib": [("tags", "extended")],
    "xbooru": [("tags", "extended")],
}

# (id, extractor, domains, credentials, tags_value, override_key, uses_resolve_urls, uses_direct_download, retry_on_empty, supports_browse)
AUTH_SITES: List[Tuple[str, str, List[str], List[str], Optional[str], Optional[str], bool, bool, bool, bool]] = [
    ("sankaku", "sankaku", ["sankaku.app", "sankakucomplex.com"], ["username", "password"], "standard", "sankaku", False, False, False, True),
    ("twitter", "twitter", ["twitter.com", "x.com"], [], None, "twitter", True, True, False, False),
    ("misskey", "misskey", ["misskey.io", "misskey.art", "misskey.net", "misskey.love", "misskey.jp",
     "misskey.design", "misskey.xyz", "mi.0px.io", "misskey.pizza"], ["access-token", "username", "password"], None, "misskey", True, True, False, False),
    ("rule34", "rule34", ["rule34.xxx"], ["api-key", "user-id"], "extended", "rule34", False, False, True, True),
    ("rule34vault", "rule34vault", ["rule34vault.com"], [], None, None, False, False, False, False),
    ("danbooru", "danbooru", ["danbooru.donmai.us"], ["api-key", "user-id"], "extended", "danbooru", False, False, False, True),
    ("gelbooru", "gelbooru", ["gelbooru.com"], ["api-key", "user-id"], "extended", "gelbooru", False, False, False, True),
    ("yandere", "yandere", ["yande.re"], [], "true", "yandere", False, False, False, True),
    ("reddit", "reddit", ["reddit.com"], ["client-id", "client-secret", "username"], None, "reddit", False, False, False, False),
    ("e621", "e621", ["e621.net"], ["username", "password"], "true", None, False, False, False, False),
]


def get_auth_site_defs() -> List[Dict[str, Any]]:
    """Return auth site definitions as dicts for handler construction."""
    return [
        {
            "id": sid,
            "extractor": ext,
            "domains": domains,
            "credentials": creds,
            "tags_value": tags,
            "override_key": override,
            "uses_resolve_urls": u_resolve,
            "uses_direct_download": u_direct,
            "retry_on_empty": retry,
            "supports_browse": browse,
        }
        for sid, ext, domains, creds, tags, override, u_resolve, u_direct, retry, browse in AUTH_SITES
    ]


def get_no_auth_site_defs() -> List[Dict[str, Any]]:
    """Return no-auth site definitions from NO_AUTH_SITES + NO_AUTH_TAG_OPTIONS."""
    return [
        {
            "id": eid,
            "extractor": eid,
            "domains": [domain],
            "credentials": [],
            "tags_value": (opts[0][1] if (opts := NO_AUTH_TAG_OPTIONS.get(eid)) else None),
            "override_key": None,
            "uses_resolve_urls": False,
            "uses_direct_download": False,
            "retry_on_empty": False,
            "supports_browse": False,
        }
        for eid, domain in NO_AUTH_SITES
    ]
