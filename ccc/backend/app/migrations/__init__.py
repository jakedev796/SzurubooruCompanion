"""
Auto-migrations run on startup.
Each migration is a (version, sql) pair; version is stored in schema_migrations after apply.
"""

import logging
from typing import List, Tuple

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import SchemaMigration, async_session, engine

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
    (
        "003_add_related_post_ids",
        """
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'related_post_ids'
          ) THEN
            ALTER TABLE jobs ADD COLUMN related_post_ids INTEGER[] DEFAULT '{}';
          END IF;
        END $$;
        """,
    ),
]


async def _check_enum_value_exists(conn, enum_name: str, value: str) -> bool:
    """
    Check if an enum value already exists in the PostgreSQL enum type.
    Uses parameterized query for safety.
    """
    check_sql = text("""
        SELECT 1 FROM pg_enum 
        WHERE enumlabel = :value 
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = :enum_name)
    """)
    result = await conn.execute(check_sql, {"value": value, "enum_name": enum_name})
    return result.fetchone() is not None


async def _add_enum_value(enum_name: str, value: str) -> bool:
    """
    Add a value to a PostgreSQL enum type.
    
    PostgreSQL ALTER TYPE ... ADD VALUE has special requirements:
    - Cannot be run inside a transaction block in PostgreSQL < 12
    - In PostgreSQL 12+, can run in transaction but only if it's the only operation
    - No IF NOT EXISTS syntax support
    
    This function uses AUTOCOMMIT isolation level to ensure it works across
    all PostgreSQL versions and handles the operation safely.
    
    Returns True if the value was added or already exists, False on error.
    """
    try:
        # Get a fresh connection with AUTOCOMMIT isolation level
        # This is required for ALTER TYPE ... ADD VALUE in PostgreSQL
        async with engine.connect() as conn:
            # Set autocommit mode - this prevents any transaction from being started
            conn = await conn.execution_options(isolation_level="AUTOCOMMIT")
            
            # First check if the value already exists (idempotent)
            if await _check_enum_value_exists(conn, enum_name, value):
                logger.debug("Enum value already exists: %s.%s", enum_name, value)
                return True
            
            # Value doesn't exist, add it
            # Note: We use text() with bind parameters for safety
            # However, DDL statements don't support bind parameters for identifiers
            # Since enum_name and value come from our code (not user input), it's safe
            add_sql = text(f"ALTER TYPE {enum_name} ADD VALUE '{value}'")
            await conn.execute(add_sql)
            logger.info("Added enum value: %s.%s", enum_name, value)
            return True
            
    except Exception as e:
        # Check if it's a "duplicate" error - value might have been added by another process
        error_str = str(e).lower()
        if "already exists" in error_str or "duplicate" in error_str:
            logger.debug("Enum value %s.%s already exists (race condition handled)", enum_name, value)
            return True
        
        logger.error("Failed to add enum value %s.%s: %s", enum_name, value, e)
        return False


async def _ensure_enum_values() -> None:
    """
    Ensure all required enum values exist in the jobstatus enum type.
    
    This function is idempotent and safe to run multiple times.
    It handles:
    - Values that already exist (skips them)
    - Race conditions when multiple processes try to add the same value
    - Connection pooling issues by using fresh connections
    - PostgreSQL version differences in transaction handling
    """
    enum_values = [
        ("jobstatus", "paused"),
        ("jobstatus", "stopped"),
    ]
    
    for enum_name, value in enum_values:
        success = await _add_enum_value(enum_name, value)
        if not success:
            logger.warning(
                "Could not add enum value %s.%s - this may cause issues if the value is truly missing",
                enum_name, value
            )


async def run_migrations() -> None:
    """Apply any pending migrations."""
    # Run regular migrations (inside transaction)
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
    
    # Ensure enum values exist - this is now the primary way we add enum values
    # It's idempotent and handles all edge cases
    await _ensure_enum_values()


async def _applied_versions(session: AsyncSession) -> set:
    """Return set of applied migration version ids."""
    result = await session.execute(select(SchemaMigration.version))
    return {row[0] for row in result.fetchall()}
