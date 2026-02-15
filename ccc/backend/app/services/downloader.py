"""
Download service – wraps gallery-dl and yt-dlp.
Tries gallery-dl first; if unsupported, falls back to yt-dlp.
Returns a list of downloaded file paths and any parsed metadata.
"""

import asyncio
import json
import logging
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple
from urllib.parse import urlparse, parse_qs

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


@dataclass
class DownloadResult:
    """Result of a download attempt."""
    files: List[Path] = field(default_factory=list)
    metadata: Dict = field(default_factory=dict)
    source_url: Optional[str] = None
    error: Optional[str] = None
    used_tool: Optional[str] = None  # "gallery-dl" | "yt-dlp"
    tags: List[str] = field(default_factory=list)  # Tags extracted during download


@dataclass
class ExtractedMedia:
    """Represents an extracted media URL with metadata."""
    url: str  # The original page URL
    source_url: str  # The direct media URL (will be used as post source)
    filename: str  # Suggested filename
    metadata: Optional[Dict] = None  # Additional metadata from gallery-dl
    
    @property
    def download_url(self) -> str:
        """
        Return the URL to use for downloading this media.
        
        For Twitter/Misskey, we download from the direct media URL (source_url)
        to get individual files. For other sites, we use the original page URL.
        """
        # If source_url is a direct media URL (different from page URL), use it
        if self.source_url and self.source_url != self.url:
            return self.source_url
        return self.url


# ---------------------------------------------------------------------------
# URL type detection
# ---------------------------------------------------------------------------


def _is_twitter_url(url: str) -> bool:
    """True if URL is from Twitter/X."""
    lower = url.lower()
    return "twitter.com" in lower or "x.com" in lower


def _is_misskey_url(url: str) -> bool:
    """True if URL is from a Misskey instance."""
    lower = url.lower()
    # Common Misskey instances
    misskey_domains = [
        "misskey.io", "misskey.art", "misskey.net", "misskey.love", "misskey.jp",
        "misskey.design", "misskey.xyz", "mi.0px.io", "misskey.pizza"
    ]
    return any(domain in lower for domain in misskey_domains)


def _needs_resolve_urls(url: str) -> bool:
    """True if URL needs --resolve-urls to get direct media URLs. Sankaku uses generic --dump-json so we get tags."""
    if _is_sankaku_url(url):
        return False
    return _is_twitter_url(url) or _is_misskey_url(url)


# ---------------------------------------------------------------------------
# Direct media URL extraction for Twitter/Misskey
# ---------------------------------------------------------------------------


async def _resolve_direct_media_urls(url: str) -> List[str]:
    """
    Use gallery-dl --resolve-urls to get direct media URLs.
    
    For Twitter/Misskey, this returns the original (best quality) media URLs.
    Output format from --resolve-urls:
        https://pbs.twimg.com/media/xxx?format=jpg&name=orig
        | https://pbs.twimg.com/media/xxx?format=jpg&name=4096x4096
        | ...
    
    We only want the non-indented lines (the orig URLs).
    """
    try:
        opts, cleanup_paths = _gallery_dl_options(url)
        cmd = [
            "gallery-dl",
            "--resolve-urls",
            *opts,
            url,
        ]
        logger.debug("Running gallery-dl --resolve-urls for %s", url)
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=settings.gallery_dl_timeout
            )
        finally:
            for p in cleanup_paths:
                try:
                    p.unlink(missing_ok=True)
                except Exception as e:
                    logger.debug("Cleanup temp cookie file %s: %s", p, e)

        if proc.returncode != 0:
            err = stderr.decode(errors="replace").strip()
            logger.warning("gallery-dl --resolve-urls exited %d: %s", proc.returncode, err)
            return []

        output = stdout.decode("utf-8", errors="replace").strip()
        if not output:
            logger.warning("gallery-dl --resolve-urls produced no output for %s", url)
            return []

        # Parse output - only take lines that don't start with '|' (those are the orig URLs)
        direct_urls: List[str] = []
        for line in output.split("\n"):
            line = line.strip()
            # Skip empty lines and alternative size lines (prefixed with '|')
            if not line or line.startswith("|"):
                continue
            # This is a direct media URL (the orig version)
            direct_urls.append(line)

        logger.info("Resolved %d direct media URL(s) for %s", len(direct_urls), url)
        return direct_urls

    except asyncio.TimeoutError:
        logger.error("gallery-dl --resolve-urls timed out for %s", url)
        return []
    except FileNotFoundError:
        logger.error("gallery-dl binary not found")
        return []
    except Exception as exc:
        logger.exception("gallery-dl --resolve-urls unexpected error for %s", url)
        return []


