"""
Shared MIME type handling.
Ensures consistent type detection across the application, even in minimal Docker images.
"""

import mimetypes

# Initialize and patch the mimetypes database once at import time.
mimetypes.init()

COMMON_MIME_TYPES = {
    # Images
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".gif": "image/gif",
    ".webp": "image/webp",
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


def extension_from_content_type(content_type: str) -> str:
    """Map a Content-Type header value to a file extension (without dot). Returns '' if unknown."""
    content_type = content_type.split(";")[0].strip().lower()
    return _MIME_TO_EXT.get(content_type, "")
