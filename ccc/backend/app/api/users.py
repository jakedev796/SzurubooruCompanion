"""
User management endpoints (admin only) and user config endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select, delete
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from uuid import UUID

from app.database import User, UserRole, SiteCredential, get_db
from app.api.deps import require_admin, get_current_user
from app.services.auth import hash_password, verify_password
from app.services.config import invalidate_user_config_cache
from app.services.encryption import encrypt, decrypt

router = APIRouter()


# ============================================================================
# Request/Response Models
# ============================================================================

class UserCreateRequest(BaseModel):
    username: str
    password: str
    role: str = "user"


class UserUpdateRequest(BaseModel):
    password: Optional[str] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None


class UserResponse(BaseModel):
    id: str
    username: str
    role: str
    is_active: bool
    szuru_url: Optional[str]
    szuru_public_url: Optional[str]
    szuru_username: Optional[str]
    szuru_category_mappings: Optional[dict]
    created_at: str
    updated_at: str


class UserConfigRequest(BaseModel):
    szuru_url: Optional[str] = None
    szuru_public_url: Optional[str] = None
    szuru_username: Optional[str] = None
    szuru_token: Optional[str] = None
    szuru_category_mappings: Optional[dict] = None
    site_credentials: Optional[dict] = None  # {site_name: {key: value}}


# ============================================================================
# Admin-only User Management Endpoints
# ============================================================================

@router.get("/users", response_model=List[UserResponse])
async def list_users(
    _admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """List all users (admin only)."""
    result = await db.execute(select(User).order_by(User.created_at))
    users = result.scalars().all()

    return [
        UserResponse(
            id=str(u.id),
            username=u.username,
            role=u.role.value,
            is_active=bool(u.is_active),
            szuru_url=u.szuru_url,
            szuru_public_url=u.szuru_public_url,
            szuru_username=u.szuru_username,
            szuru_category_mappings=u.szuru_category_mappings or {},
            created_at=u.created_at.isoformat(),
            updated_at=u.updated_at.isoformat(),
        )
        for u in users
    ]


@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(
    body: UserCreateRequest,
    _admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Create a new user (admin only)."""
    # Check if username exists
    result = await db.execute(select(User).where(User.username == body.username))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Username already exists")

    # Validate role
    if body.role not in ("admin", "user"):
        raise HTTPException(status_code=400, detail="Invalid role")

    user = User(
        username=body.username,
        password_hash=hash_password(body.password),
        role=UserRole.ADMIN if body.role == "admin" else UserRole.USER,
        is_active=1,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

    return UserResponse(
        id=str(user.id),
        username=user.username,
        role=user.role.value,
        is_active=bool(user.is_active),
        szuru_url=user.szuru_url,
        szuru_public_url=user.szuru_public_url,
        szuru_username=user.szuru_username,
        szuru_category_mappings=user.szuru_category_mappings or {},
        created_at=user.created_at.isoformat(),
        updated_at=user.updated_at.isoformat(),
    )


@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: UUID,
    _admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Get user details (admin only)."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return UserResponse(
        id=str(user.id),
        username=user.username,
        role=user.role.value,
        is_active=bool(user.is_active),
        szuru_url=user.szuru_url,
        szuru_public_url=user.szuru_public_url,
        szuru_username=user.szuru_username,
        szuru_category_mappings=user.szuru_category_mappings or {},
        created_at=user.created_at.isoformat(),
        updated_at=user.updated_at.isoformat(),
    )


