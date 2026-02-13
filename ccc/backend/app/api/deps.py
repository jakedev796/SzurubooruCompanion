"""
Shared FastAPI dependencies (auth, db session).
"""

from fastapi import Depends, Header, HTTPException, status

from app.config import get_settings

settings = get_settings()


async def verify_api_key(x_api_key: str = Header(default="")) -> str:
    """Validate the X-API-Key header when API_KEY is configured."""
    if not settings.api_key:
        # No key configured – allow all requests.
        return ""
    if x_api_key != settings.api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key.",
        )
    return x_api_key
