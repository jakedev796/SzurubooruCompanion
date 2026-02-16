"""
Config API endpoint.
Exposes frontend-needed configuration like the Booru URL.
"""

from fastapi import APIRouter, Header, Request

from app.api.deps import verify_api_key
from app.config import get_settings, get_szuru_users

router = APIRouter()


@router.get("/config")
async def get_config(
    request: Request,
    x_api_key: str = Header(default="", alias="X-API-Key"),
):
    """Return frontend configuration.

    Public fields (booru_url, auth_required) are always returned.
    szuru_users is only included for authenticated requests.
    """
    settings = get_settings()
    result: dict = {
        "booru_url": settings.szuru_public_url or settings.szuru_url,
        "auth_required": bool(settings.dashboard_user and settings.dashboard_password),
    }

    # Only expose the user list to authenticated callers.
    try:
        await verify_api_key(request, x_api_key)
        users = get_szuru_users()
        result["szuru_users"] = [u for u, _t in users]
    except Exception:
        pass

    return result
