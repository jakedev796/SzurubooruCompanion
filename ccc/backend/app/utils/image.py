"""
Image utilities: format conversion for sites/Szurubooru instances that don't
accept newer image containers.
"""

import logging
from pathlib import Path

from PIL import Image, features
from pillow_heif import register_heif_opener

register_heif_opener()

logger = logging.getLogger(__name__)

HEIF_EXTENSIONS = {".heic", ".heif"}
AVIF_EXTENSIONS = {".avif", ".avifs"}


def is_heif_path(path: str | Path) -> bool:
    return Path(path).suffix.lower() in HEIF_EXTENSIONS


def is_avif_path(path: str | Path) -> bool:
    return Path(path).suffix.lower() in AVIF_EXTENSIONS


def avif_supported() -> bool:
    """
    Whether the installed Pillow can decode AVIF.

    Pillow ships AVIF support in its wheels from 11.3.0 onwards; older builds
    can read neither AVIF nor convert it, so callers must degrade instead.
    """
    return bool(features.check("avif"))


def convert_to_jpeg(path: Path, *, quality: int = 92) -> Path:
    """
    Convert an image to JPEG in-place (same directory, new extension).
    Returns the path to the new JPEG. The original file is removed on success.

    Raises on conversion failure; callers should catch and handle.
    """
    src = Path(path)
    dst = src.with_suffix(".jpg")

    with Image.open(src) as img:
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
        img.save(dst, format="JPEG", quality=quality, optimize=True)

    try:
        src.unlink()
    except OSError as e:
        logger.warning("Could not remove source file %s after conversion: %s", src, e)

    logger.info("Converted %s -> %s", src.name, dst.name)
    return dst
