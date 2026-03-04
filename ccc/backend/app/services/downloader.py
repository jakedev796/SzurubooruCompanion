"""
Download service – wraps gallery-dl and yt-dlp.
Tries gallery-dl first; if unsupported, falls back to yt-dlp.
Returns a list of downloaded file paths and any parsed metadata.
"""

import asyncio
import json
import logging
import os
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse, parse_qs

from app.config import get_settings
from app.sites.registry import get_handler

logger = logging.getLogger(__name__)
settings = get_settings()

# User-Agent used for all direct HTTP downloads (avoids blocks from CDNs that reject empty UA).
DEFAULT_DOWNLOAD_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0"
)


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
# Direct media URL extraction for Twitter/Misskey
# ---------------------------------------------------------------------------


async def _resolve_direct_media_urls(
    url: str, user_config: Optional[Dict] = None, gallery_dl_timeout: int = 120, proxy_url: Optional[str] = None
) -> List[str]:
    """
    Use gallery-dl --resolve-urls to get direct media URLs.

    For Twitter/Misskey, this returns the original (best quality) media URLs.
    Output format from --resolve-urls:
        https://pbs.twimg.com/media/xxx?format=jpg&name=orig
        | https://pbs.twimg.com/media/xxx?format=jpg&name=4096x4096
        | ...

    We only want the non-indented lines (the orig URLs).

    Args:
        url: The URL to resolve
        user_config: Per-user credentials from database (optional)
        gallery_dl_timeout: Subprocess timeout in seconds
    """
    try:
        opts, cleanup_paths = _gallery_dl_options(url, user_config, proxy_url=proxy_url)
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
                proc.communicate(), timeout=gallery_dl_timeout
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
        logger.error("gallery-dl --resolve-urls timed out after %ds for %s", gallery_dl_timeout, url)
        return []
    except FileNotFoundError:
        logger.error("gallery-dl binary not found")
        return []
    except Exception as exc:
        logger.exception("gallery-dl --resolve-urls unexpected error for %s", url)
        return []


