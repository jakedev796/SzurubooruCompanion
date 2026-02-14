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
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

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


async def download_url(url: str, dest_dir: str) -> DownloadResult:
    """
    Download media from *url* into *dest_dir*.
    1. Try gallery-dl (with JSON metadata output).
    2. If gallery-dl fails / unsupported, try yt-dlp.
    3. Return paths + any parsed metadata.
    """
    os.makedirs(dest_dir, exist_ok=True)

    result = await _try_gallery_dl(url, dest_dir)
    if result.files:
        return result

    logger.info("gallery-dl produced no files for %s – falling back to yt-dlp", url)
    return await _try_ytdlp(url, dest_dir)


# ---------------------------------------------------------------------------
# gallery-dl
# ---------------------------------------------------------------------------

def _is_sankaku_url(url: str) -> bool:
    """True if URL is a Sankaku image board (sankaku.app or sankakucomplex.com subdomains)."""
    lower = url.lower()
    return "sankaku.app" in lower or ".sankakucomplex.com" in lower


def _gallery_dl_options(url: str) -> List[str]:
    """Build optional gallery-dl args: config file, per-extractor options, and Sankaku login when applicable."""
    opts: List[str] = []
    if settings.gallery_dl_config_file:
        opts.extend(["-c", settings.gallery_dl_config_file])
    if not settings.gallery_dl_config_file and "yande.re" in url:
        opts.extend(["-o", "extractor.yandere.tags=true"])
    if _is_sankaku_url(url):
        username = (settings.gallery_dl_sankaku_username or "").strip()
        password = (settings.gallery_dl_sankaku_password or "").strip()
        if username:
            opts.extend(["-o", f"extractor.sankaku.username={username}"])
        if password:
            opts.extend(["-o", f"extractor.sankaku.password={password}"])
    return opts


async def _try_gallery_dl(url: str, dest_dir: str) -> DownloadResult:
    result = DownloadResult(source_url=url, used_tool="gallery-dl")
    try:
        cmd = [
            "gallery-dl",
            "--dest", dest_dir,
            "--write-metadata",
            "--no-mtime",
            *_gallery_dl_options(url),
            url,
        ]
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=settings.gallery_dl_timeout
        )

        if proc.returncode != 0:
            err = stderr.decode(errors="replace").strip()
            logger.warning("gallery-dl exited %d: %s", proc.returncode, err)
            result.error = err
            # Don't return early – there may still be files.

        # Collect downloaded files (gallery-dl writes into subdirs).
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
                else:
                    files.append(fp)

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