async def download_url(url: str, dest_dir: str, source_url: Optional[str] = None) -> DownloadResult:
    """
    Download media from *url* into *dest_dir*.
    1. Try gallery-dl (with JSON metadata output).
    2. If gallery-dl fails / unsupported, try yt-dlp.
    3. Return paths + any parsed metadata.

    Args:
        url: The URL to download from.
        dest_dir: Destination directory for downloaded files.
        source_url: If provided, use this as the source instead of the page URL.
                   The source_url should be the direct media link for proper source tracking.
    """
    url = normalize_sankaku_url(url)
    os.makedirs(dest_dir, exist_ok=True)

    result = await _try_gallery_dl(url, dest_dir)
    if result.files:
        # Override source_url if provided
        if source_url:
            result.source_url = source_url
        return result

    logger.info("gallery-dl produced no files for %s – falling back to yt-dlp", url)
    result = await _try_ytdlp(url, dest_dir)
    if source_url:
        result.source_url = source_url
    return result


async def download_direct_media_url(url: str, dest_dir: str, filename: Optional[str] = None) -> DownloadResult:
    """
    Download a direct media URL (e.g., pbs.twimg.com/media/xxx.jpg) directly.
    
    This is used for Twitter/Misskey where we have the exact media URL and don't
    need gallery-dl to extract it. This ensures each file is downloaded individually.
    
    Args:
        url: The direct media URL to download.
        dest_dir: Destination directory for the downloaded file.
        filename: Optional filename to use. If not provided, extracts from URL.
    
    Returns:
        DownloadResult with the downloaded file path.
    """
    import aiohttp
    
    os.makedirs(dest_dir, exist_ok=True)
    result = DownloadResult(source_url=url, used_tool="direct")
    
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=60)) as resp:
                if resp.status != 200:
                    result.error = f"HTTP {resp.status}: {await resp.text()}"
                    logger.warning("Direct download failed for %s: %s", url, result.error)
                    return result
                
                # Determine filename
                if not filename:
                    # Try to get filename from Content-Disposition header
                    content_disp = resp.headers.get("Content-Disposition", "")
                    if "filename=" in content_disp:
                        filename = content_disp.split("filename=")[1].strip('"')
                    else:
                        # Extract from URL
                        filename = _extract_filename_from_url(url)
                        
                        # Add extension from Content-Type if missing
                        if not Path(filename).suffix:
                            content_type = resp.headers.get("Content-Type", "")
                            ext = _extension_from_content_type(content_type)
                            if ext:
                                filename = f"{filename}.{ext}"
                
                # Ensure unique filename
                file_path = Path(dest_dir) / filename
                if file_path.exists():
                    base = file_path.stem
                    suffix = file_path.suffix
                    counter = 1
                    while file_path.exists():
                        file_path = Path(dest_dir) / f"{base}_{counter}{suffix}"
                        counter += 1
                
                # Write the file
                content = await resp.read()
                with open(file_path, "wb") as f:
                    f.write(content)
                
                result.files = [file_path]
                logger.info("Direct download saved %s (%d bytes)", file_path.name, len(content))
                
    except asyncio.TimeoutError:
        result.error = "Direct download timed out"
        logger.error("Direct download timed out for %s", url)
    except Exception as exc:
        result.error = str(exc)
        logger.exception("Direct download failed for %s", url)
    
    return result


def _extension_from_content_type(content_type: str) -> str:
    """Map Content-Type header to file extension."""
    # Remove parameters like "charset=utf-8"
    content_type = content_type.split(";")[0].strip().lower()
    
    mapping = {
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/bmp": "bmp",
        "image/tiff": "tiff",
        "video/mp4": "mp4",
        "video/webm": "webm",
        "video/x-matroska": "mkv",
        "video/quicktime": "mov",
        "video/x-msvideo": "avi",
    }
    return mapping.get(content_type, "")


