"""
Statistics endpoints for the dashboard.
Uses single queries per metric to avoid transaction-aborted issues when the DB
enum or schema diverges from the app (e.g. old status values in the DB).
"""

from collections import defaultdict
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends
from sqlalchemy import String, func, select, cast, text
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

    # Average job duration (completed/merged only): seconds from created_at to updated_at.
    avg_epoch = func.avg(text("EXTRACT(EPOCH FROM (jobs.updated_at - jobs.created_at))"))
    duration_q = _apply_user_filter(
        select(avg_epoch)
        .select_from(Job)
        .where(Job.status.in_([JobStatus.COMPLETED, JobStatus.MERGED]))
    )
    avg_seconds = (await db.execute(duration_q)).scalar()
    average_job_duration_seconds = float(avg_seconds) if avg_seconds is not None else None

    # Jobs created in the last 24 hours (UTC).
    twenty_four_h_ago = datetime.now(timezone.utc) - timedelta(hours=24)
    count_24h_q = _apply_user_filter(
        select(func.count(Job.id)).select_from(Job).where(Job.created_at >= twenty_four_h_ago)
    )
    jobs_last_24h = (await db.execute(count_24h_q)).scalar() or 0

    # Uploads per day for the last 30 days, broken down by status.
    # GROUP BY date + status then pivot in Python to avoid CASE/enum mismatch
    # (same pattern as status_counts above which reads status as text).
    thirty_days_ago = datetime.now(timezone.utc) - timedelta(days=30)
    day_utc_expr = text("(jobs.created_at AT TIME ZONE 'UTC')::date")
    day_utc_select = text("(jobs.created_at AT TIME ZONE 'UTC')::date AS day")
    daily_q = _apply_user_filter(
        select(
            day_utc_select,
            cast(Job.status, String).label("status"),
            func.count(Job.id).label("count"),
        )
        .select_from(Job)
        .where(Job.created_at >= thirty_days_ago)
        .group_by(day_utc_expr, Job.status)
        .order_by(day_utc_expr)
    )
    daily_result = await db.execute(daily_q)
    rows = daily_result.all()
    daily_map: dict[str, dict] = defaultdict(
        lambda: {"count": 0, "completed": 0, "merged": 0, "failed": 0}
    )
    for row in rows:
        date = str(row[0])
        status = str(row[1]).lower()
        cnt = row[2]
        daily_map[date]["count"] += cnt
        if status in ("completed", "merged", "failed"):
            daily_map[date][status] = cnt
    daily = [{"date": d, **v} for d, v in sorted(daily_map.items())]

    return {
        "total_jobs": total,
        "by_status": status_counts,
        "daily_uploads": daily,
        "average_job_duration_seconds": average_job_duration_seconds,
        "jobs_last_24h": jobs_last_24h,
    }
