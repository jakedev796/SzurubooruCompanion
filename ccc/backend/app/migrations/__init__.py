"""
Auto-migrations run on startup.
Migrations are .sql files in app/migrations/sql/ named {version_id}.sql (e.g. 001_add_initial_tags.sql).
Applied versions are stored in schema_migrations.
"""

import logging
from pathlib import Path

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import SchemaMigration, User, UserRole, async_session, engine

logger = logging.getLogger(__name__)

_SQL_DIR = Path(__file__).resolve().parent / "sql"


def _split_sql_statements(content: str) -> list[str]:
    """
    Split SQL by semicolon into statements, without splitting inside dollar-quoted strings ($$...$$).
    So DO $$ ... END $$; is kept as one statement.
    """
    content = content.strip()
    if not content:
        return []
    parts = content.split(";")
    statements: list[str] = []
    current: list[str] = []
    for i, part in enumerate(parts):
        current.append(part)
        merged = ";".join(current)
        if merged.count("$$") % 2 == 0:
            stmt = merged.strip()
            if stmt:
                statements.append(stmt)
            current = []
    if current:
        stmt = ";".join(current).strip()
        if stmt:
            statements.append(stmt)
    return statements


def _discover_migrations() -> list[str]:
    """Return sorted list of migration version ids (filename stem) from sql/ directory."""
    if not _SQL_DIR.is_dir():
        return []
    versions = [f.stem for f in _SQL_DIR.glob("*.sql")]
    return sorted(versions)


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
        ("jobtype", "TAG_EXISTING"),
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
    """Apply any pending migrations from app/migrations/sql/*.sql."""
    async with async_session() as session:
        applied = await _applied_versions(session)
        for version in _discover_migrations():
            if version in applied:
                continue
            sql_path = _SQL_DIR / f"{version}.sql"
            if not sql_path.is_file():
                continue
            logger.info("Applying migration: %s", version)
            content = sql_path.read_text(encoding="utf-8")
            statements = _split_sql_statements(content)
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
