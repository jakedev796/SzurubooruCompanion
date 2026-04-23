"""
Chunked file-upload endpoints for large files.

The single-POST /api/jobs/upload endpoint in jobs.py works fine for smaller
files, but uploads over ~100 MB hit Cloudflare's per-request body limit. This
module adds a three-step flow so clients can split large files into chunks:

    1. POST /api/jobs/upload/init             -> session_id, chunk_size, total_chunks
    2. POST /api/jobs/upload/chunk/{id}/{n}   -> append chunk (n = 0..N-1)
    3. POST /api/jobs/upload/complete/{id}    -> reassemble + create Job

Chunk uploads are idempotent (re-sending chunk N overwrites) so clients can
safely retry individual chunks on network failure. Sessions expire after 24h.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.jobs import JobOut, _job_to_out, _parse_json_tags, _safe_upload_filename
from app.config import get_settings
from app.database import Job, JobType, User, get_db
from app.services import upload_sessions

logger = logging.getLogger(__name__)
settings = get_settings()
router = APIRouter()

MAX_FILENAME_LEN = 512
MAX_UPLOAD_BYTES = 10 * 1024 * 1024 * 1024  # 10 GB sanity cap


class UploadInitRequest(BaseModel):
    filename: str = Field(..., min_length=1, max_length=MAX_FILENAME_LEN)
    total_size: int = Field(..., gt=0, le=MAX_UPLOAD_BYTES)
    safety: str = "unsafe"
    skip_tagging: bool = False
    tags: Optional[str] = None
    source: Optional[str] = None


class UploadInitResponse(BaseModel):
    session_id: str
    chunk_size: int
    total_chunks: int
    expires_at: datetime


class UploadChunkResponse(BaseModel):
    received_chunks: int
    total_chunks: int


def _session_user_id(user: User) -> str:
    return str(user.id) if user.id is not None else "api_key"


async def _load_owned_session(session_id: str, user: User) -> upload_sessions.UploadSession:
    """Fetch session and verify ownership; raise 404 otherwise (hides existence)."""
    session = await upload_sessions.get_session(session_id)
    if not session or session.user_id != _session_user_id(user):
        raise HTTPException(status_code=404, detail="Upload session not found.")
    return session


@router.post("/jobs/upload/init", response_model=UploadInitResponse, status_code=201)
async def init_upload(
    body: UploadInitRequest,
    current_user: User = Depends(get_current_user),
):
    """Start a chunked upload session. Returns the chunk size and count to use."""
    safe_filename = _safe_upload_filename(body.filename)
    session = await upload_sessions.create_session(
        user_id=_session_user_id(current_user),
        filename=safe_filename,
        total_size=body.total_size,
        safety=body.safety or "unsafe",
        skip_tagging=body.skip_tagging,
        tags=body.tags,
        source=body.source,
    )
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=upload_sessions.SESSION_TTL_SECONDS)
    return UploadInitResponse(
        session_id=session.id,
        chunk_size=session.chunk_size,
        total_chunks=session.total_chunks,
        expires_at=expires_at,
    )


@router.post(
    "/jobs/upload/chunk/{session_id}/{chunk_number}",
    response_model=UploadChunkResponse,
)
async def upload_chunk(
    session_id: str,
    chunk_number: int,
    chunk: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    """Upload a single chunk. Idempotent: re-sending the same chunk number overwrites."""
    session = await _load_owned_session(session_id, current_user)

    if chunk_number < 0 or chunk_number >= session.total_chunks:
        raise HTTPException(status_code=400, detail="Chunk number out of range.")

    received = await upload_sessions.store_chunk(session, chunk_number, chunk.file)
    return UploadChunkResponse(received_chunks=received, total_chunks=session.total_chunks)


@router.post("/jobs/upload/complete/{session_id}", response_model=JobOut, status_code=201)
async def complete_upload(
    session_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Reassemble chunks, create a Job, and clean up the session."""
    session = await _load_owned_session(session_id, current_user)

    received = await upload_sessions.received_chunks(session_id)
    if len(received) != session.total_chunks:
        missing = sorted(set(range(session.total_chunks)) - set(received))
        first_missing = missing[0] if missing else None
        raise HTTPException(
            status_code=400,
            detail=f"Upload incomplete: missing {len(missing)} chunk(s) (first missing: {first_missing}).",
        )

    job_id = uuid.uuid4()
    job_dir = os.path.join(settings.job_data_dir, str(job_id))
    dest = os.path.join(job_dir, session.filename)

    try:
        await upload_sessions.assemble(session, dest)
    except (FileNotFoundError, ValueError) as e:
        # Leave the session intact so the client can retry missing chunks.
        raise HTTPException(status_code=400, detail=str(e)) from e

    parsed_tags = _parse_json_tags(session.tags) if session.tags else None
    if parsed_tags is None and session.tags:
        parsed_tags = [t.strip() for t in session.tags.split(",") if t.strip()]

    job = Job(
        id=job_id,
        job_type=JobType.FILE,
        original_filename=session.filename,
        source_override=session.source,
        initial_tags=json.dumps(parsed_tags) if parsed_tags else None,
        safety=session.safety,
        skip_tagging=1 if session.skip_tagging else 0,
        szuru_user=current_user.szuru_username,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    await upload_sessions.delete_session(session_id)

    from app.api.events import publish_job_update
    await publish_job_update(job_id=job.id, status="pending", progress=0)
    return _job_to_out(job)


@router.delete("/jobs/upload/{session_id}", status_code=200)
async def abort_upload(
    session_id: str,
    current_user: User = Depends(get_current_user),
):
    """Abort and clean up an in-progress chunked upload session."""
    session = await upload_sessions.get_session(session_id)
    if not session:
        return {"deleted": False}
    if session.user_id != _session_user_id(current_user):
        raise HTTPException(status_code=404, detail="Upload session not found.")
    await upload_sessions.delete_session(session_id)
    return {"deleted": True}
