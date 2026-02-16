"""
Statistics endpoints for the dashboard.
Uses single queries per metric to avoid transaction-aborted issues when the DB
enum or schema diverges from the app (e.g. old status values in the DB).
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import String, func, select, cast, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import Job, JobStatus, get_db
from app.api.deps import verify_api_key

router = APIRouter()


@router.get("/stats")
async def get_stats(
    _key: str = Depends(verify_api_key),
    db: AsyncSession = Depends(get_db),
    szuru_user: Optional[str] = Query(None),
):
    """Return aggregate job statistics, optionally filtered by szuru_user."""

    def _apply_user_filter(q):
        if szuru_user:
            return q.where(Job.szuru_user == szuru_user)
        return q

    total_q = _apply_user_filter(select(func.count(Job.id)).select_from(Job))
    total = (await db.execute(total_q)).scalar() or 0

    # Single GROUP BY query for all status counts; read status as text to avoid
    # Python/DB enum mismatch leaving the transaction aborted.
    status_q = _apply_user_filter(
        select(
            cast(Job.status, String).label("status"),
            func.count(Job.id).label("count"),
        )
        .select_from(Job)
        .group_by(Job.status)
    )
    status_rows = (await db.execute(status_q)).all()
    status_counts = {s.value: 0 for s in JobStatus}
    for row in status_rows:
        # Row: (status_str, count). Use index to avoid .count shadowing built-in.
        raw = row[0] if len(row) > 0 else None
        cnt = row[1] if len(row) > 1 else 0
        if raw is not None:
            key = str(raw).lower()
            if key in status_counts:
                status_counts[key] = cnt

    # Uploads per day for the last 30 days. Group by UTC date so labels match
    # stored timestamps regardless of DB session timezone. text() has no .label(),
    # so alias in SQL and use raw expression for group_by/order_by.
    thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
    day_utc_expr = text("(jobs.created_at AT TIME ZONE 'UTC')::date")
    day_utc_select = text("(jobs.created_at AT TIME ZONE 'UTC')::date AS day")
    daily_q = _apply_user_filter(
        select(day_utc_select, func.count(Job.id).label("count"))
        .select_from(Job)
        .where(Job.created_at >= thirty_days_ago)
        .group_by(day_utc_expr)
        .order_by(day_utc_expr)
    )
    daily_result = await db.execute(daily_q)
    rows = daily_result.all()
    daily = [{"date": str(row[0]), "count": row[1]} for row in rows]

    return {
        "total_jobs": total,
        "by_status": status_counts,
        "daily_uploads": daily,
    }
