"""
Shared FastAPI dependencies (auth, db session).
"""

import base64
import binascii

from typing import Optional

from fastapi import Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import User, UserRole, get_db
from app.services.auth import verify_password, verify_jwt_token

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


async def get_current_user(
    request: Request,
    authorization: Optional[str] = Header(None),
    x_api_key: str = Header(default="", alias="X-API-Key"),
    db: AsyncSession = Depends(get_db),
) -> User:
    """
    Authenticate user via JWT (preferred) or legacy Basic auth.
    Returns User model or raises 401.
    """
    # Try JWT first (Bearer token)
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
        payload = verify_jwt_token(token)
        if payload:
            user_id = payload.get("user_id")
            if user_id:
                result = await db.execute(select(User).where(User.id == user_id, User.is_active == 1))
                user = result.scalar_one_or_none()
                if user:
                    return user

    # Try legacy Basic auth (for ENV-based DASHBOARD_USER/PASSWORD)
    if authorization and authorization.startswith("Basic "):
        try:
            raw = base64.b64decode(authorization[6:].encode()).decode()
            username, _, password = raw.partition(":")

            # Check against ENV admin user (backward compat during transition)
            if (settings.dashboard_user and settings.dashboard_password and
                username == settings.dashboard_user and password == settings.dashboard_password):
                # Create virtual admin user for transition period
                return User(
                    id=None,
                    username=settings.dashboard_user,
                    password_hash="",
                    role=UserRole.ADMIN,
                    is_active=1,
                )

            # Check against DB users
            result = await db.execute(select(User).where(User.username == username, User.is_active == 1))
            user = result.scalar_one_or_none()
            if user and verify_password(password, user.password_hash):
                return user
        except Exception:
            pass

    # Try API key (grants admin-level access for external clients)
    if settings.api_key and x_api_key == settings.api_key:
        # Create virtual admin user for API key
        return User(
            id=None,
            username="api_key_user",
            password_hash="",
            role=UserRole.ADMIN,
            is_active=1,
        )

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or missing authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Require admin role. Raises 403 if user is not admin."""
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )
    return current_user
