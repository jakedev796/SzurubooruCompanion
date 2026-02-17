"""
Client preferences endpoints for browser extension and mobile app.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Body
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import User, ClientPreference, get_db
from app.api.deps import get_current_user

router = APIRouter()

VALID_CLIENT_TYPES = {"extension-chrome", "extension-firefox", "mobile-android"}


class PreferencesResponse(BaseModel):
    preferences: dict


@router.get("/preferences/{client_type}", response_model=PreferencesResponse)
async def get_preferences(
    client_type: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get client preferences for the current user."""
    if client_type not in VALID_CLIENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid client_type. Must be one of: {VALID_CLIENT_TYPES}",
        )

    result = await db.execute(
        select(ClientPreference).where(
            ClientPreference.user_id == current_user.id,
            ClientPreference.client_type == client_type,
        )
    )
    pref = result.scalar_one_or_none()
    return PreferencesResponse(preferences=pref.preferences if pref else {})


@router.put("/preferences/{client_type}")
async def update_preferences(
    client_type: str,
    preferences: dict = Body(..., embed=True),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update client preferences for the current user."""
    if client_type not in VALID_CLIENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid client_type. Must be one of: {VALID_CLIENT_TYPES}",
        )

    result = await db.execute(
        select(ClientPreference).where(
            ClientPreference.user_id == current_user.id,
            ClientPreference.client_type == client_type,
        )
    )
    pref = result.scalar_one_or_none()

    if pref:
        pref.preferences = preferences
        pref.updated_at = datetime.now(timezone.utc)
    else:
        pref = ClientPreference(
            user_id=current_user.id,
            client_type=client_type,
            preferences=preferences,
        )
        db.add(pref)

    await db.commit()
    return {"status": "ok", "preferences": preferences}


@router.delete("/preferences/{client_type}", status_code=204)
async def delete_preferences(
    client_type: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete client preferences for the current user."""
    if client_type not in VALID_CLIENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid client_type. Must be one of: {VALID_CLIENT_TYPES}",
        )

    result = await db.execute(
        select(ClientPreference).where(
            ClientPreference.user_id == current_user.id,
            ClientPreference.client_type == client_type,
        )
    )
    pref = result.scalar_one_or_none()
    if pref:
        await db.delete(pref)
        await db.commit()
    return None
