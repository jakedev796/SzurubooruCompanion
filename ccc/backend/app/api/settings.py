"""
Global settings endpoints (admin only).
"""

import json
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional, Dict, List

from app.database import GlobalSetting, User, get_db
from app.api.deps import require_admin, get_current_user
from app.config import get_settings as get_env_settings
from app.services import szurubooru
from app.sites.registry import get_all_handlers
from app.sites.site_info import SITE_DISPLAY_INFO, DOWNLOAD_NA, TAG_EXTRACTION_NA

router = APIRouter()


class SupportedSiteOut(BaseModel):
    name: str
    url: str
    auth_required: bool
    notes: str
    download_supported: str  # "yes" | "no" | "na"
    tag_extraction_supported: str  # "yes" | "no" | "na"
    config_needed: str  # "required" | "optional" | "none"


class GlobalSettingsResponse(BaseModel):
    wd14_enabled: bool
    wd14_confidence_threshold: float
    wd14_max_tags: int
    gallery_dl_timeout: int
    ytdlp_timeout: int
    max_retries: int
    retry_delay: float
    video_tagging_enabled: bool
    video_scene_threshold: float
    video_max_frames: int
    video_tag_min_frame_ratio: float
    video_confidence_threshold: float


class GlobalSettingsUpdateRequest(BaseModel):
    wd14_enabled: Optional[bool] = None
    wd14_confidence_threshold: Optional[float] = None
    wd14_max_tags: Optional[int] = None
    gallery_dl_timeout: Optional[int] = None
    ytdlp_timeout: Optional[int] = None
    max_retries: Optional[int] = None
    retry_delay: Optional[float] = None
    video_tagging_enabled: Optional[bool] = None
    video_scene_threshold: Optional[float] = None
    video_max_frames: Optional[int] = None
    video_tag_min_frame_ratio: Optional[float] = None
    video_confidence_threshold: Optional[float] = None


@router.get("/settings/global", response_model=GlobalSettingsResponse)
async def get_global_settings(
    _admin=Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Get global settings (admin only)."""
    from app.services.config import load_global_config

    config = await load_global_config(db)

    return GlobalSettingsResponse(
        wd14_enabled=config.wd14_enabled,
        wd14_confidence_threshold=config.wd14_confidence_threshold,
        wd14_max_tags=config.wd14_max_tags,
        gallery_dl_timeout=config.gallery_dl_timeout,
        ytdlp_timeout=config.ytdlp_timeout,
        max_retries=config.max_retries,
        retry_delay=config.retry_delay,
        video_tagging_enabled=config.video_tagging_enabled,
        video_scene_threshold=config.video_scene_threshold,
        video_max_frames=config.video_max_frames,
        video_tag_min_frame_ratio=config.video_tag_min_frame_ratio,
        video_confidence_threshold=config.video_confidence_threshold,
    )


@router.put("/settings/global")
async def update_global_settings(
    body: GlobalSettingsUpdateRequest,
    _admin=Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Update global settings (admin only)."""
    updates = body.dict(exclude_unset=True)

    for key, value in updates.items():
        # Determine value type
        if isinstance(value, bool):
            value_type = "bool"
            value_str = str(value).lower()
        elif isinstance(value, int):
            value_type = "int"
            value_str = str(value)
        elif isinstance(value, float):
            value_type = "float"
            value_str = str(value)
        else:
            value_type = "string"
            value_str = str(value)

        # Upsert setting
        result = await db.execute(select(GlobalSetting).where(GlobalSetting.key == key))
        setting = result.scalar_one_or_none()

        if setting:
            setting.value = value_str
            setting.value_type = value_type
        else:
            new_setting = GlobalSetting(key=key, value=value_str, value_type=value_type)
            db.add(new_setting)

    await db.commit()
    return {"message": "Global settings updated"}


@router.get("/settings/api-key")
async def get_api_key(_admin=Depends(require_admin)):
    """Get API key from ENV (admin only)."""
    env = get_env_settings()
    return {"api_key": env.api_key or "(not set)"}


@router.post("/settings/szuru-categories")
async def fetch_szuru_categories(
    body: dict,
    current_user: User = Depends(get_current_user),
):
    """
    Fetch tag categories from a Szurubooru instance.
    Requires szuru_url, szuru_username, and szuru_token in request body.
    Returns list of categories or error.
    """
    szuru_url = body.get("szuru_url", "").strip()
    szuru_username = body.get("szuru_username", "").strip()
    szuru_token = body.get("szuru_token", "").strip()

    if not szuru_url or not szuru_username or not szuru_token:
        return {"error": "Missing required fields: szuru_url, szuru_username, szuru_token"}

    result = await szurubooru.fetch_tag_categories(szuru_url, szuru_username, szuru_token)
    return result


@router.get("/settings/supported-sites", response_model=List[SupportedSiteOut])
async def get_supported_sites(
    current_user: User = Depends(get_current_user),
):
    """List curated supported sites (only those in SITE_DISPLAY_INFO). Add sites there as they are tested."""
    handlers = get_all_handlers()
    out = []
    for h in handlers:
        if h.name not in SITE_DISPLAY_INFO:
            continue
        info = SITE_DISPLAY_INFO[h.name]
        auth = bool(h.credentials) or (h.name == "twitter")

        download_supported = info.get("download_supported")
        if download_supported is None:
            download_supported = "na" if h.name in DOWNLOAD_NA else "yes"

        tag_extraction_supported = info.get("tag_extraction_supported")
        if tag_extraction_supported is None:
            if h.name in TAG_EXTRACTION_NA:
                tag_extraction_supported = "na"
            elif h.gallery_dl_tag_options:
                tag_extraction_supported = "yes"
            else:
                tag_extraction_supported = "no"

        config_needed = info.get("config", "none")

        out.append(
            SupportedSiteOut(
                name=h.name,
                url=info.get("url", ""),
                auth_required=auth,
                notes=info.get("notes", ""),
                download_supported=download_supported,
                tag_extraction_supported=tag_extraction_supported,
                config_needed=config_needed,
            )
        )
    out.sort(key=lambda x: x.name.lower())
    return out


@router.get("/settings/category-mappings")
async def get_category_mappings(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get user's category mappings (per-user, not global)."""
    return {"mappings": current_user.szuru_category_mappings or {}}


@router.put("/settings/category-mappings")
async def update_category_mappings(
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Update user's category mappings (per-user, any authenticated user can update their own).
    Body should be: {"mappings": {"general": "general", "artist": "author", ...}}
    """
    mappings = body.get("mappings", {})

    # Validate mapping keys
    valid_keys = ["general", "artist", "character", "copyright", "meta"]
    for key in mappings.keys():
        if key not in valid_keys:
            return {"error": f"Invalid category key: {key}. Must be one of: {valid_keys}"}

    # Store in user's settings
    current_user.szuru_category_mappings = mappings
    await db.commit()

    return {"message": "Category mappings updated", "mappings": mappings}
