"""
Config API endpoint.
Exposes frontend-needed configuration like the Booru URL.
"""

from fastapi import APIRouter, Depends

from app.api.deps import get_current_user
from app.database import User

router = APIRouter()


@router.get("/config")
async def get_config(
    current_user: User = Depends(get_current_user),
):
    """Return frontend configuration for the authenticated user.

    Returns the user's public Szurubooru URL (or internal URL if public not set).
    """
    # Use public URL if set, otherwise fall back to internal URL
    booru_url = current_user.szuru_public_url or current_user.szuru_url

    return {
        "booru_url": booru_url,
    }
