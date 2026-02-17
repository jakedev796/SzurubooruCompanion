"""
Configuration module for CCC Backend.
Loads settings from environment variables as defined in .env.example.
All user-specific configuration (Szurubooru credentials, site credentials, etc.) 
is stored in the database and loaded via app.services.config.
"""

import os
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class Settings:
    """Application settings loaded from environment variables."""

    # --- Database ---
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://ccc:ccc@localhost:5432/ccc",
    )

    # --- Redis ---
    redis_url: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")

    # --- Legacy API key (unused; clients use JWT login) ---
    api_key: str = os.getenv("API_KEY", "")

    # --- WD14 Tagger (ENV-based, requires restart to change) ---
    wd14_enabled: bool = os.getenv("WD14_ENABLED", "true").lower() == "true"
    wd14_model: str = os.getenv("WD14_MODEL", "SmilingWolf/wd-swinv2-tagger-v3")
    wd14_confidence_threshold: float = float(os.getenv("WD14_CONFIDENCE_THRESHOLD", "0.35"))
    wd14_max_tags: int = int(os.getenv("WD14_MAX_TAGS", "30"))

    # --- Worker & Paths ---
    job_data_dir: str = os.getenv("JOB_DATA_DIR", "/data/jobs")

    # --- Gallery-DL ---
    gallery_dl_config_file: Optional[str] = os.getenv("GALLERY_DL_CONFIG_FILE")

    # --- Server ---
    host: str = os.getenv("HOST", "0.0.0.0")
    port: int = int(os.getenv("PORT", "21425"))
    debug: bool = os.getenv("DEBUG", "false").lower() == "true"
    log_level: str = os.getenv("LOG_LEVEL", "INFO")
    cors_origins: str = os.getenv("CORS_ORIGINS", "*")


def get_settings() -> Settings:
    """Return a singleton-ish settings instance."""
    return Settings()
