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

    # --- Tag categories: match your Szurubooru's category names ---
    szuru_default_tag_category: str = os.getenv("SZURU_DEFAULT_TAG_CATEGORY", "general")
    # Your instance's category name for each slot; source names (author, circle, etc.) are mapped in code.
    szuru_category_general: str = os.getenv("SZURU_CATEGORY_GENERAL", "general")
    szuru_category_artist: str = os.getenv("SZURU_CATEGORY_ARTIST", "artist")
    szuru_category_character: str = os.getenv("SZURU_CATEGORY_CHARACTER", "character")
    szuru_category_copyright: str = os.getenv("SZURU_CATEGORY_COPYRIGHT", "copyright")
    szuru_category_meta: str = os.getenv("SZURU_CATEGORY_META", "meta")

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
    # CPU: run tag() in a subprocess to avoid GIL so PyTorch can use all cores. Set false to use thread pool.
    wd14_use_process_pool: bool = os.getenv("WD14_USE_PROCESS_POOL", "true").lower() == "true"
    # Thread pool size when not using process pool; also caps parallel tag() when batching.
    wd14_num_workers: int = max(1, int(os.getenv("WD14_NUM_WORKERS", "4")))

    # --- CCC API auth ---
    api_key: str = os.getenv("API_KEY", "")

    # --- Dashboard auth (optional). If both set, API accepts X-API-Key OR Basic auth. ---
    dashboard_user: str = os.getenv("DASHBOARD_USER", "")
    dashboard_password: str = os.getenv("DASHBOARD_PASSWORD", "")

    # --- Worker ---
    job_data_dir: str = os.getenv("JOB_DATA_DIR", "/data/jobs")
    gallery_dl_timeout: int = int(os.getenv("GALLERY_DL_TIMEOUT", "120"))
    # Optional gallery-dl config file; if set, passed as -c to gallery-dl. Else we pass per-extractor options for known sites.
    gallery_dl_config_file: Optional[str] = os.getenv("GALLERY_DL_CONFIG_FILE")
    # Twitter (twitter.com / x.com): cookies written to temp file and passed when URL is Twitter. Username/password used by config file.
    gallery_dl_twitter_username: Optional[str] = os.getenv("TWITTER_USERNAME")
    gallery_dl_twitter_password: Optional[str] = os.getenv("TWITTER_PASSWORD")
    gallery_dl_twitter_cookies: Optional[str] = os.getenv("TWITTER_COOKIES")
    # Misskey: used by config file or for future -o injection when URL is Misskey.
    gallery_dl_misskey_username: Optional[str] = os.getenv("MISSKEY_USERNAME")
    gallery_dl_misskey_password: Optional[str] = os.getenv("MISSKEY_PASSWORD")
    # Sankaku (sankaku.app / sankakucomplex.com): passed as -o extractor.sankaku.username/password when URL is Sankaku.
    gallery_dl_sankaku_username: Optional[str] = os.getenv("SANKAKU_USERNAME")
    gallery_dl_sankaku_password: Optional[str] = os.getenv("SANKAKU_PASSWORD")
    # Danbooru: used by config file or for future -o injection.
    gallery_dl_danbooru_api_key: Optional[str] = os.getenv("DANBOORU_API_KEY")
    gallery_dl_danbooru_user_id: Optional[str] = os.getenv("DANBOORU_USER_ID")
    # Gelbooru: used by config file or for future -o injection.
    gallery_dl_gelbooru_api_key: Optional[str] = os.getenv("GELBOORU_API_KEY")
    gallery_dl_gelbooru_user_id: Optional[str] = os.getenv("GELBOORU_USER_ID")
    # Rule34.xxx: passed as -o extractor.rule34.api-key / user-id when URL is rule34.
    gallery_dl_rule34_api_key: Optional[str] = os.getenv("RULE34_API_KEY")
    gallery_dl_rule34_user_id: Optional[str] = os.getenv("RULE34_USER_ID")
    # Reddit: used by config file or for future -o injection.
    gallery_dl_reddit_client_id: Optional[str] = os.getenv("REDDIT_CLIENT_ID")
    gallery_dl_reddit_client_secret: Optional[str] = os.getenv("REDDIT_CLIENT_SECRET")
    gallery_dl_reddit_username: Optional[str] = os.getenv("REDDIT_USERNAME")
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
