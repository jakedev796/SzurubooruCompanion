"""
Shared MIME type handling.
Ensures consistent type detection across the application, even in minimal Docker images.
"""

import mimetypes
from pathlib import Path

# Initialize and patch the mimetypes database once at import time.
mimetypes.init()

COMMON_MIME_TYPES = {
    # Images
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".avif": "image/avif",
    ".heic": "image/heic",
    ".heif": "image/heif",
    ".bmp": "image/bmp",
    ".tiff": "image/tiff",
    ".tif": "image/tiff",
    ".svg": "image/svg+xml",
    # Videos
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".mkv": "video/x-matroska",
    ".avi": "video/x-msvideo",
    ".mov": "video/quicktime",
    ".wmv": "video/x-ms-wmv",
    ".flv": "video/x-flv",
    # Audio
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".m4a": "audio/mp4",
}

# Reverse lookup: MIME type -> extension (for Content-Type header parsing)
_MIME_TO_EXT = {mime: ext.lstrip(".") for ext, mime in COMMON_MIME_TYPES.items()}
# Prefer "jpg" over "jpeg"
_MIME_TO_EXT["image/jpeg"] = "jpg"

# Patch the mimetypes database for minimal Docker images
for ext, mime in COMMON_MIME_TYPES.items():
    if ext not in mimetypes.types_map:
        mimetypes.add_type(mime, ext)


def guess_mime_type(filename: str) -> str:
    """Guess MIME type from filename. Returns 'application/octet-stream' as fallback."""
    mime, _ = mimetypes.guess_type(filename)
    return mime or "application/octet-stream"


def sniff_mime_type(data: bytes) -> str:
    """Detect common image/video formats from file signatures."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if data.startswith(b"BM"):
        return "image/bmp"
    if data.startswith((b"II*\x00", b"MM\x00*")):
        return "image/tiff"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if len(data) >= 12 and data[4:8] == b"ftyp":
        brand = data[8:12]
        if brand in {b"avif", b"avis"}:
            return "image/avif"
        # "mif1"/"msf1" are HEIF image brands, not MP4 ones.
        if brand in {b"mif1", b"msf1"}:
            return "image/heif"
        if brand in {b"heic", b"heix", b"hevc", b"hevx"}:
            return "image/heic"
        if brand in {b"mp4 ", b"isom", b"iso2", b"avc1", b"mp41", b"mp42"}:
            return "video/mp4"
    if data.startswith(b"\x1aE\xdf\xa3"):
        return "video/webm"
    return "application/octet-stream"


def detect_mime_type(path: str | Path) -> str:
    """Prefer magic-byte sniffing, then fall back to extension-based guessing."""
    try:
        with open(path, "rb") as f:
            head = f.read(32)
        sniffed = sniff_mime_type(head)
        if sniffed != "application/octet-stream":
            return sniffed
    except OSError:
        pass
    return guess_mime_type(str(path))


def normalized_filename(path: str | Path) -> str:
    """
    Return a filename whose extension matches detected content when possible.

    This keeps multipart filenames aligned with the actual bytes even when the
    source app supplied a misleading or missing extension.
    """
    p = Path(path)
    mime = detect_mime_type(p)
    ext = extension_from_content_type(mime)
    if not ext:
        return p.name

    expected_suffix = f".{ext}"
    current_suffix = p.suffix.lower()
    if current_suffix == expected_suffix:
        return p.name

    stem = p.stem if current_suffix else p.name
    return f"{stem}{expected_suffix}"


def extension_from_content_type(content_type: str) -> str:
    """Map a Content-Type header value to a file extension (without dot). Returns '' if unknown."""
    content_type = content_type.split(";")[0].strip().lower()
    return _MIME_TO_EXT.get(content_type, "")
