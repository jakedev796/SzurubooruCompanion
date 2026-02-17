"""
Auto-migrations run on startup.
Each migration is a (version, sql) pair; version is stored in schema_migrations after apply.
"""

import logging
from typing import List, Tuple

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import SchemaMigration, User, UserRole, async_session, engine

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
    (
        "004_create_tag_cache",
        """
        CREATE TABLE IF NOT EXISTS tag_cache (
            tag_name    VARCHAR(512) PRIMARY KEY,
            category    VARCHAR(128) NOT NULL,
            verified_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
        );
        """,
    ),
    (
        "005_add_szuru_user",
        """
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'szuru_user'
          ) THEN
            ALTER TABLE jobs ADD COLUMN szuru_user VARCHAR(255);
          END IF;
        END $$;
        """,
    ),
    (
        "006_add_was_merge",
        """
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'was_merge'
          ) THEN
            ALTER TABLE jobs ADD COLUMN was_merge INTEGER NOT NULL DEFAULT 0;
          END IF;
        END $$;
        """,
    ),
    (
        "007_create_users_table",
        """
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            username VARCHAR(255) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            role VARCHAR(16) NOT NULL DEFAULT 'user',
            szuru_url VARCHAR(512),
            szuru_username VARCHAR(255),
            szuru_token_encrypted TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
        """,
    ),
    (
        "008_create_site_credentials_table",
        """
        CREATE TABLE IF NOT EXISTS site_credentials (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL,
            site_name VARCHAR(64) NOT NULL,
            credential_key VARCHAR(128) NOT NULL,
            credential_value_encrypted TEXT NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_user_site_cred UNIQUE(user_id, site_name, credential_key)
        );
        CREATE INDEX IF NOT EXISTS idx_site_creds_user ON site_credentials(user_id);
        """,
    ),
    (
        "009_create_global_settings_table",
        """
        CREATE TABLE IF NOT EXISTS global_settings (
            key VARCHAR(255) PRIMARY KEY,
            value TEXT,
            value_type VARCHAR(32) NOT NULL DEFAULT 'string',
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
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
    Add a value to a PostgreSQL enum type. Idempotent; uses AUTOCOMMIT for ALTER TYPE compatibility.
    """
    try:
        async with engine.connect() as conn:
            conn = await conn.execution_options(isolation_level="AUTOCOMMIT")
            if await _check_enum_value_exists(conn, enum_name, value):
                logger.debug("Enum value already exists: %s.%s", enum_name, value)
                return True
            add_sql = text(f"ALTER TYPE {enum_name} ADD VALUE '{value}'")
            await conn.execute(add_sql)
            logger.info("Added enum value: %s.%s", enum_name, value)
            return True
    except Exception as e:
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
    # SQLAlchemy persists enum member names by default, so use uppercase to match DB.
    enum_values = [
        ("jobstatus", "paused"),
        ("jobstatus", "stopped"),
        ("jobstatus", "MERGED"),
    ]
    
    for enum_name, value in enum_values:
        success = await _add_enum_value(enum_name, value)
        if not success:
            logger.warning(
                "Could not add enum value %s.%s - this may cause issues if the value is truly missing",
                enum_name, value
            )


async def _bootstrap_admin_user() -> None:
    """
    Create admin user from ENV if ADMIN_USER and ADMIN_PASSWORD are set.
    This is a one-time bootstrap - runs only if the user doesn't exist.
    After this, all user management is done via the database/dashboard.
    """
    import os
    from app.database import User, UserRole

    admin_user = os.getenv("ADMIN_USER", "").strip()
    admin_pass = os.getenv("ADMIN_PASSWORD", "").strip()

    if not admin_user or not admin_pass:
        logger.info("ADMIN_USER/ADMIN_PASSWORD not set - skipping admin user bootstrap")
        return

    async with async_session() as session:
        # Check if admin user already exists
        result = await session.execute(
            select(User).where(User.username == admin_user)
        )
        existing = result.scalar_one_or_none()

        if existing:
            logger.info("Admin user '%s' already exists - skipping bootstrap", admin_user)
            return

        # Import here to avoid circular dependency (auth service imports database)
        try:
            from app.services.auth import hash_password
        except ImportError:
            # If auth service doesn't exist yet (during development), use a placeholder
            # This will be replaced once we create the auth service
            logger.warning("auth service not available yet - cannot create admin user")
            return

        # Create admin user
        admin = User(
            username=admin_user,
            password_hash=hash_password(admin_pass),
            role=UserRole.ADMIN,
            is_active=1,
        )
        session.add(admin)
        await session.commit()
        logger.info("Created admin user: %s", admin_user)


async def run_migrations() -> None:
    """Apply any pending migrations."""
    # Run regular migrations (inside transaction)
    async with async_session() as session:
        applied = await _applied_versions(session)
        for version, sql in MIGRATIONS:
            if version in applied:
                continue
            logger.info("Applying migration: %s", version)

            # Split SQL into individual statements (asyncpg doesn't support multiple commands)
            statements = [s.strip() for s in sql.strip().split(';') if s.strip()]
            for stmt in statements:
                await session.execute(text(stmt))

            session.add(SchemaMigration(version=version))
            await session.commit()
            logger.info("Applied migration: %s", version)

    # Ensure enum values exist - this is now the primary way we add enum values
    # It's idempotent and handles all edge cases
    await _ensure_enum_values()

    # Bootstrap admin user from ENV (one-time, idempotent)
    await _bootstrap_admin_user()


async def _applied_versions(session: AsyncSession) -> set:
    """Return set of applied migration version ids."""
    result = await session.execute(select(SchemaMigration.version))
    return {row[0] for row in result.fetchall()}
