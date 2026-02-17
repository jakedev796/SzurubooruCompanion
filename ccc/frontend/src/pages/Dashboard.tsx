import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Play, Pause, Square, Trash2 } from "lucide-react";
import {
  fetchStats,
  fetchJobs,
  fetchJob,
  fetchConfig,
  startJob,
  pauseJob,
  stopJob,
  deleteJob,
  resumeJob,
  getJobSources,
  sortTags,
  type Job,
  type JobSummary,
  type JobsResponse,
  type StatsResponse,
} from "../api";
import { useJobUpdates } from "../hooks/useJobUpdates";
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";

const ACTIVITY_LIMIT = 10;
const CHART_ACCENT = "#C41E3A";
const CHART_GRID = "rgba(255, 255, 255, 0.06)";
const CHART_TOOLTIP_BG = "#252220";
const CHART_TOOLTIP_BORDER = "#3d3632";
const CHART_TICK = "#a39d93";

function StatusBadge({ status }: { status: string }) {
  return <span className={`badge ${status}`}>{status}</span>;
}

function formatDate(iso: string | undefined): string {
  if (!iso) return "-";
  return new Date(iso).toLocaleString();
}

const MERGED_REPORT_LIMIT = 50;

export default function Dashboard() {
  const [stats, setStats] = useState<StatsResponse | null>(null);
  const [recentJobs, setRecentJobs] = useState<JobsResponse | null>(null);
  const [mergedJobs, setMergedJobs] = useState<JobsResponse | null>(null);
  const [booruUrl, setBooruUrl] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loadingActions, setLoadingActions] = useState<Record<string, boolean>>({});
  const navigate = useNavigate();

  useEffect(() => {
    fetchConfig()
      .then((c) => setBooruUrl(c.booru_url || ""))
      .catch(() => {});
  }, []);

  useEffect(() => {
    setError(null);
    Promise.all([
      fetchStats().then(setStats).catch((e: Error) => {
        if (e.message.includes("401")) navigate("/login", { replace: true });
        else setError(e.message);
      }),
      fetchJobs({ offset: 0, limit: ACTIVITY_LIMIT })
        .then(setRecentJobs)
        .catch((e: Error) => {
          if (e.message.includes("401")) navigate("/login", { replace: true });
          else setRecentJobs(null);
        }),
      fetchJobs({ was_merge: true, limit: MERGED_REPORT_LIMIT })
        .then(setMergedJobs)
        .catch(() => setMergedJobs(null)),
    ]).then(() => {});
  }, [navigate]);

  useJobUpdates((payload: Record<string, unknown>) => {
    const id = (payload.id ?? payload.job_id) as number;
    const updatedJob = { ...payload, id } as JobSummary;
    setRecentJobs((prev) => {
      if (!prev?.results) return prev;
      const index = prev.results.findIndex((j) => String(j.id) === String(id));
      if (index >= 0) {
        const newResults = [...prev.results];
        newResults[index] = { ...prev.results[index], ...updatedJob };
        return { ...prev, results: newResults };
      }
      fetchJob(String(id))
        .then((fullJob) => {
          setRecentJobs((p) => {
            if (!p) return p;
            const idx = p.results.findIndex((j) => String(j.id) === String(id));
            if (idx >= 0) return p;
            const results = [{ ...fullJob, ...updatedJob }, ...p.results].slice(0, ACTIVITY_LIMIT);
            return { ...p, results, total: p.total + 1 };
          });
        })
        .catch(() => {});
      return prev;
    });
    if (payload.status === "merged" || (payload.status === "completed" && payload.was_merge)) {
      fetchJob(String(id))
        .then((job) => {
          setMergedJobs((prev) => {
            const list = prev?.results ?? [];
            if (list.some((j) => String(j.id) === String(id))) return prev;
            const next = [job, ...list].slice(0, MERGED_REPORT_LIMIT);
            return { results: next, total: (prev?.total ?? 0) + 1, offset: 0, limit: prev?.limit ?? MERGED_REPORT_LIMIT };
          });
        })
        .catch(() => {});
    }
  });

  async function handleJobAction(
    jobId: number,
    action: string,
    actionFn: (id: number) => Promise<Job>
  ) {
    setLoadingActions((prev) => ({ ...prev, [`${jobId}-${action}`]: true }));
    try {
      const updatedJob = await actionFn(jobId);
      setRecentJobs((prev) => {
        if (!prev) return prev;
        const index = prev.results.findIndex((j) => j.id === jobId);
        if (index >= 0) {
          const newResults = [...prev.results];
          newResults[index] = updatedJob;
          return { ...prev, results: newResults };
        }
        return prev;
      });
    } catch (e) {
      console.error(`Failed to ${action} job ${jobId}:`, (e as Error).message);
    } finally {
      setLoadingActions((prev) => ({ ...prev, [`${jobId}-${action}`]: false }));
    }
  }

  async function handleDeleteJob(jobId: number) {
    if (!confirm("Are you sure you want to delete this job?")) return;
    setLoadingActions((prev) => ({ ...prev, [`${jobId}-delete`]: true }));
    try {
      await deleteJob(jobId);
      setRecentJobs((prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          results: prev.results.filter((j) => j.id !== jobId),
          total: Math.max(0, (prev.total || 0) - 1),
        };
      });
    } catch (e) {
      console.error(`Failed to delete job ${jobId}:`, (e as Error).message);
    } finally {
      setLoadingActions((prev) => ({ ...prev, [`${jobId}-delete`]: false }));
    }
  }

  function getQuickActions(job: JobSummary) {
    const { id, status } = job;
    const isLoading = (action: string) => loadingActions[`${id}-${action}`];
    switch (status) {
      case "pending":
        return (
          <>
            <button
              className="btn btn-success btn-sm"
              onClick={() => handleJobAction(id, "start", startJob)}
              disabled={isLoading("start")}
              title="Start job"
            >
              {isLoading("start") ? "..." : <Play size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : <Trash2 size={14} />}
            </button>
          </>
        );
      case "downloading":
      case "tagging":
      case "uploading":
        return (
          <>
            <button
              className="btn btn-warning btn-sm"
              onClick={() => handleJobAction(id, "pause", pauseJob)}
              disabled={isLoading("pause")}
              title="Pause job"
            >
              {isLoading("pause") ? "..." : <Pause size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleJobAction(id, "stop", stopJob)}
              disabled={isLoading("stop")}
              title="Stop job"
            >
              {isLoading("stop") ? "..." : <Square size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : <Trash2 size={14} />}
            </button>
          </>
        );
      case "paused":
      case "stopped":
        return (
          <>
            <button
              className="btn btn-success btn-sm"
              onClick={() => handleJobAction(id, "resume", resumeJob)}
              disabled={isLoading("resume")}
              title="Resume job"
            >
              {isLoading("resume") ? "..." : <Play size={14} />}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : <Trash2 size={14} />}
            </button>
          </>
        );
      case "completed":
      case "merged":
      case "failed":
        return (
          <button
            className="btn btn-danger btn-sm"
            onClick={() => handleDeleteJob(id)}
            disabled={isLoading("delete")}
            title="Delete job"
          >
            {isLoading("delete") ? "..." : <Trash2 size={14} />}
          </button>
        );
      default:
        return null;
    }
  }

  if (error) return <p style={{ color: "var(--red)" }}>Error: {error}</p>;
  if (!stats) return <p>Loading...</p>;

  const { by_status, daily_uploads } = stats;

  return (
    <>
      {/* Primary stat cards */}
      <div className="stat-grid--primary">
        <div className="stat-card--colored stat-card--pending">
          <div className="value">{by_status.pending ?? 0}</div>
          <div className="label">Pending</div>
        </div>
        <div className="stat-card--colored stat-card--active">
          <div className="value">
            {(by_status.downloading ?? 0) + (by_status.tagging ?? 0) + (by_status.uploading ?? 0)}
          </div>
          <div className="label">Active</div>
        </div>
        <div className="stat-card--colored stat-card--completed">
          <div className="value">{by_status.completed ?? 0}</div>
          <div className="label">Completed</div>
        </div>
        <div className="stat-card--colored stat-card--failed">
          <div className="value">{by_status.failed ?? 0}</div>
          <div className="label">Failed</div>
        </div>
      </div>

      {/* Secondary stat cards (only when non-zero) */}
      {((by_status.paused ?? 0) > 0 || (by_status.stopped ?? 0) > 0) && (
        <div className="stat-grid--secondary">
          {(by_status.paused ?? 0) > 0 && (
            <div className="stat-card--colored stat-card--paused">
              <div className="value">{by_status.paused}</div>
              <div className="label">Paused</div>
            </div>
          )}
          {(by_status.stopped ?? 0) > 0 && (
            <div className="stat-card--colored stat-card--stopped">
              <div className="value">{by_status.stopped}</div>
              <div className="label">Stopped</div>
            </div>
          )}
        </div>
      )}

      {/* Daily uploads area chart */}
      {daily_uploads && daily_uploads.length > 0 && (
        <div className="card" style={{ marginBottom: "1.5rem" }}>
          <h3 style={{ marginBottom: "0.75rem" }}>Uploads - last 30 days</h3>
          <div className="chart-container" style={{ minHeight: 200 }}>
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={daily_uploads}>
                <defs>
                  <linearGradient id="uploadGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={CHART_ACCENT} stopOpacity={0.3} />
                    <stop offset="95%" stopColor={CHART_ACCENT} stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke={CHART_GRID} />
                <XAxis
                  dataKey="date"
                  type="category"
                  tick={{ fill: CHART_TICK, fontSize: 11 }}
                  tickFormatter={(v) => (v && typeof v === "string" ? v.slice(5) : String(v))}
                />
                <YAxis tick={{ fill: CHART_TICK, fontSize: 11 }} allowDecimals={false} />
                <Tooltip
                  contentStyle={{
                    background: CHART_TOOLTIP_BG,
                    border: `1px solid ${CHART_TOOLTIP_BORDER}`,
                    borderRadius: 8,
                  }}
                />
                <Area
                  type="monotone"
                  dataKey="count"
                  stroke={CHART_ACCENT}
                  strokeWidth={2}
                  fill="url(#uploadGradient)"
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}

      {/* Recent activity table */}
      <div className="card">
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            marginBottom: "0.75rem",
          }}
        >
          <h3 style={{ margin: 0 }}>Recent activity</h3>
          <Link to="/jobs">View all jobs</Link>
        </div>
        {recentJobs?.results?.length ? (
          <div className="table-wrap" style={{ overflowX: "auto" }}>
            <table>
              <thead>
                <tr>
                  <th>Status</th>
                  <th>Type</th>
                  <th>User</th>
                  <th>Source</th>
                  <th>Szuru Post</th>
                  <th>Created</th>
                  <th>Actions</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {recentJobs.results.map((j) => {
                  const sources = getJobSources(j);
                  const maxVisible = 3;
                  const visible = sources.slice(0, maxVisible);
                  const extra = sources.length - maxVisible;
                  return (
                    <tr key={j.id}>
                      <td>
                        <StatusBadge status={j.status} />
                      </td>
                      <td>{j.job_type}</td>
                      <td>{j.dashboard_username || "-"}</td>
                      <td>
                        {sources.length > 0 ? (
                          <div className="source-cell" title={sources.join("\n")}>
                            <span className="multi-source">
                              {visible.map((src, idx) => (
                                <span key={idx}>
                                  {idx > 0 && " "}
                                  <a
                                    href={src}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="source-link"
                                  >
                                    {src.length > 30 ? src.substring(0, 30) + "..." : src}
                                  </a>
                                </span>
                              ))}
                              {extra > 0 && (
                                <span className="source-count"> +{extra} more</span>
                              )}
                            </span>
                          </div>
                        ) : j.original_filename ? (
                          <span>{j.original_filename}</span>
                        ) : (
                          "-"
                        )}
                      </td>
                      <td>
                        {(j.post?.id ?? j.szuru_post_id) ? (
                          <span className="post-links">
                            <a
                              href={`${booruUrl}/post/${j.post?.id ?? j.szuru_post_id!}`}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="post-link"
                            >
                              #{j.post?.id ?? j.szuru_post_id}
                            </a>
                            {(j.post?.relations ?? j.related_post_ids)?.length ? (
                              <span
                                className="related-posts"
                                title={`Related: ${(j.post?.relations ?? j.related_post_ids)!.map((id) => `#${id}`).join(", ")}`}
                              >
                                {" "}
                                +{(j.post?.relations ?? j.related_post_ids)!.length}
                              </span>
                            ) : null}
                          </span>
                        ) : (
                          "-"
                        )}
                      </td>
                      <td>{formatDate(j.created_at)}</td>
                      <td>
                        <div className="quick-actions" style={{ display: "flex", gap: "0.25rem" }}>
                          {getQuickActions(j)}
                        </div>
                      </td>
                      <td>
                        <Link to={`/jobs/${j.id}`}>details</Link>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <p style={{ color: "var(--text-muted)" }}>No jobs yet.</p>
        )}
      </div>
    </>
  );
}
