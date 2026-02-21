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

    # --- Encryption key (required for credential encryption/decryption) ---
    encryption_key: str = os.getenv("ENCRYPTION_KEY", "")

    # --- WD14 Tagger (ENV-based, requires restart to change) ---
    # wd14_enabled, wd14_confidence_threshold, wd14_max_tags are live settings managed via
    # Settings > Global Settings in the dashboard (GlobalConfig). Only model/pool/threads
    # require a restart and are therefore ENV-only.
    wd14_model: str = os.getenv("WD14_MODEL", "SmilingWolf/wd-swinv2-tagger-v3")
    # Thread pool size for GPU/multi-worker inference (ignored when process pool is active)
    wd14_num_workers: int = int(os.getenv("WD14_NUM_WORKERS", "4"))
    # Use a subprocess for CPU inference to bypass the GIL (only beneficial with a single worker;
    # disable when worker_concurrency > 1 so all workers share the thread pool concurrently)
    wd14_use_process_pool: bool = os.getenv("WD14_USE_PROCESS_POOL", "false").lower() == "true"

    # --- Worker & Paths ---
    # worker_concurrency requires a restart (workers are spawned at startup), so it lives in ENV.
    worker_concurrency: int = int(os.getenv("WORKER_CONCURRENCY", "1"))
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
