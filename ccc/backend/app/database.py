"""
Database models and session management.
All timestamps are stored in UTC.
"""

import uuid
from datetime import datetime, timezone
from enum import Enum as PyEnum

from sqlalchemy import (
    ARRAY,
    Column,
    DateTime,
    Enum,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import get_settings

settings = get_settings()

engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    pool_pre_ping=True,
)

async_session = sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    pass


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class JobStatus(str, PyEnum):
    PENDING = "pending"
    DOWNLOADING = "downloading"
    TAGGING = "tagging"
    UPLOADING = "uploading"
    COMPLETED = "completed"
    MERGED = "merged"
    FAILED = "failed"
    PAUSED = "paused"
    STOPPED = "stopped"


class JobType(str, PyEnum):
    URL = "url"
    FILE = "file"


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class Job(Base):
    __tablename__ = "jobs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    status = Column(Enum(JobStatus), nullable=False, default=JobStatus.PENDING, index=True)
    job_type = Column(Enum(JobType), nullable=False)

    # Input
    url = Column(Text, nullable=True)
    original_filename = Column(String(512), nullable=True)
    source_override = Column(Text, nullable=True)
    initial_tags = Column(Text, nullable=True)  # JSON array from client (e.g. browser-ext)
    safety = Column(String(16), nullable=True, default="unsafe")
    skip_tagging = Column(Integer, nullable=False, default=0)
    szuru_user = Column(String(255), nullable=True)  # Which Szurubooru user to upload as

    # Output
    szuru_post_id = Column(Integer, nullable=True)
    related_post_ids = Column(ARRAY(Integer), default=list)  # Related posts from multi-file sources
    was_merge = Column(Integer, nullable=False, default=0)  # 1 if job merged into existing post
    error_message = Column(Text, nullable=True)
    tags_applied = Column(Text, nullable=True)  # JSON array stored as text
    tags_from_source = Column(Text, nullable=True)  # JSON array: from metadata / initial / inferred
    tags_from_ai = Column(Text, nullable=True)  # JSON array: from WD14

    # Retry tracking
    retry_count = Column(Integer, nullable=False, default=0)

    # Timestamps (always UTC)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )


class TagCache(Base):
    """Cache of tags verified to exist in Szurubooru with the correct category."""

    __tablename__ = "tag_cache"

    tag_name = Column(String(512), primary_key=True)  # stored lowercased
    category = Column(String(128), nullable=False)
    verified_at = Column(DateTime(timezone=True), nullable=False,
                         default=lambda: datetime.now(timezone.utc))


class SchemaMigration(Base):
    """Tracks applied schema migrations for auto-migration on startup."""

    __tablename__ = "schema_migrations"

    version = Column(String(255), primary_key=True)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def init_db() -> None:
    """Create all tables if they don't exist."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_db() -> AsyncSession:
    """Yield a database session for FastAPI dependency injection."""
    async with async_session() as session:
        try:
            yield session
        finally:
            await session.close()
