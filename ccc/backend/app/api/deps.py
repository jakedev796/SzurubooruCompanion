"""
Shared FastAPI dependencies (auth, db session).
"""

import base64
import binascii

from typing import Optional

from fastapi import Depends, Header, HTTPException, Request, status

from app.config import get_settings

settings = get_settings()


def _basic_auth_valid(auth_header: Optional[str]) -> bool:
    """Return True if Authorization: Basic matches configured dashboard user/pass."""
    if not settings.dashboard_user or not settings.dashboard_password:
        return False
    if not auth_header or not auth_header.strip().lower().startswith("basic "):
        return False
    try:
        raw = base64.b64decode(auth_header.strip()[6:].encode(), validate=True).decode()
    except (binascii.Error, ValueError, UnicodeDecodeError):
        return False
    if ":" not in raw:
        return False
    user, _, password = raw.partition(":")
    return user == settings.dashboard_user and password == settings.dashboard_password


async def verify_api_key(
    request: Request,
    x_api_key: str = Header(default="", alias="X-API-Key"),
) -> str:
    """
    Validate auth: X-API-Key when API_KEY is set, or Basic when DASHBOARD_USER/PASSWORD set.
    If neither is configured, allow all. Otherwise require one of them.
    """
    auth_header = request.headers.get("authorization")

    if settings.api_key and x_api_key == settings.api_key:
        return x_api_key
    if _basic_auth_valid(auth_header):
        return "basic"

    if settings.api_key or (settings.dashboard_user and settings.dashboard_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key or credentials.",
            headers={"WWW-Authenticate": "Basic realm=\"SzuruCompanion Dashboard\""},
        )
    return ""
