"""
Configuration module for CCC Backend.
Loads all settings from environment variables with sensible defaults.
"""

import os
from dataclasses import dataclass, field
from typing import List, Optional


@dataclass(frozen=True)
class Settings:
    """Application settings loaded from environment variables."""

    # --- Szurubooru connection ---
    szuru_url: str = os.getenv("SZURU_URL", "http://localhost:8080")
    szuru_username: str = os.getenv("SZURU_USERNAME", "")
    szuru_token: str = os.getenv("SZURU_TOKEN", "")

    # --- Tag categories (Szurubooru: general, artist, copyright, character, meta) ---
    szuru_default_tag_category: str = os.getenv("SZURU_DEFAULT_TAG_CATEGORY", "general")

    # --- Database ---
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://ccc:ccc@localhost:5432/ccc",
    )

    # --- Redis ---
    redis_url: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")

    # --- WD14 Tagger (in-process via wdtagger) ---
    wd14_enabled: bool = os.getenv("WD14_ENABLED", "true").lower() == "true"
    wd14_model: str = os.getenv("WD14_MODEL", "SmilingWolf/wd-swinv2-tagger-v3")
    wd14_confidence_threshold: float = float(os.getenv("WD14_CONFIDENCE_THRESHOLD", "0.35"))
    wd14_max_tags: int = int(os.getenv("WD14_MAX_TAGS", "30"))

    # --- CCC API auth ---
    api_key: str = os.getenv("API_KEY", "")

    # --- Dashboard auth (optional). If both set, API accepts X-API-Key OR Basic auth. ---
    dashboard_user: str = os.getenv("DASHBOARD_USER", "")
    dashboard_password: str = os.getenv("DASHBOARD_PASSWORD", "")

    # --- Worker ---
    job_data_dir: str = os.getenv("JOB_DATA_DIR", "/data/jobs")
    gallery_dl_timeout: int = int(os.getenv("GALLERY_DL_TIMEOUT", "120"))
    # Optional gallery-dl config file; if set, passed as -c to gallery-dl. Else we pass per-extractor options (e.g. extractor.yandere.tags) for known sites.
    gallery_dl_config_file: Optional[str] = os.getenv("GALLERY_DL_CONFIG_FILE")
    # Sankaku (sankaku.app / sankakucomplex.com) login; passed as -o extractor.sankaku.username/password when URL is Sankaku.
    gallery_dl_sankaku_username: Optional[str] = os.getenv("SANKAKU_USERNAME")
    gallery_dl_sankaku_password: Optional[str] = os.getenv("SANKAKU_PASSWORD")
    # Twitter (twitter.com / x.com): Netscape-format cookie content; written to a temp file when invoking gallery-dl for Twitter URLs.
    gallery_dl_twitter_cookies: Optional[str] = os.getenv("TWITTER_COOKIES")
    ytdlp_timeout: int = int(os.getenv("YTDLP_TIMEOUT", "300"))
    max_retries: int = int(os.getenv("MAX_RETRIES", "3"))
    retry_delay: float = float(os.getenv("RETRY_DELAY", "5.0"))

    # --- Server ---
    host: str = os.getenv("HOST", "0.0.0.0")
    port: int = int(os.getenv("PORT", "21425"))
    debug: bool = os.getenv("DEBUG", "false").lower() == "true"
    log_level: str = os.getenv("LOG_LEVEL", "INFO")
    cors_origins: str = os.getenv("CORS_ORIGINS", "*")


def get_settings() -> Settings:
    """Return a singleton-ish settings instance."""
    return Settings()
