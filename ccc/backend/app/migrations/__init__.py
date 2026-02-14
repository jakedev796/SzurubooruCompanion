"""
Auto-migrations run on startup.
Each migration is a (version, sql) pair; version is stored in schema_migrations after apply.
"""

import logging
from typing import List, Tuple

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import SchemaMigration, async_session

logger = logging.getLogger(__name__)

# (version_id, raw SQL to run). Use PostgreSQL syntax; run in order.
MIGRATIONS: List[Tuple[str, str]] = [
    (
        "001_add_initial_tags",
        """
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'initial_tags'
          ) THEN
            ALTER TABLE jobs ADD COLUMN initial_tags TEXT;
          END IF;
        END $$;
        """,
    ),
    (
        "002_add_tags_from_source_and_ai",
        """
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'tags_from_source'
          ) THEN
            ALTER TABLE jobs ADD COLUMN tags_from_source TEXT;
          END IF;
          IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'tags_from_ai'
          ) THEN
            ALTER TABLE jobs ADD COLUMN tags_from_ai TEXT;
          END IF;
        END $$;
        """,
    ),
]


async def run_migrations() -> None:
    """Apply any pending migrations."""
    async with async_session() as session:
        applied = await _applied_versions(session)
        for version, sql in MIGRATIONS:
            if version in applied:
                continue
            logger.info("Applying migration: %s", version)
            await session.execute(text(sql.strip()))
            session.add(SchemaMigration(version=version))
            await session.commit()
            logger.info("Applied migration: %s", version)


async def _applied_versions(session: AsyncSession) -> set:
    """Return set of applied migration version ids."""
    result = await session.execute(select(SchemaMigration.version))
    return {row[0] for row in result.fetchall()}