async def download_url(
    url: str,
    dest_dir: str,
    source_url: Optional[str] = None,
    user_config: Optional[Dict] = None,
    gallery_dl_timeout: int = 120,
    ytdlp_timeout: int = 300,
    proxy_url: Optional[str] = None,
) -> DownloadResult:
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
        user_config: Per-user credentials from database (optional)
                    Format: {site_name: {credential_key: value}}
        gallery_dl_timeout: gallery-dl subprocess timeout in seconds.
        ytdlp_timeout: yt-dlp subprocess timeout in seconds.
    """
    handler = get_handler(url, user_config)
    url = handler.normalize_url(url) if handler else url
    os.makedirs(dest_dir, exist_ok=True)

    result = await _try_gallery_dl(url, dest_dir, user_config, gallery_dl_timeout, proxy_url=proxy_url)
    if result.files:
        if source_url:
            result.source_url = source_url
        return result

    if handler and handler.retry_on_empty:
        logger.info("gallery-dl produced no files for %s URL, retrying once: %s", handler.name, url)
        await asyncio.sleep(2)
        result = await _try_gallery_dl(url, dest_dir, user_config, gallery_dl_timeout, proxy_url=proxy_url)
        if result.files:
            if source_url:
                result.source_url = source_url
            return result

    logger.info("gallery-dl produced no files for %s – falling back to yt-dlp", url)
    result = await _try_ytdlp(url, dest_dir, ytdlp_timeout, proxy_url=proxy_url)
    if source_url:
        result.source_url = source_url
    return result


async def download_direct_media_url(url: str, dest_dir: str, filename: Optional[str] = None, proxy_url: Optional[str] = None) -> DownloadResult:
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

    headers = {"User-Agent": DEFAULT_DOWNLOAD_USER_AGENT}

    try:
        async with aiohttp.ClientSession() as session:
            req_kwargs = {"headers": headers, "timeout": aiohttp.ClientTimeout(total=60)}
            if proxy_url:
                req_kwargs["proxy"] = proxy_url
            async with session.get(url, **req_kwargs) as resp:
                if resp.status != 200:
                    result.error = f"HTTP {resp.status}: {await resp.text()}"
                    logger.warning("Direct download failed for %s: %s", url, result.error)
                    return result

                # Reject HTML responses (e.g. hotlink protection pages)
                content_type = resp.headers.get("Content-Type", "")
                ct_base = content_type.split(";")[0].strip().lower()
                if ct_base in ("text/html", "application/xhtml+xml"):
                    result.error = (
                        f"Server returned HTML instead of media (Content-Type: {ct_base}). "
                        "The host may be blocking direct downloads."
                    )
                    logger.warning("Direct download for %s returned HTML, not media", url)
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
                            ext = _extension_from_content_type(content_type)
                            if ext:
                                filename = f"{filename}.{ext}"
                elif not Path(filename).suffix:
                    # Filename was provided but has no extension (e.g. Reddit t3_xxx); add from Content-Type
                    ext = _extension_from_content_type(content_type)
                    if ext:
                        filename = f"{filename}.{ext}"

                if not filename:
                    filename = _extract_filename_from_url(url) or "download"

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


async def extract_media_urls(
    url: str, user_config: Optional[Dict] = None, gallery_dl_timeout: int = 120, proxy_url: Optional[str] = None
) -> List[ExtractedMedia]:
    """
    Phase 1: Extract direct media URLs without downloading.

    For Twitter/Misskey: Uses --resolve-urls to get direct media URLs.
    For other sites: Uses --dump-json to get metadata.

    Args:
        url: The URL to extract media from
        user_config: Per-user credentials from database (optional)
                    Format: {site_name: {credential_key: value}}
        gallery_dl_timeout: gallery-dl subprocess timeout in seconds.

    Returns list of ExtractedMedia objects with:
    - url: The original page URL (used for downloading)
    - source_url: The direct media URL (used for Szurubooru source field)
    - filename: Suggested filename
    - metadata: Any additional metadata from gallery-dl

    For single-file sources, returns a list with one ExtractedMedia.
    For multi-file sources (galleries), returns one ExtractedMedia per file.
    """
    handler = get_handler(url, user_config)
    url = handler.normalize_url(url) if handler else url
    if handler and handler.uses_resolve_urls:
        return await _extract_twitter_misskey_media(url, user_config, gallery_dl_timeout, proxy_url=proxy_url)
    return await _extract_generic_media(url, user_config, gallery_dl_timeout, proxy_url=proxy_url)


async def _extract_twitter_misskey_media(
    url: str, user_config: Optional[Dict] = None, gallery_dl_timeout: int = 120, proxy_url: Optional[str] = None
) -> List[ExtractedMedia]:
    """
    Extract media info for Twitter/Misskey URLs using --resolve-urls.

    This approach:
    1. Uses --resolve-urls to get direct media URLs (for source tracking)
    2. Returns ExtractedMedia with the original URL for downloading
    3. The direct media URL is stored as source_url for Szurubooru

    Args:
        url: The Twitter/Misskey URL to extract from
        user_config: Per-user credentials from database (optional)
        gallery_dl_timeout: gallery-dl subprocess timeout in seconds.
    """
    results: List[ExtractedMedia] = []

    # Get direct media URLs using --resolve-urls
    direct_urls = await _resolve_direct_media_urls(url, user_config, gallery_dl_timeout, proxy_url=proxy_url)
    
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


async def _extract_generic_media(
    url: str, user_config: Optional[Dict] = None, gallery_dl_timeout: int = 120, proxy_url: Optional[str] = None
) -> List[ExtractedMedia]:
    """
    Extract media info for generic URLs using --dump-json.

    This is the original extraction logic for non-Twitter/Misskey sites.

    Args:
        url: The URL to extract media from
        user_config: Per-user credentials from database (optional)
        gallery_dl_timeout: gallery-dl subprocess timeout in seconds.
    """
    results: List[ExtractedMedia] = []

    try:
        opts, cleanup_paths = _gallery_dl_options(url, user_config, proxy_url=proxy_url)
        cmd = [
            "gallery-dl",
            "--dump-json",
            "--no-download",
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
                proc.communicate(), timeout=gallery_dl_timeout
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
            # e621/danbooru-style APIs nest file URL under "file"
            file_obj = item.get("file") or {}
            media_url = (
                direct_url
                or item.get("url")
                or item.get("file_url")
                or (file_obj.get("url") if isinstance(file_obj, dict) else None)
                or item.get("sample_url")
                or item.get("download_url")
                or url
            )
            extension = item.get("extension", "") or (item.get("file_ext") or "")
            base_filename = item.get("filename") or item.get("name") or _extract_filename_from_url(media_url)

            if not extension and media_url:
                extension = _extension_from_media_url(media_url)
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
        logger.error("gallery-dl --dump-json timed out after %ds for %s", gallery_dl_timeout, url)
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


def _extension_from_media_url(url: str) -> str:
    """Derive file extension from a media URL path (e.g. i.redd.it/xxx.jpeg -> jpeg)."""
    try:
        parsed = urlparse(url)
        path = (parsed.path or "").strip().rstrip("/")
        if not path:
            return ""
        name = path.split("/")[-1]
        if "." in name:
            ext = name.rsplit(".", 1)[-1].lower()
            if ext in ("jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "mp4", "webm", "mkv", "mov", "avi", "gifv"):
                return "jpg" if ext == "jpeg" else ext
    except Exception:
        pass
    return ""


# ---------------------------------------------------------------------------
# gallery-dl
# ---------------------------------------------------------------------------


def _gallery_dl_options(url: str, user_config: Optional[Dict] = None, proxy_url: Optional[str] = None) -> Tuple[List[str], List[Path]]:
    """
    Build gallery-dl args from handlers only: tag options and credentials via -o flags from DB.
    Twitter cookies are written to a temp file and passed as path. No config file; all options from code.
    """
    opts: List[str] = []
    cleanup_paths: List[Path] = []

    if proxy_url:
        opts.extend(["--proxy", proxy_url])

    handler = get_handler(url, user_config)
    if handler:
        opts.extend(handler.gallery_dl_options(url))
        if handler.name == "rule34" and (user_config or {}).get("rule34"):
            logger.info("Rule34 API credentials injected for request")
        if handler.name == "twitter":
            cookies_content = None
            if user_config:
                site_creds = user_config.get("twitter", {})
                cookies_content = site_creds.get("cookies")
            cookies_content = (cookies_content or "").strip()
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


async def _try_gallery_dl(
    url: str, dest_dir: str, user_config: Optional[Dict] = None, gallery_dl_timeout: int = 120, proxy_url: Optional[str] = None
) -> DownloadResult:
    result = DownloadResult(source_url=url, used_tool="gallery-dl")
    try:
        opts, cleanup_paths = _gallery_dl_options(url, user_config, proxy_url=proxy_url)
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
                proc.communicate(), timeout=gallery_dl_timeout
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
        result.error = f"gallery-dl timed out after {gallery_dl_timeout}s"
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

async def _try_ytdlp(url: str, dest_dir: str, ytdlp_timeout: int = 300, proxy_url: Optional[str] = None) -> DownloadResult:
    result = DownloadResult(source_url=url, used_tool="yt-dlp")
    try:
        output_template = os.path.join(dest_dir, "%(title)s.%(ext)s")
        cmd = [
            "yt-dlp",
            "--no-playlist",
            "-o", output_template,
            "--write-info-json",
        ]
        if proxy_url:
            cmd.extend(["--proxy", proxy_url])
        cmd.append(url)
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=ytdlp_timeout
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
        result.error = f"yt-dlp timed out after {ytdlp_timeout}s"
        logger.error(result.error)
    except FileNotFoundError:
        result.error = "yt-dlp binary not found"
        logger.error(result.error)
    except Exception as exc:
        result.error = str(exc)
        logger.exception("yt-dlp unexpected error")

    return result
