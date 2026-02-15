"""
CCC Backend – FastAPI entry point.
Starts the API server and the background job worker.
"""

import asyncio
import logging

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.database import init_db
from app.migrations import run_migrations
from app.api.jobs import router as jobs_router
from app.api.stats import router as stats_router
from app.api.health import router as health_router
from app.api.events import router as events_router
from app.api.config import router as config_router
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

    logger.info("Starting background worker...")
    worker_task = asyncio.create_task(start_worker())

    yield

    logger.info("Shutting down worker...")
    await stop_worker()
    worker_task.cancel()
    try:
        await worker_task
    except asyncio.CancelledError:
        pass
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

# CORS
origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(health_router, prefix="/api", tags=["health"])
app.include_router(jobs_router, prefix="/api", tags=["jobs"])
app.include_router(stats_router, prefix="/api", tags=["stats"])
app.include_router(events_router, prefix="/api", tags=["events"])
app.include_router(config_router, prefix="/api", tags=["config"])