async def extract_media_urls(url: str) -> List[ExtractedMedia]:
    """
    Phase 1: Extract direct media URLs without downloading.

    For Twitter/Misskey: Uses --resolve-urls to get direct media URLs.
    For other sites: Uses --dump-json to get metadata.
    
    Returns list of ExtractedMedia objects with:
    - url: The original page URL (used for downloading)
    - source_url: The direct media URL (used for Szurubooru source field)
    - filename: Suggested filename
    - metadata: Any additional metadata from gallery-dl

    For single-file sources, returns a list with one ExtractedMedia.
    For multi-file sources (galleries), returns one ExtractedMedia per file.
    """
    url = normalize_sankaku_url(url)
    if _is_sankaku_url(url):
        return await _extract_generic_media(url)
    # Twitter/Misskey: use --resolve-urls for direct media URLs
    if _needs_resolve_urls(url):
        return await _extract_twitter_misskey_media(url)
    # All other sites: --dump-json for metadata
    return await _extract_generic_media(url)


async def _extract_twitter_misskey_media(url: str) -> List[ExtractedMedia]:
    """
    Extract media info for Twitter/Misskey URLs using --resolve-urls.
    
    This approach:
    1. Uses --resolve-urls to get direct media URLs (for source tracking)
    2. Returns ExtractedMedia with the original URL for downloading
    3. The direct media URL is stored as source_url for Szurubooru
    """
    results: List[ExtractedMedia] = []
    
    # Get direct media URLs using --resolve-urls
    direct_urls = await _resolve_direct_media_urls(url)
    
    if not direct_urls:
        # Fallback - return the original URL
        logger.warning("No direct media URLs resolved for %s, using original URL", url)
        return [ExtractedMedia(
            url=url,
            source_url=url,
            filename=_extract_filename_from_url(url),
            metadata=None
        )]
    
    # Create ExtractedMedia for each direct URL
    for idx, direct_url in enumerate(direct_urls):
        # Extract filename from the direct URL
        filename = _extract_filename_from_url(direct_url)
        
        # Extract extension from URL query params (e.g., ?format=jpg)
        parsed = urlparse(direct_url)
        query_params = parse_qs(parsed.query)
        fmt = query_params.get("format", [None])[0]
        
        # If we have a format but no extension in filename, add it
        if fmt and not Path(filename).suffix:
            filename = f"{filename}.{fmt}"
        
        results.append(ExtractedMedia(
            url=url,  # Original page URL - used for downloading
            source_url=direct_url,  # Direct media URL - used for Szurubooru source
            filename=filename,
            metadata={"media_index": idx + 1, "total_media": len(direct_urls)}
        ))
    
    logger.info("Extracted %d media item(s) from %s", len(results), url)
    return results


