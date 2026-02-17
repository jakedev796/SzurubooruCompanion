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


async def verify_api_key(
    request: Request,
    x_api_key: str = Header(default="", alias="X-API-Key"),
) -> str:
    """
    Validate auth: X-API-Key when API_KEY is set.
    If API_KEY is not configured, allow all. Otherwise require API key.
    """
    if settings.api_key and x_api_key == settings.api_key:
        return x_api_key

    if settings.api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key.",
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

    # Try Basic auth (for DB users only)
    if authorization and authorization.startswith("Basic "):
        try:
            raw = base64.b64decode(authorization[6:].encode()).decode()
            username, _, password = raw.partition(":")

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
