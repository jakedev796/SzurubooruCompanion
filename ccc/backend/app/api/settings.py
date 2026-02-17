"""
Global settings endpoints (admin only).
"""

import json
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional, Dict

from app.database import GlobalSetting, User, get_db
from app.api.deps import require_admin, get_current_user
from app.config import get_settings as get_env_settings
from app.services import szurubooru

router = APIRouter()


class GlobalSettingsResponse(BaseModel):
    wd14_enabled: bool
    wd14_model: str
    wd14_confidence_threshold: float
    wd14_max_tags: int
    worker_concurrency: int
    gallery_dl_timeout: int
    ytdlp_timeout: int
    max_retries: int
    retry_delay: float


class GlobalSettingsUpdateRequest(BaseModel):
    wd14_enabled: Optional[bool] = None
    wd14_model: Optional[str] = None
    wd14_confidence_threshold: Optional[float] = None
    wd14_max_tags: Optional[int] = None
    worker_concurrency: Optional[int] = None
    gallery_dl_timeout: Optional[int] = None
    ytdlp_timeout: Optional[int] = None
    max_retries: Optional[int] = None
    retry_delay: Optional[float] = None


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
        wd14_model=config.wd14_model,
        wd14_confidence_threshold=config.wd14_confidence_threshold,
        wd14_max_tags=config.wd14_max_tags,
        worker_concurrency=config.worker_concurrency,
        gallery_dl_timeout=config.gallery_dl_timeout,
        ytdlp_timeout=config.ytdlp_timeout,
        max_retries=config.max_retries,
        retry_delay=config.retry_delay,
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


@router.get("/settings/category-mappings")
async def get_category_mappings(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get global category mappings."""
    result = await db.execute(
        select(GlobalSetting).where(GlobalSetting.key == "szuru_category_mappings")
    )
    setting = result.scalar_one_or_none()

    if setting and setting.value:
        try:
            return {"mappings": json.loads(setting.value)}
        except json.JSONDecodeError:
            return {"mappings": {}}
    return {"mappings": {}}


@router.put("/settings/category-mappings")
async def update_category_mappings(
    body: dict,
    _admin=Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Update global category mappings (admin only).
    Body should be: {"mappings": {"general": "general", "artist": "author", ...}}
    """
    mappings = body.get("mappings", {})

    # Validate mapping keys
    valid_keys = ["general", "artist", "character", "copyright", "meta"]
    for key in mappings.keys():
        if key not in valid_keys:
            return {"error": f"Invalid category key: {key}. Must be one of: {valid_keys}"}

    # Store as JSON
    json_value = json.dumps(mappings)

    result = await db.execute(
        select(GlobalSetting).where(GlobalSetting.key == "szuru_category_mappings")
    )
    setting = result.scalar_one_or_none()

    if setting:
        setting.value = json_value
        setting.value_type = "json"
    else:
        new_setting = GlobalSetting(
            key="szuru_category_mappings",
            value=json_value,
            value_type="json"
        )
        db.add(new_setting)

    await db.commit()
    return {"message": "Category mappings updated", "mappings": mappings}