async def _extract_generic_media(url: str) -> List[ExtractedMedia]:
    """
    Extract media info for generic URLs using --dump-json.
    
    This is the original extraction logic for non-Twitter/Misskey sites.
    """
    results: List[ExtractedMedia] = []

    try:
        opts, cleanup_paths = _gallery_dl_options(url)
        cmd = [
            "gallery-dl",
            "--dump-json",
            "--no-download",    # Prevents file downloads during metadata extraction
            *opts,
            url,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=settings.gallery_dl_timeout
            )
        finally:
            for p in cleanup_paths:
                try:
                    p.unlink(missing_ok=True)
                except Exception as e:
                    logger.debug("Cleanup temp cookie file %s: %s", p, e)

        if proc.returncode != 0:
            err = stderr.decode(errors="replace").strip()
            logger.warning("gallery-dl --dump-json exited %d: %s", proc.returncode, err)
            # Fall back to returning the original URL as a single media item
            return [ExtractedMedia(
                url=url,
                source_url=url,
                filename=_extract_filename_from_url(url),
                metadata=None
            )]

        # Parse JSON output - gallery-dl outputs a JSON array (pretty-printed)
        output = stdout.decode("utf-8", errors="replace").strip()
        if not output:
            logger.warning("gallery-dl --dump-json produced no output for %s", url)
            return [ExtractedMedia(
                url=url,
                source_url=url,
                filename=_extract_filename_from_url(url),
                metadata=None
            )]

        # Parse entire output as JSON array (gallery-dl --dump-json outputs pretty-printed JSON)
        try:
            data = json.loads(output)
        except json.JSONDecodeError as e:
            logger.warning("Failed to parse gallery-dl JSON: %s, content: %s", e, output[:500])
            # Fall back to returning the original URL as a single media item
            return [ExtractedMedia(
                url=url,
                source_url=url,
                filename=_extract_filename_from_url(url),
                metadata=None
            )]

        # Handle both single object and array output
        if isinstance(data, dict):
            data = [data]

        # gallery-dl --dump-json can output [type_id, dict] or [type_id, url, dict] per item; unwrap to get the dict
        def _unwrap_item(raw):
            if isinstance(raw, dict):
                return raw, None
            if isinstance(raw, list) and len(raw) >= 2 and isinstance(raw[-1], dict):
                direct = raw[1] if len(raw) == 3 and isinstance(raw[1], str) and raw[1].startswith("http") else None
                return raw[-1], direct
            return None, None

        seen_ids: set = set()
        for raw_item in data:
            item, direct_url = _unwrap_item(raw_item)
            if not item:
                continue
            # Dedupe: gallery-dl often emits [2, metadata] and [3, url, metadata] for the same post
            post_id = item.get("id") or item.get("md5")
            if post_id and post_id in seen_ids:
                continue
            if post_id:
                seen_ids.add(post_id)

            # Extract the direct media URL from gallery-dl's JSON
            media_url = direct_url or item.get("url") or item.get("file_url") or item.get("sample_url") or item.get("download_url") or url
            extension = item.get("extension", "") or (item.get("file_ext") or "")
            base_filename = item.get("filename") or item.get("name") or _extract_filename_from_url(media_url)

            if extension and not base_filename.endswith(f".{extension}"):
                filename = f"{base_filename}.{extension}"
            else:
                filename = base_filename

            metadata = {k: v for k, v in item.items() if k not in ("url", "filename", "extension", "name", "file_url", "sample_url")}

            results.append(ExtractedMedia(
                url=url,
                source_url=media_url,
                filename=filename,
                metadata=metadata if metadata else None
            ))

        if not results:
            # No valid JSON parsed, fall back to original URL
            results.append(ExtractedMedia(
                url=url,
                source_url=url,
                filename=_extract_filename_from_url(url),
                metadata=None
            ))

    except asyncio.TimeoutError:
        logger.error("gallery-dl --dump-json timed out after %ss for %s", settings.gallery_dl_timeout, url)
        results.append(ExtractedMedia(
            url=url,
            source_url=url,
            filename=_extract_filename_from_url(url),
            metadata=None
        ))
    except FileNotFoundError:
        logger.error("gallery-dl binary not found")
        results.append(ExtractedMedia(
            url=url,
            source_url=url,
            filename=_extract_filename_from_url(url),
            metadata=None
        ))
    except Exception as exc:
        logger.exception("gallery-dl --dump-json unexpected error for %s", url)
        results.append(ExtractedMedia(
            url=url,
            source_url=url,
            filename=_extract_filename_from_url(url),
            metadata=None
        ))

    return results


def _extract_filename_from_url(url: str) -> str:
    """Extract a filename from a URL as a fallback."""
    from urllib.parse import urlparse, unquote
    parsed = urlparse(url)
    path = unquote(parsed.path)
    filename = path.split("/")[-1] if path.split("/") else "download"
    return filename or "download"


# ---------------------------------------------------------------------------
# gallery-dl
# ---------------------------------------------------------------------------

def normalize_sankaku_url(url: str) -> str:
    """Use www.sankakucomplex.com so gallery-dl and credential logic work (apex domain is unsupported)."""
    if not url or not url.strip():
        return url
    parsed = urlparse(url.strip())
    if parsed.netloc.lower() == "sankakucomplex.com":
        return parsed._replace(netloc="www.sankakucomplex.com").geturl()
    return url


def _is_sankaku_url(url: str) -> bool:
    """True if URL is a Sankaku image board (sankaku.app or sankakucomplex.com)."""
    lower = url.lower()
    return "sankaku.app" in lower or "sankakucomplex.com" in lower


def _is_rule34_url(url: str) -> bool:
    """True if URL is rule34.xxx."""
    return "rule34.xxx" in url.lower()


def _is_danbooru_url(url: str) -> bool:
    """True if URL is a Danbooru instance (danbooru.donmai.us, safebooru.org, etc.)."""
    lower = url.lower()
    return "danbooru.donmai.us" in lower or "safebooru.org" in lower


def _is_gelbooru_url(url: str) -> bool:
    """True if URL is Gelbooru (rule34.xxx and others have their own injectors)."""
    return "gelbooru.com" in url.lower()


