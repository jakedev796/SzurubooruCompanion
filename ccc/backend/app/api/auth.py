"""
Authentication endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, status, Body
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import User, get_db
from app.services.auth import verify_password, create_jwt_token, create_refresh_token, verify_refresh_token
from app.api.deps import get_current_user

router = APIRouter()


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: dict


class UserMeResponse(BaseModel):
    id: str
    username: str
    role: str


@router.post("/auth/login", response_model=LoginResponse)
async def login(
    body: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """Login with username/password, returns JWT token."""
    result = await db.execute(
        select(User).where(User.username == body.username, User.is_active == 1)
    )
    user = result.scalar_one_or_none()

    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password",
        )

    access_token = create_jwt_token(str(user.id), user.username, user.role.value)
    refresh_token = create_refresh_token(str(user.id), user.username)

    return LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user={
            "id": str(user.id),
            "username": user.username,
            "role": user.role.value,
        },
    )


@router.post("/auth/refresh")
async def refresh_token(
    refresh_token: str = Body(..., embed=True),
    db: AsyncSession = Depends(get_db),
):
    """Exchange refresh token for new access token."""
    payload = verify_refresh_token(refresh_token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    # Verify user still exists and is active
    user_id = payload.get("user_id")
    result = await db.execute(
        select(User).where(User.id == user_id, User.is_active == 1)
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
        )

    new_access_token = create_jwt_token(str(user.id), user.username, user.role.value)
    return {"access_token": new_access_token, "token_type": "bearer"}


@router.get("/auth/me", response_model=UserMeResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    """Get current user info from JWT token."""
    return UserMeResponse(
        id=str(current_user.id) if current_user.id else "legacy",
        username=current_user.username,
        role=current_user.role.value,
    )
