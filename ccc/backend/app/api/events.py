"""
Server-Sent Events (SSE) endpoint for real-time job updates.
Clients connect to /api/events to receive push notifications when job status changes.
"""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import AsyncGenerator, Optional

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse
from redis.asyncio import Redis

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

router = APIRouter()

# Redis channel name for job updates
JOB_UPDATES_CHANNEL = "job_updates"

# Heartbeat interval in seconds
HEARTBEAT_INTERVAL = 30


def get_redis_client() -> Redis:
    """Create a Redis client for pub/sub."""
    return Redis.from_url(settings.redis_url, decode_responses=True)


async def event_stream(request: Request) -> AsyncGenerator[str, None]:
    """
    Generate SSE events from Redis pub/sub.
    
    Yields SSE-formatted strings with job update events and heartbeats.
    Handles client disconnect gracefully.
    """
    redis = get_redis_client()
    pubsub = redis.pubsub()
    
    heartbeat_task = None
    try:
        await pubsub.subscribe(JOB_UPDATES_CHANNEL)
        logger.info("SSE client connected, subscribed to %s", JOB_UPDATES_CHANNEL)
        
        # Send initial connection event
        yield format_sse_event(
            event="connected",
            data={"message": "Connected to job updates stream", "timestamp": get_timestamp()}
        )
        
        # Create heartbeat task
        heartbeat_task = asyncio.create_task(heartbeat_generator())
        
        # Listen for messages
        while True:
            # Check if client disconnected
            if await request.is_disconnected():
                logger.info("SSE client disconnected")
                break
            
            try:
                # Check for Redis messages with timeout
                message = await asyncio.wait_for(
                    pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0),
                    timeout=2.0
                )
                
                if message and message["type"] == "message":
                    # Forward the job update to the client
                    yield format_sse_event(event="job_update", data=message["data"])
                    
            except asyncio.TimeoutError:
                # No message, continue loop (allows checking for disconnect)
                pass
            
            # Check for heartbeat
            if heartbeat_task.done():
                heartbeat = heartbeat_task.result()
                yield heartbeat
                heartbeat_task = asyncio.create_task(heartbeat_generator())
                
    except asyncio.CancelledError:
        logger.info("SSE stream cancelled")
        raise
    except Exception as e:
        logger.exception("SSE stream error: %s", e)
        yield format_sse_event(event="error", data={"error": str(e)})
    finally:
        if heartbeat_task is not None:
            heartbeat_task.cancel()
            try:
                await heartbeat_task
            except asyncio.CancelledError:
                pass
        await pubsub.unsubscribe(JOB_UPDATES_CHANNEL)
        await pubsub.close()
        await redis.close()
        logger.info("SSE connection cleaned up")


async def heartbeat_generator() -> str:
    """Generate a heartbeat comment after HEARTBEAT_INTERVAL seconds."""
    await asyncio.sleep(HEARTBEAT_INTERVAL)
    return format_sse_comment(f"heartbeat {get_timestamp()}")


def format_sse_event(event: str, data: dict) -> str:
    """
    Format data as a Server-Sent Event.
    
    Args:
        event: Event type (e.g., 'job_update', 'connected', 'error')
        data: Event data dictionary
        
    Returns:
        SSE-formatted string with event and data fields
    """
    # If data is a string, parse it (from Redis messages)
    if isinstance(data, str):
        try:
            data = json.loads(data)
        except json.JSONDecodeError:
            data = {"raw": data}
    
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


def format_sse_comment(comment: str) -> str:
    """
    Format a comment for SSE (used for heartbeats).
    Comments are ignored by EventSource clients but keep the connection alive.
    """
    return f": {comment}\n\n"


def get_timestamp() -> str:
    """Return current UTC timestamp in ISO 8601 format."""
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


@router.get("/events")
async def sse_events(request: Request):
    """
    SSE endpoint for real-time job updates.
    
    Clients connect here to receive push notifications when:
    - Job status changes (pending, downloading, tagging, uploading, completed, failed)
    - Job progress updates
    
    Event format:
    ```
    event: job_update
    data: {"job_id": 123, "status": "downloading", "progress": 25, "timestamp": "2024-01-15T10:30:00Z"}
    ```
    
    Heartbeats are sent every 30 seconds to keep connections alive.
    """
    return StreamingResponse(
        event_stream(request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  # Disable nginx buffering
            "Access-Control-Allow-Origin": "*",
        }
    )


async def publish_job_update(
    job_id,
    status: str,
    progress: Optional[int] = None,
    error: Optional[str] = None,
    szuru_post_id: Optional[int] = None,
    tags: Optional[list] = None,
) -> None:
    """
    Publish a job update to Redis for SSE distribution.
    
    This function is called by the job processor when job status changes.
    All connected SSE clients will receive the update.
    
    Args:
        job_id: The job ID (UUID or string)
        status: New job status (pending, downloading, tagging, uploading, completed, failed)
        progress: Optional progress percentage (0-100)
        error: Optional error message for failed jobs
        szuru_post_id: Optional Szurubooru post ID for completed jobs
        tags: Optional list of applied tags for completed jobs
    """
    redis = get_redis_client()
    
    try:
        # Convert UUID to string if necessary
        if hasattr(job_id, 'hex'):
            job_id = str(job_id)
        
        data = {
            "job_id": job_id,
            "status": status,
            "timestamp": get_timestamp(),
        }
        
        if progress is not None:
            data["progress"] = progress
        if error is not None:
            data["error"] = error
        if szuru_post_id is not None:
            data["szuru_post_id"] = szuru_post_id
        if tags is not None:
            data["tags"] = tags
        
        await redis.publish(JOB_UPDATES_CHANNEL, json.dumps(data))
        logger.debug("Published job update: %s", data)
        
    except Exception as e:
        logger.error("Failed to publish job update: %s", e)
    finally:
        await redis.close()
