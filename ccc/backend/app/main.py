"""
CCC Backend – FastAPI entry point.
Starts the API server and the background job worker.
"""

import asyncio
import logging
from typing import Optional

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.config import get_settings
from app.database import init_db
from app.migrations import run_migrations
from app.api.jobs import router as jobs_router
from app.api.stats import router as stats_router
from app.api.health import router as health_router
from app.api.events import router as events_router
from app.api.config import router as config_router
from app.api.auth import router as auth_router
from app.api.setup import router as setup_router
from app.api.users import router as users_router
from app.api.settings import router as settings_router
from app.api.preferences import router as preferences_router
from app.api.swiper import router as swiper_router
from app.api.tag_jobs import router as tag_jobs_router
from app.services.szurubooru import (
    init_session as init_szuru_session,
    close_session as close_szuru_session,
    load_tag_cache,
)
from app.workers.processor import start_worker, stop_worker

settings = get_settings()

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("ccc")

# Reduce console noise: uvicorn access log and third-party libs
logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
for name in ("httpx", "httpcore", "huggingface_hub", "timm", "timm.models._hub", "wdtagger"):
    logging.getLogger(name).setLevel(logging.WARNING)


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup / shutdown lifecycle."""
    logger.info("Initializing database...")
    await init_db()
    await run_migrations()
    logger.info("Database ready.")

    logger.info("Initializing Szurubooru session and tag cache...")
    await init_szuru_session()
    await load_tag_cache()

    num_workers = settings.worker_concurrency
    logger.info("Starting %d background worker(s) (WORKER_CONCURRENCY)...", num_workers)
    worker_tasks = [asyncio.create_task(start_worker(i)) for i in range(num_workers)]

    yield

    logger.info("Shutting down workers...")
    await stop_worker()
    for task in worker_tasks:
        task.cancel()
    await asyncio.gather(*worker_tasks, return_exceptions=True)

    logger.info("Closing Szurubooru session...")
    await close_szuru_session()
    logger.info("Shutdown complete.")


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Szurubooru Companion – CCC",
    description="Command & Control Center for uploading and tagging media to Szurubooru.",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS: with allow_credentials=True, browser forbids allow_origins=["*"].
# When user sets "*" or leaves empty, use common dev origins so localhost
# frontend (e.g. :21430) can call this API (:21425). Exception handlers below
# add CORS to 4xx/5xx responses so the browser shows the real error.
_origins_raw = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
_dev_origins = [
    "http://localhost:21430",
    "http://127.0.0.1:21430",
    "http://localhost:21425",
    "http://127.0.0.1:21425",
]
if not _origins_raw or _origins_raw == ["*"]:
    cors_origins = _dev_origins
else:
    cors_origins = _origins_raw
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _cors_headers(origin: Optional[str]) -> dict:
    """Headers so browser allows cross-origin response (including on 5xx)."""
    if origin and origin in cors_origins:
        allow = origin
    else:
        allow = cors_origins[0] if cors_origins else "*"
    return {
        "Access-Control-Allow-Origin": allow,
        "Access-Control-Allow-Credentials": "true",
    }


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler_with_cors(request: Request, exc: StarletteHTTPException):
    """Ensure CORS headers on HTTPException responses (e.g. 401) so browser shows error."""
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail},
        headers=_cors_headers(request.headers.get("origin")),
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Log unhandled exceptions and return 500 with CORS so browser shows error instead of CORS block."""
    logger.exception("Unhandled exception: %s", exc)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
        headers=_cors_headers(request.headers.get("origin")),
    )


# Routers
app.include_router(health_router, prefix="/api", tags=["health"])
app.include_router(auth_router, prefix="/api", tags=["auth"])
app.include_router(setup_router, prefix="/api", tags=["setup"])
app.include_router(users_router, prefix="/api", tags=["users"])
app.include_router(settings_router, prefix="/api", tags=["settings"])
app.include_router(preferences_router, prefix="/api", tags=["preferences"])
app.include_router(jobs_router, prefix="/api", tags=["jobs"])
app.include_router(stats_router, prefix="/api", tags=["stats"])
app.include_router(events_router, prefix="/api", tags=["events"])
app.include_router(config_router, prefix="/api", tags=["config"])
app.include_router(swiper_router, prefix="/api", tags=["discover"])
app.include_router(tag_jobs_router, prefix="/api", tags=["tag-jobs"])


# ---------------------------------------------------------------------------
# Static frontend (single-container mode)
# ---------------------------------------------------------------------------
import os as _os
from pathlib import Path as _Path

_static_dir = _os.getenv("STATIC_FILES_DIR", "")
if _static_dir and _Path(_static_dir).is_dir():
    from starlette.responses import FileResponse

    _static_path = _Path(_static_dir)
    _index_path = str(_static_path / "index.html")

    @app.get("/")
    async def _serve_root():
        return FileResponse(_index_path)

    @app.get("/{full_path:path}")
    async def _spa_fallback(full_path: str):
        """Serve static file if it exists, otherwise index.html for SPA routing."""
        if ".." in full_path:
            return FileResponse(_index_path)
        candidate = _static_path / full_path
        if candidate.is_file():
            return FileResponse(str(candidate), media_type=None)
        return FileResponse(_index_path)
