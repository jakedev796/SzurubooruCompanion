"""
Statistics endpoints for the dashboard.
Uses single queries per metric to avoid transaction-aborted issues when the DB
enum or schema diverges from the app (e.g. old status values in the DB).
"""

from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends
from sqlalchemy import String, func, select, cast, text, case
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import Job, JobStatus, User, get_db
from app.api.deps import get_current_user

router = APIRouter()


@router.get("/stats")
async def get_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return aggregate job statistics for the current authenticated user."""

    def _apply_user_filter(q):
        # Auto-filter by current user's szuru_username (JWT auth)
        if current_user.szuru_username:
            return q.where(Job.szuru_user == current_user.szuru_username)
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

    # Keep completed and merged separate so the dashboard can show both.

    # Uploads per day for the last 30 days (completed, merged, failed). Group by UTC date.
    thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
    day_utc_expr = text("(jobs.created_at AT TIME ZONE 'UTC')::date")
    day_utc_select = text("(jobs.created_at AT TIME ZONE 'UTC')::date AS day")
    status_str = cast(Job.status, String)
    completed_case = case((status_str == "completed", 1), else_=0)
    merged_case = case((status_str == "merged", 1), else_=0)
    failed_case = case((status_str == "failed", 1), else_=0)
    daily_q = _apply_user_filter(
        select(
            day_utc_select,
            func.count(Job.id).label("count"),
            func.sum(completed_case).label("completed"),
            func.sum(merged_case).label("merged"),
            func.sum(failed_case).label("failed"),
        )
        .select_from(Job)
        .where(Job.created_at >= thirty_days_ago)
        .group_by(day_utc_expr)
        .order_by(day_utc_expr)
    )
    daily_result = await db.execute(daily_q)
    rows = daily_result.all()
    daily = [
        {
            "date": str(row[0]),
            "count": row[1],
            "completed": int(row[2] or 0),
            "merged": int(row[3] or 0),
            "failed": int(row[4] or 0),
        }
        for row in rows
    ]

    return {
        "total_jobs": total,
        "by_status": status_counts,
        "daily_uploads": daily,
    }