def _is_reddit_url(url: str) -> bool:
    """True if URL is reddit.com."""
    return "reddit.com" in url.lower()


# Extended/categorized tags: (url_matcher, extractor_name, [(option_key, option_value), ...]).
# Sankaku: do NOT use tags=extended (scrapes chan.sankakucomplex.com). We force tags=standard so
# gallery-dl uses API /posts/{id}/tags and fills tags_artist, tags_character, tags_copyright, etc.
# Explicit option overrides any gallery-dl config file that might set tags=extended.
def _gallery_dl_extended_tag_options() -> List[Tuple[Callable[[str], bool], str, List[Tuple[str, str]]]]:
    return [
        (lambda u: "yande.re" in u, "yandere", [("tags", "true")]),
        (_is_sankaku_url, "sankaku", [("tags", "standard")]),
    ]


# One entry per site: (url_matcher, extractor_name, [(option_key, value_getter), ...]).
def _gallery_dl_credential_getters() -> List[Tuple[Callable[[str], bool], str, List[Tuple[str, Callable[[], Optional[str]]]]]]:
    s = settings
    return [
        (_is_sankaku_url, "sankaku", [
            ("username", lambda: (s.gallery_dl_sankaku_username or "").strip() or None),
            ("password", lambda: (s.gallery_dl_sankaku_password or "").strip() or None),
        ]),
        (_is_rule34_url, "rule34", [
            ("api-key", lambda: (s.gallery_dl_rule34_api_key or "").strip() or None),
            ("user-id", lambda: (s.gallery_dl_rule34_user_id or "").strip() or None),
        ]),
        (_is_misskey_url, "misskey", [
            ("username", lambda: (s.gallery_dl_misskey_username or "").strip() or None),
            ("password", lambda: (s.gallery_dl_misskey_password or "").strip() or None),
        ]),
        (_is_danbooru_url, "danbooru", [
            ("api-key", lambda: (s.gallery_dl_danbooru_api_key or "").strip() or None),
            ("user-id", lambda: (s.gallery_dl_danbooru_user_id or "").strip() or None),
        ]),
        (_is_gelbooru_url, "gelbooru", [
            ("api-key", lambda: (s.gallery_dl_gelbooru_api_key or "").strip() or None),
            ("user-id", lambda: (s.gallery_dl_gelbooru_user_id or "").strip() or None),
        ]),
        (_is_reddit_url, "reddit", [
            ("client-id", lambda: (s.gallery_dl_reddit_client_id or "").strip() or None),
            ("client-secret", lambda: (s.gallery_dl_reddit_client_secret or "").strip() or None),
            ("user-agent", lambda: (f"Python:ExtendedUploader:v1.0 (by /u/{(s.gallery_dl_reddit_username or '').strip()})" if (s.gallery_dl_reddit_username or "").strip() else None)),
        ]),
        (_is_twitter_url, "twitter", [
            ("username", lambda: (s.gallery_dl_twitter_username or "").strip() or None),
            ("password", lambda: (s.gallery_dl_twitter_password or "").strip() or None),
        ]),
    ]


def _gallery_dl_options(url: str) -> Tuple[List[str], List[Path]]:
    """
    Build optional gallery-dl args and any temp files to clean up after the subprocess.
    Credentials are injected per-site from _gallery_dl_credential_getters; Twitter cookies are a special case.
    """
    opts: List[str] = []
    cleanup_paths: List[Path] = []
    if settings.gallery_dl_config_file:
        opts.extend(["-c", settings.gallery_dl_config_file])

    for matcher, extractor_name, options in _gallery_dl_extended_tag_options():
        if matcher(url):
            for opt_key, opt_value in options:
                opts.extend(["-o", f"extractor.{extractor_name}.{opt_key}={opt_value}"])
            break

    for matcher, extractor_name, key_getters in _gallery_dl_credential_getters():
        if not matcher(url):
            continue
        added = 0
        for opt_key, getter in key_getters:
            value = getter()
            if value:
                opts.extend(["-o", f"extractor.{extractor_name}.{opt_key}={value}"])
                added += 1
        if extractor_name == "rule34" and added:
            logger.info("Rule34 API credentials injected for request")

    if _is_twitter_url(url):
        cookies_content = (settings.gallery_dl_twitter_cookies or "").strip()
        if cookies_content:
            try:
                fd = tempfile.NamedTemporaryFile(
                    mode="w",
                    delete=False,
                    suffix=".txt",
                    prefix="ccc_twitter_cookies_",
                    encoding="utf-8",
                )
                fd.write(cookies_content)
                fd.close()
                path = Path(fd.name)
                cleanup_paths.append(path)
                opts.extend(["-o", f"extractor.twitter.cookies={path}"])
            except Exception as e:
                logger.warning("Failed to write Twitter cookies temp file: %s", e)
    return (opts, cleanup_paths)


