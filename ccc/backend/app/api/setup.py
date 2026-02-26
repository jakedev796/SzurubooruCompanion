"""
Setup endpoints for initial onboarding (first admin creation).
These endpoints are public — no authentication required.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, field_validator
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import User, UserRole, get_db
from app.services.auth import hash_password, create_jwt_token, create_refresh_token
from app.sites.registry import get_all_handlers

logger = logging.getLogger(__name__)

router = APIRouter()


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------


class SiteInfo(BaseModel):
    name: str
    fields: list[str]


class SetupStatusResponse(BaseModel):
    needs_setup: bool


class CreateAdminRequest(BaseModel):
    username: str
    password: str

    @field_validator("username")
    @classmethod
    def username_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Username must not be empty")
        return v.strip()

    @field_validator("password")
    @classmethod
    def password_min_length(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        return v


class CreateAdminResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: dict


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/setup/status", response_model=SetupStatusResponse)
async def get_setup_status(db: AsyncSession = Depends(get_db)):
    """Check if initial setup is needed. Public endpoint — no auth required."""
    result = await db.execute(select(func.count()).select_from(User))
    user_count = result.scalar_one()
    return SetupStatusResponse(needs_setup=user_count == 0)


@router.post("/setup/admin", response_model=CreateAdminResponse, status_code=201)
async def create_admin(
    body: CreateAdminRequest,
    db: AsyncSession = Depends(get_db),
):
    """Create the first admin account. Only works when zero users exist."""
    result = await db.execute(select(func.count()).select_from(User))
    user_count = result.scalar_one()

    if user_count > 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Setup already completed — an admin account already exists",
        )

    user = User(
        username=body.username,
        password_hash=hash_password(body.password),
        role=UserRole.ADMIN,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    logger.info("Setup: created admin user '%s'", user.username)

    access_token = create_jwt_token(str(user.id), user.username, user.role.value)
    refresh_token = create_refresh_token(str(user.id), user.username)

    return CreateAdminResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user={
            "id": str(user.id),
            "username": user.username,
            "role": user.role.value,
        },
    )


@router.get("/setup/sites", response_model=list[SiteInfo])
async def list_supported_sites():
    """List all supported sites and their credential fields. Public endpoint."""
    handlers = get_all_handlers()
    sites = []
    for handler in handlers:
        fields = [spec.gallery_dl_key for spec in handler.credentials]
        # Twitter uses cookies stored as site credential but not via CredentialSpec
        if handler.name == "twitter" and "cookies" not in fields:
            fields.append("cookies")
        if fields:
            sites.append(SiteInfo(name=handler.name, fields=fields))
    return sites
