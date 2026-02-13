"""
Statistics endpoints for the dashboard.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func, select, case, cast, Date
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import Job, JobStatus, get_db
from app.api.deps import verify_api_key

router = APIRouter()


@router.get("/stats")
async def get_stats(
    _key: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
):
    """Return aggregate job statistics."""
    total_q = select(func.count(Job.id))
    total = (await db.execute(total_q)).scalar() or 0

    status_counts = {}
    for s in JobStatus:
        q = select(func.count(Job.id)).where(Job.status == s)
        status_counts[s.value] = (await db.execute(q)).scalar() or 0

    # Uploads per day for the last 30 days (UTC)
    thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
    daily_q = (
        select(
            cast(Job.created_at, Date).label("day"),
            func.count(Job.id).label("count"),
        )
        .where(Job.created_at >= thirty_days_ago)
        .group_by(cast(Job.created_at, Date))
        .order_by(cast(Job.created_at, Date))
    )
    daily_result = await db.execute(daily_q)
    daily = [{"date": str(row.day), "count": row.count} for row in daily_result]

    return {
        "total_jobs": total,
        "by_status": status_counts,
        "daily_uploads": daily,
    }
