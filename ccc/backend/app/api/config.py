"""
Config API endpoint.
Exposes frontend-needed configuration like the Booru URL.
"""

from fastapi import APIRouter

from app.config import get_settings

router = APIRouter()


@router.get("/config")
async def get_config():
    """Return frontend configuration."""
    settings = get_settings()
    return {
        "booru_url": settings.szuru_url,
        "auth_required": bool(settings.dashboard_user and settings.dashboard_password),
    }
