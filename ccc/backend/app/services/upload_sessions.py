"""
Chunked upload session management.

Sessions live in Redis (TTL 24h) with chunk files on disk under
``{job_data_dir}/upload_sessions/{session_id}/``. When all chunks are
received, the session is finalized by the /complete endpoint: chunks are
reassembled into the job data directory, a Job row is created, and the
session is cleaned up.
"""

import asyncio
import logging
import os
import shutil
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import List, Optional

from redis.asyncio import Redis

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Server-dictated chunk size. 10 MB keeps each request well below common
# edge-proxy body limits (Cloudflare free tier caps at 100 MB per request).
CHUNK_SIZE_BYTES = 10 * 1024 * 1024
SESSION_TTL_SECONDS = 24 * 60 * 60
SESSIONS_SUBDIR = "upload_sessions"


def _session_key(session_id: str) -> str:
    return f"upload_session:{session_id}"


def _received_key(session_id: str) -> str:
    return f"upload_session:{session_id}:received"


def _session_dir(session_id: str) -> str:
    return os.path.join(settings.job_data_dir, SESSIONS_SUBDIR, session_id)


def _chunk_path(session_id: str, chunk_number: int) -> str:
    return os.path.join(_session_dir(session_id), f"chunk_{chunk_number}.part")


def _redis() -> Redis:
    return Redis.from_url(settings.redis_url, decode_responses=True)


@dataclass
class UploadSession:
    id: str
    user_id: str
    filename: str
    total_size: int
    total_chunks: int
    chunk_size: int
    safety: str
    skip_tagging: bool
    tags: Optional[str]
    source: Optional[str]


async def create_session(
    user_id: str,
    filename: str,
    total_size: int,
    safety: str,
    skip_tagging: bool,
    tags: Optional[str],
    source: Optional[str],
) -> UploadSession:
    """Create a new upload session and its on-disk chunk dir."""
    session_id = str(uuid.uuid4())
    total_chunks = max(1, (total_size + CHUNK_SIZE_BYTES - 1) // CHUNK_SIZE_BYTES)

    os.makedirs(_session_dir(session_id), exist_ok=True)

    data = {
        "user_id": user_id,
        "filename": filename,
        "total_size": str(total_size),
        "total_chunks": str(total_chunks),
        "chunk_size": str(CHUNK_SIZE_BYTES),
        "safety": safety,
        "skip_tagging": "1" if skip_tagging else "0",
        "tags": tags or "",
        "source": source or "",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    redis = _redis()
    try:
        await redis.hset(_session_key(session_id), mapping=data)
        await redis.expire(_session_key(session_id), SESSION_TTL_SECONDS)
    finally:
        await redis.close()

    return UploadSession(
        id=session_id,
        user_id=user_id,
        filename=filename,
        total_size=total_size,
        total_chunks=total_chunks,
        chunk_size=CHUNK_SIZE_BYTES,
        safety=safety,
        skip_tagging=skip_tagging,
        tags=tags,
        source=source,
    )


async def get_session(session_id: str) -> Optional[UploadSession]:
    """Load a session from Redis, or return None if missing/expired."""
    redis = _redis()
    try:
        data = await redis.hgetall(_session_key(session_id))
    finally:
        await redis.close()
    if not data:
        return None
    try:
        return UploadSession(
            id=session_id,
            user_id=data["user_id"],
            filename=data["filename"],
            total_size=int(data["total_size"]),
            total_chunks=int(data["total_chunks"]),
            chunk_size=int(data["chunk_size"]),
            safety=data.get("safety") or "unsafe",
            skip_tagging=data.get("skip_tagging") == "1",
            tags=data.get("tags") or None,
            source=data.get("source") or None,
        )
    except (KeyError, ValueError):
        return None


async def store_chunk(session: UploadSession, chunk_number: int, stream) -> int:
    """Write a chunk atomically to disk and record receipt; returns received count."""
    os.makedirs(_session_dir(session.id), exist_ok=True)
    path = _chunk_path(session.id, chunk_number)
    tmp_path = path + ".tmp"
    with open(tmp_path, "wb") as f:
        shutil.copyfileobj(stream, f)
    os.replace(tmp_path, path)

    redis = _redis()
    try:
        await redis.sadd(_received_key(session.id), chunk_number)
        await redis.expire(_received_key(session.id), SESSION_TTL_SECONDS)
        await redis.expire(_session_key(session.id), SESSION_TTL_SECONDS)
        return await redis.scard(_received_key(session.id))
    finally:
        await redis.close()


async def received_chunks(session_id: str) -> List[int]:
    redis = _redis()
    try:
        members = await redis.smembers(_received_key(session_id))
    finally:
        await redis.close()
    try:
        return sorted(int(m) for m in members)
    except ValueError:
        return []


async def assemble(session: UploadSession, dest_path: str) -> None:
    """Reassemble chunks into dest_path. Raises if a chunk is missing or size mismatches."""
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    with open(dest_path, "wb") as out:
        for i in range(session.total_chunks):
            part = _chunk_path(session.id, i)
            if not os.path.isfile(part):
                raise FileNotFoundError(f"Missing chunk {i} for session {session.id}")
            with open(part, "rb") as src:
                shutil.copyfileobj(src, out)

    size = os.path.getsize(dest_path)
    if size != session.total_size:
        raise ValueError(
            f"Assembled size {size} does not match expected {session.total_size}"
        )


async def delete_session(session_id: str) -> None:
    """Remove Redis keys and on-disk chunks for a session."""
    redis = _redis()
    try:
        await redis.delete(_session_key(session_id), _received_key(session_id))
    finally:
        await redis.close()

    session_dir = _session_dir(session_id)
    if os.path.isdir(session_dir):
        shutil.rmtree(session_dir, ignore_errors=True)


async def _cleanup_orphaned_dirs() -> None:
    """Delete chunk dirs whose Redis session no longer exists (TTL-expired or aborted)."""
    base = os.path.join(settings.job_data_dir, SESSIONS_SUBDIR)
    if not os.path.isdir(base):
        return
    try:
        entries = os.listdir(base)
    except OSError:
        return

    redis = _redis()
    try:
        for name in entries:
            path = os.path.join(base, name)
            if not os.path.isdir(path):
                continue
            exists = await redis.exists(_session_key(name))
            if not exists:
                shutil.rmtree(path, ignore_errors=True)
                logger.info("Cleaned up orphaned upload session dir: %s", name)
    finally:
        await redis.close()


async def cleanup_loop(interval_seconds: int = 3600) -> None:
    """Background task: periodically removes orphaned chunk dirs."""
    while True:
        try:
            await _cleanup_orphaned_dirs()
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("Upload session cleanup error: %s", e)
        await asyncio.sleep(interval_seconds)
