"""
Configuration service for loading user-specific and global settings from database.
All configuration is database-driven - ENV is only used for bootstrap (admin user, encryption key).
"""

from typing import Dict, Optional
from dataclasses import dataclass
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
import logging

from app.database import User, SiteCredential, GlobalSetting
from app.services.encryption import decrypt
from app.config import get_settings as get_env_settings

logger = logging.getLogger(__name__)


@dataclass
class UserConfig:
    """User-specific configuration loaded from database."""
    user_id: str
    username: str
    szuru_url: Optional[str]
    szuru_username: Optional[str]
    szuru_token: Optional[str]
    site_credentials: Dict[str, Dict[str, str]]  # {site_name: {credential_key: value}}


@dataclass
class GlobalConfig:
    """Global system settings loaded from database."""
    wd14_enabled: bool
    wd14_model: str
    wd14_confidence_threshold: float
    wd14_max_tags: int
    worker_concurrency: int
    gallery_dl_timeout: int
    ytdlp_timeout: int
    max_retries: int
    retry_delay: float


async def load_user_config(db: AsyncSession, user_id: str) -> Optional[UserConfig]:
    """
    Load user-specific configuration from database.
    Returns None if user not found.
    All credentials are decrypted from database.
    """
    # Load user
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        logger.error("User %s not found in database", user_id)
        return None

    # Decrypt Szurubooru token
    szuru_token = None
    if user.szuru_token_encrypted:
        try:
            szuru_token = decrypt(user.szuru_token_encrypted)
        except Exception as e:
            logger.error("Failed to decrypt szuru token for user %s: %s", user.username, e)

    # Load site credentials
    creds_result = await db.execute(
        select(SiteCredential).where(SiteCredential.user_id == user_id)
    )
    site_creds_raw = creds_result.scalars().all()

    site_credentials: Dict[str, Dict[str, str]] = {}
    for cred in site_creds_raw:
        if cred.site_name not in site_credentials:
            site_credentials[cred.site_name] = {}

        try:
            decrypted_value = decrypt(cred.credential_value_encrypted)
            site_credentials[cred.site_name][cred.credential_key] = decrypted_value
        except Exception as e:
            logger.error(
                "Failed to decrypt %s.%s for user %s: %s",
                cred.site_name,
                cred.credential_key,
                user.username,
                e
            )

    return UserConfig(
        user_id=str(user.id),
        username=user.username,
        szuru_url=user.szuru_url,
        szuru_username=user.szuru_username,
        szuru_token=szuru_token,
        site_credentials=site_credentials,
    )


async def load_global_config(db: AsyncSession) -> GlobalConfig:
    """
    Load global configuration from database.
    Falls back to sensible defaults if settings not in database.
    All settings are configurable via Settings > Global Settings in dashboard.
    """
    # Sensible defaults (used when DB is empty - first startup)
    DEFAULTS = {
        "wd14_enabled": True,
        "wd14_model": "SmilingWolf/wd-swinv2-tagger-v3",
        "wd14_confidence_threshold": 0.35,
        "wd14_max_tags": 30,
        "worker_concurrency": 1,
        "gallery_dl_timeout": 120,
        "ytdlp_timeout": 300,
        "max_retries": 3,
        "retry_delay": 5.0,
    }

    result = await db.execute(select(GlobalSetting))
    settings_raw = {s.key: (s.value, s.value_type) for s in result.scalars().all()}

    def get_setting(key: str, default, value_type: str):
        """Get setting from DB, fallback to default."""
        if key in settings_raw:
            raw_val, typ = settings_raw[key]
            try:
                if typ == "int":
                    return int(raw_val)
                elif typ == "float":
                    return float(raw_val)
                elif typ == "bool":
                    return raw_val.lower() in ("true", "1", "yes")
                return raw_val
            except (ValueError, AttributeError) as e:
                logger.warning("Invalid value for setting %s: %s, using default", key, e)
                return default
        return default

    return GlobalConfig(
        wd14_enabled=get_setting("wd14_enabled", DEFAULTS["wd14_enabled"], "bool"),
        wd14_model=get_setting("wd14_model", DEFAULTS["wd14_model"], "string"),
        wd14_confidence_threshold=get_setting("wd14_confidence_threshold", DEFAULTS["wd14_confidence_threshold"], "float"),
        wd14_max_tags=get_setting("wd14_max_tags", DEFAULTS["wd14_max_tags"], "int"),
        worker_concurrency=get_setting("worker_concurrency", DEFAULTS["worker_concurrency"], "int"),
        gallery_dl_timeout=get_setting("gallery_dl_timeout", DEFAULTS["gallery_dl_timeout"], "int"),
        ytdlp_timeout=get_setting("ytdlp_timeout", DEFAULTS["ytdlp_timeout"], "int"),
        max_retries=get_setting("max_retries", DEFAULTS["max_retries"], "int"),
        retry_delay=get_setting("retry_delay", DEFAULTS["retry_delay"], "float"),
    )
