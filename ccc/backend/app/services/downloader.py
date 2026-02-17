"""
Download service – wraps gallery-dl and yt-dlp.
Tries gallery-dl first; if unsupported, falls back to yt-dlp.
Returns a list of downloaded file paths and any parsed metadata.
"""

import asyncio
import json
import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse, parse_qs

from app.config import get_settings
from app.sites.registry import get_handler, normalize_url
from app.utils.mime import extension_from_content_type

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
        """Return the URL to use for downloading this media."""
        if self.source_url and self.source_url != self.url:
            return self.source_url
        return self.url


# ---------------------------------------------------------------------------
# Subprocess helper
# ---------------------------------------------------------------------------


async def _run_subprocess(
    cmd: List[str],
    timeout: float,
    cleanup_paths: Optional[List[Path]] = None,
) -> Tuple[int, str, str]:
    """
    Run a subprocess with timeout and temp-file cleanup.

    Returns (returncode, stdout, stderr) as decoded strings.
    Raises asyncio.TimeoutError or FileNotFoundError on those conditions.
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        raw_stdout, raw_stderr = await asyncio.wait_for(
            proc.communicate(), timeout=timeout
        )
    finally:
        for p in cleanup_paths or []:
            try:
                p.unlink(missing_ok=True)
            except Exception as e:
                logger.debug("Cleanup temp file %s: %s", p, e)

    stdout = raw_stdout.decode("utf-8", errors="replace").strip()
    stderr = raw_stderr.decode(errors="replace").strip()
    return proc.returncode, stdout, stderr


# ---------------------------------------------------------------------------
# Direct media URL extraction for resolve-urls sites (Twitter, Misskey, etc.)
# ---------------------------------------------------------------------------


async def _resolve_direct_media_urls(url: str, user_config: Optional[Dict] = None) -> List[str]:
    """
    Use gallery-dl --resolve-urls to get direct media URLs.

    For Twitter/Misskey, this returns the original (best quality) media URLs.
    We only want the non-indented lines (the orig URLs).
    """
    try:
        opts, cleanup_paths = _gallery_dl_options(url, user_config)
        cmd = ["gallery-dl", "--resolve-urls", *opts, url]
        logger.debug("Running gallery-dl --resolve-urls for %s", url)

        returncode, stdout, stderr = await _run_subprocess(
            cmd, settings.gallery_dl_timeout, cleanup_paths
        )

        if returncode != 0:
            logger.warning("gallery-dl --resolve-urls exited %d: %s", returncode, stderr)
            return []

        if not stdout:
            logger.warning("gallery-dl --resolve-urls produced no output for %s", url)
            return []

        # Parse output - only take lines that don't start with '|' (those are alternative sizes)
        direct_urls = [
            line.strip() for line in stdout.split("\n")
            if line.strip() and not line.strip().startswith("|")
        ]

        logger.info("Resolved %d direct media URL(s) for %s", len(direct_urls), url)
        return direct_urls

    except asyncio.TimeoutError:
        logger.error("gallery-dl --resolve-urls timed out for %s", url)
        return []
    except FileNotFoundError:
        logger.error("gallery-dl binary not found")
        return []
    except Exception:
        logger.exception("gallery-dl --resolve-urls unexpected error for %s", url)
        return []


async def download_url(url: str, dest_dir: str, source_url: Optional[str] = None, user_config: Optional[Dict] = None) -> DownloadResult:
    """
    Download media from *url* into *dest_dir*.
    1. Try gallery-dl (with JSON metadata output).
    2. If gallery-dl fails / unsupported, try yt-dlp.
    3. Return paths + any parsed metadata.

    Args:
        url: URL to download
        dest_dir: Destination directory
        source_url: Optional source URL override
        user_config: Per-user credentials from database ({site_name: {key: value}})
    """
    url = normalize_url(url)
    os.makedirs(dest_dir, exist_ok=True)

    result = await _try_gallery_dl(url, dest_dir, user_config)
    if result.files:
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
    Download a direct media URL (e.g., pbs.twimg.com/media/xxx.jpg) directly via HTTP.
    Used for sites where we already have the exact media URL.
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
                    content_disp = resp.headers.get("Content-Disposition", "")
                    if "filename=" in content_disp:
                        filename = content_disp.split("filename=")[1].strip('"')
                    else:
                        filename = _extract_filename_from_url(url)
                        if not Path(filename).suffix:
                            ext = extension_from_content_type(resp.headers.get("Content-Type", ""))
                            if ext:
                                filename = f"{filename}.{ext}"

                # Ensure unique filename
                file_path = Path(dest_dir) / filename
                if file_path.exists():
                    base, suffix = file_path.stem, file_path.suffix
                    counter = 1
                    while file_path.exists():
                        file_path = Path(dest_dir) / f"{base}_{counter}{suffix}"
                        counter += 1

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


async def extract_media_urls(url: str, user_config: Optional[Dict] = None) -> List[ExtractedMedia]:
    """
    Phase 1: Extract direct media URLs without downloading.

    For resolve-urls sites (Twitter/Misskey): Uses --resolve-urls to get direct media URLs.
    For other sites: Uses --dump-json to get metadata.
    """
    url = normalize_url(url)
    handler = get_handler(url, user_config)
    if handler and handler.uses_resolve_urls:
        return await _extract_resolve_urls_media(url, user_config)
    return await _extract_generic_media(url, user_config)


def _fallback_media(url: str) -> ExtractedMedia:
    """Create a fallback ExtractedMedia when extraction fails."""
    return ExtractedMedia(
        url=url, source_url=url,
        filename=_extract_filename_from_url(url),
        metadata=None,
    )


async def _extract_resolve_urls_media(url: str, user_config: Optional[Dict] = None) -> List[ExtractedMedia]:
    """Extract media info using --resolve-urls (for sites like Twitter/Misskey)."""
    direct_urls = await _resolve_direct_media_urls(url, user_config)

    if not direct_urls:
        logger.warning("No direct media URLs resolved for %s, using original URL", url)
        return [_fallback_media(url)]

    results: List[ExtractedMedia] = []
    for idx, direct_url in enumerate(direct_urls):
        filename = _extract_filename_from_url(direct_url)

        # Extract extension from URL query params (e.g., ?format=jpg)
        parsed = urlparse(direct_url)
        fmt = parse_qs(parsed.query).get("format", [None])[0]
        if fmt and not Path(filename).suffix:
            filename = f"{filename}.{fmt}"

        results.append(ExtractedMedia(
            url=url,
            source_url=direct_url,
            filename=filename,
            metadata={"media_index": idx + 1, "total_media": len(direct_urls)},
        ))

    logger.info("Extracted %d media item(s) from %s", len(results), url)
    return results


async def _extract_generic_media(url: str, user_config: Optional[Dict] = None) -> List[ExtractedMedia]:
    """Extract media info for generic URLs using --dump-json."""
    results: List[ExtractedMedia] = []

    try:
        opts, cleanup_paths = _gallery_dl_options(url, user_config)
        cmd = ["gallery-dl", "--dump-json", "--no-download", *opts, url]

        returncode, stdout, stderr = await _run_subprocess(
            cmd, settings.gallery_dl_timeout, cleanup_paths
        )

        if returncode != 0:
            logger.warning("gallery-dl --dump-json exited %d: %s", returncode, stderr)
            return [_fallback_media(url)]

        if not stdout:
            logger.warning("gallery-dl --dump-json produced no output for %s", url)
            return [_fallback_media(url)]

        try:
            data = json.loads(stdout)
        except json.JSONDecodeError as e:
            logger.warning("Failed to parse gallery-dl JSON: %s, content: %s", e, stdout[:500])
            return [_fallback_media(url)]

        if isinstance(data, dict):
            data = [data]

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
            post_id = item.get("id") or item.get("md5")
            if post_id and post_id in seen_ids:
                continue
            if post_id:
                seen_ids.add(post_id)

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
                metadata=metadata if metadata else None,
            ))

        if not results:
            results.append(_fallback_media(url))

    except asyncio.TimeoutError:
        logger.error("gallery-dl --dump-json timed out after %ss for %s", settings.gallery_dl_timeout, url)
        results.append(_fallback_media(url))
    except FileNotFoundError:
        logger.error("gallery-dl binary not found")
        results.append(_fallback_media(url))
    except Exception:
        logger.exception("gallery-dl --dump-json unexpected error for %s", url)
        results.append(_fallback_media(url))

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

def _gallery_dl_options(url: str, user_config: Optional[Dict] = None) -> Tuple[List[str], List[Path]]:
    """
    Build optional gallery-dl args and any temp files to clean up after the subprocess.
    Delegates to the site handler for credentials, tag options, and cookie handling.

    Args:
        url: The URL to download
        user_config: Per-user credentials from database ({site_name: {key: value}})
    """
    opts: List[str] = []
    cleanup_paths: List[Path] = []
    if settings.gallery_dl_config_file:
        opts.extend(["-c", settings.gallery_dl_config_file])

    handler = get_handler(url, user_config)
    if handler:
        opts.extend(handler.gallery_dl_options())
        cleanup_paths.extend(handler.gallery_dl_cleanup_paths())

    return (opts, cleanup_paths)


async def _try_gallery_dl(url: str, dest_dir: str, user_config: Optional[Dict] = None) -> DownloadResult:
    result = DownloadResult(source_url=url, used_tool="gallery-dl")
    try:
        opts, cleanup_paths = _gallery_dl_options(url, user_config)
        cmd = ["gallery-dl", "--dest", dest_dir, "--write-metadata", "--no-mtime", *opts, url]

        returncode, _stdout, stderr = await _run_subprocess(
            cmd, settings.gallery_dl_timeout, cleanup_paths
        )

        if returncode != 0:
            logger.warning("gallery-dl exited %d: %s", returncode, stderr)
            result.error = stderr
            # Don't return early – there may still be files.

        # Collect downloaded files (gallery-dl writes into subdirs).
        files: List[Path] = []
        metadata: Dict = {}
        for root, _dirs, filenames in os.walk(dest_dir):
            for fn in filenames:
                fp = Path(root) / fn
                if fn.endswith(".json"):
                    try:
                        with open(fp, "r", encoding="utf-8") as f:
                            metadata = json.load(f)
                    except Exception:
                        pass
                elif fn.endswith(".txt"):
                    logger.debug("Skipping text content file: %s", fn)
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
        cmd = ["yt-dlp", "--no-playlist", "-o", output_template, "--write-info-json", url]

        returncode, _stdout, stderr = await _run_subprocess(
            cmd, settings.ytdlp_timeout
        )

        if returncode != 0:
            result.error = stderr
            logger.warning("yt-dlp exited %d: %s", returncode, stderr)
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