@router.put("/users/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: UUID,
    body: UserUpdateRequest,
    _admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Update user (admin only)."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if body.password:
        user.password_hash = hash_password(body.password)
    if body.role:
        if body.role not in ("admin", "user"):
            raise HTTPException(status_code=400, detail="Invalid role")
        user.role = UserRole.ADMIN if body.role == "admin" else UserRole.USER
    if body.is_active is not None:
        user.is_active = 1 if body.is_active else 0

    await db.commit()
    await db.refresh(user)

    return UserResponse(
        id=str(user.id),
        username=user.username,
        role=user.role.value,
        is_active=bool(user.is_active),
        szuru_url=user.szuru_url,
        szuru_public_url=user.szuru_public_url,
        szuru_username=user.szuru_username,
        szuru_category_mappings=user.szuru_category_mappings or {},
        created_at=user.created_at.isoformat(),
        updated_at=user.updated_at.isoformat(),
    )


@router.post("/users/{user_id}/deactivate")
async def deactivate_user(
    user_id: UUID,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Deactivate user (admin only). Does not delete data."""
    if admin.id and str(admin.id) == str(user_id):
        raise HTTPException(status_code=400, detail="Cannot deactivate yourself")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.is_active = 0
    await db.commit()

    return {"message": f"User {user.username} deactivated"}


@router.post("/users/{user_id}/activate")
async def activate_user(
    user_id: UUID,
    _admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Activate user (admin only)."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.is_active = 1
    await db.commit()

    return {"message": f"User {user.username} activated"}


@router.post("/users/{user_id}/reset-password")
async def reset_user_password(
    user_id: UUID,
    body: dict,
    _admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Reset user password (admin only)."""
    new_password = body.get("password", "").strip()
    if not new_password or len(new_password) < 4:
        raise HTTPException(status_code=400, detail="Password must be at least 4 characters")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.password_hash = hash_password(new_password)
    await db.commit()

    return {"message": f"Password reset for user {user.username}"}


@router.post("/users/{user_id}/promote-admin")
async def promote_user_to_admin(
    user_id: UUID,
    _admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Promote user to admin (admin only)."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.role = UserRole.ADMIN
    await db.commit()

    return {"message": f"User {user.username} promoted to admin"}


@router.post("/users/{user_id}/demote-admin")
async def demote_user_from_admin(
    user_id: UUID,
    _admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """Demote admin to regular user (admin only)."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.role = UserRole.USER
    await db.commit()

    return {"message": f"User {user.username} demoted to regular user"}


@router.post("/users/me/change-password")
async def change_my_password(
    body: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Change current user's password."""
    if not current_user.id:
        raise HTTPException(status_code=400, detail="Legacy user - cannot change password")

    if not current_user.password_hash:
        raise HTTPException(status_code=400, detail="User has no password set")

    old_password = body.get("old_password", "").strip()
    new_password = body.get("new_password", "").strip()

    if not old_password or not new_password:
        raise HTTPException(status_code=400, detail="Both old and new passwords required")

    if len(new_password) < 4:
        raise HTTPException(status_code=400, detail="New password must be at least 4 characters")

    # Verify old password
    if not verify_password(old_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Incorrect current password")

    # Update password
    current_user.password_hash = hash_password(new_password)
    await db.commit()

    return {"message": "Password changed successfully"}


# ============================================================================
# User Config Endpoints (for current user)
# ============================================================================

@router.get("/users/me/config")
async def get_my_config(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get current user's configuration."""
    if not current_user.id:
        # Legacy user (ENV-based)
        raise HTTPException(status_code=400, detail="Legacy user - no config available")

    # Load site credentials
    creds_result = await db.execute(
        select(SiteCredential).where(SiteCredential.user_id == current_user.id)
    )
    site_creds_raw = creds_result.scalars().all()

    site_credentials = {}
    for cred in site_creds_raw:
        if cred.site_name not in site_credentials:
            site_credentials[cred.site_name] = {}
        site_credentials[cred.site_name][cred.credential_key] = decrypt(cred.credential_value_encrypted)

    # Decrypt szuru token
    szuru_token_decrypted = None
    if current_user.szuru_token_encrypted:
        szuru_token_decrypted = decrypt(current_user.szuru_token_encrypted)

    return {
        "szuru_url": current_user.szuru_url,
        "szuru_public_url": current_user.szuru_public_url,
        "szuru_username": current_user.szuru_username,
        "szuru_token": szuru_token_decrypted,
        "szuru_category_mappings": current_user.szuru_category_mappings or {},
        "site_credentials": site_credentials,
    }


@router.get("/users/me/onboarding-status")
async def get_onboarding_status(
    current_user: User = Depends(get_current_user),
):
    """Check whether the current user has completed onboarding configuration."""
    szuru_configured = bool(
        current_user.szuru_url
        and current_user.szuru_token_encrypted
    )
    categories_mapped = bool(current_user.szuru_category_mappings)

    return {
        "szuru_configured": szuru_configured,
        "categories_mapped": categories_mapped,
        "onboarding_complete": szuru_configured,
    }


@router.put("/users/me/config")
async def update_my_config(
    body: UserConfigRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update current user's configuration."""
    if not current_user.id:
        raise HTTPException(status_code=400, detail="Legacy user - cannot update config")

    # Update Szurubooru settings
    if body.szuru_url is not None:
        current_user.szuru_url = body.szuru_url
    if body.szuru_public_url is not None:
        current_user.szuru_public_url = body.szuru_public_url
    if body.szuru_username is not None:
        current_user.szuru_username = body.szuru_username
    if body.szuru_token is not None:
        current_user.szuru_token_encrypted = encrypt(body.szuru_token) if body.szuru_token else None
    if body.szuru_category_mappings is not None:
        current_user.szuru_category_mappings = body.szuru_category_mappings

    await db.commit()

    # Update site credentials
    if body.site_credentials:
        for site_name, creds in body.site_credentials.items():
            for key, value in creds.items():
                # Upsert credential
                result = await db.execute(
                    select(SiteCredential).where(
                        SiteCredential.user_id == current_user.id,
                        SiteCredential.site_name == site_name,
                        SiteCredential.credential_key == key,
                    )
                )
                existing = result.scalar_one_or_none()

                if existing:
                    existing.credential_value_encrypted = encrypt(value)
                else:
                    new_cred = SiteCredential(
                        user_id=current_user.id,
                        site_name=site_name,
                        credential_key=key,
                        credential_value_encrypted=encrypt(value),
                    )
                    db.add(new_cred)

        await db.commit()

    await invalidate_user_config_cache(str(current_user.id))
    return {"message": "Configuration updated"}