async def _try_gallery_dl(url: str, dest_dir: str) -> DownloadResult:
    result = DownloadResult(source_url=url, used_tool="gallery-dl")
    try:
        opts, cleanup_paths = _gallery_dl_options(url)
        cmd = [
            "gallery-dl",
            "--dest", dest_dir,
            "--write-metadata",
            "--no-mtime",
            *opts,
            url,
        ]
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=settings.gallery_dl_timeout
            )
        finally:
            for p in cleanup_paths:
                try:
                    p.unlink(missing_ok=True)
                except Exception as e:
                    logger.debug("Cleanup temp cookie file %s: %s", p, e)

        if proc.returncode != 0:
            err = stderr.decode(errors="replace").strip()
            logger.warning("gallery-dl exited %d: %s", proc.returncode, err)
            result.error = err
            # Don't return early – there may still be files.

        # Collect downloaded files (gallery-dl writes into subdirs).
        # Note: gallery-dl may create .txt files for tweet content (Twitter postprocessor)
        # and .json files for metadata. We only want the actual media files.
        files: List[Path] = []
        metadata: Dict = {}
        for root, _dirs, filenames in os.walk(dest_dir):
            for fn in filenames:
                fp = Path(root) / fn
                if fn.endswith(".json"):
                    # gallery-dl metadata sidecar
                    try:
                        with open(fp, "r", encoding="utf-8") as f:
                            metadata = json.load(f)
                    except Exception:
                        pass
                elif fn.endswith(".txt"):
                    # Tweet content file from Twitter postprocessor - skip
                    logger.debug("Skipping tweet content file: %s", fn)
                    pass
                else:
                    logger.debug("Found media file: %s", fn)
                    files.append(fp)
        
        logger.info("gallery-dl downloaded %d media file(s) to %s", len(files), dest_dir)

        result.files = files
        result.metadata = metadata
        if files:
            result.error = None  # Clear error if we got files anyway.

    except asyncio.TimeoutError:
        result.error = f"gallery-dl timed out after {settings.gallery_dl_timeout}s"
        logger.error(result.error)
    except FileNotFoundError:
        result.error = "gallery-dl binary not found"
        logger.error(result.error)
    except Exception as exc:
        result.error = str(exc)
        logger.exception("gallery-dl unexpected error")

    return result


# ---------------------------------------------------------------------------
# yt-dlp
# ---------------------------------------------------------------------------

async def _try_ytdlp(url: str, dest_dir: str) -> DownloadResult:
    result = DownloadResult(source_url=url, used_tool="yt-dlp")
    try:
        output_template = os.path.join(dest_dir, "%(title)s.%(ext)s")
        cmd = [
            "yt-dlp",
            "--no-playlist",
            "-o", output_template,
            "--write-info-json",
            url,
        ]
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=settings.ytdlp_timeout
        )

        if proc.returncode != 0:
            err = stderr.decode(errors="replace").strip()
            result.error = err
            logger.warning("yt-dlp exited %d: %s", proc.returncode, err)
            return result

        # Collect files
        files: List[Path] = []
        metadata: Dict = {}
        for fn in os.listdir(dest_dir):
            fp = Path(dest_dir) / fn
            if fn.endswith(".info.json"):
                try:
                    with open(fp, "r", encoding="utf-8") as f:
                        metadata = json.load(f)
                except Exception:
                    pass
            elif fp.is_file():
                files.append(fp)

        result.files = files
        result.metadata = metadata

    except asyncio.TimeoutError:
        result.error = f"yt-dlp timed out after {settings.ytdlp_timeout}s"
        logger.error(result.error)
    except FileNotFoundError:
        result.error = "yt-dlp binary not found"
        logger.error(result.error)
    except Exception as exc:
        result.error = str(exc)
        logger.exception("yt-dlp unexpected error")

    return result
