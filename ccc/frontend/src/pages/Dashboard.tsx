import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
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
  type Job,
  type JobsResponse,
  type StatsResponse,
} from "../api";
import { useJobUpdates } from "../hooks/useJobUpdates";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";

const ACTIVITY_LIMIT = 20;
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

export default function Dashboard() {
  const [stats, setStats] = useState<StatsResponse | null>(null);
  const [recentJobs, setRecentJobs] = useState<JobsResponse | null>(null);
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
    ]).then(() => {});
  }, [navigate]);

  useJobUpdates((payload: Record<string, unknown>) => {
    const id = (payload.id ?? payload.job_id) as number;
    const updatedJob = { ...payload, id } as Job;
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

  function getQuickActions(job: Job) {
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
              {isLoading("start") ? "..." : "\u25B6"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : "\u2715"}
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
              {isLoading("pause") ? "..." : "\u23F8"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleJobAction(id, "stop", stopJob)}
              disabled={isLoading("stop")}
              title="Stop job"
            >
              {isLoading("stop") ? "..." : "\u23F9"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : "\u2715"}
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
              {isLoading("resume") ? "..." : "\u25B6"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : "\u2715"}
            </button>
          </>
        );
      case "completed":
      case "failed":
        return (
          <button
            className="btn btn-danger btn-sm"
            onClick={() => handleDeleteJob(id)}
            disabled={isLoading("delete")}
            title="Delete job"
          >
            {isLoading("delete") ? "..." : "\u2715"}
          </button>
        );
      default:
        return null;
    }
  }

  if (error) return <p style={{ color: "var(--red)" }}>Error: {error}</p>;
  if (!stats) return <p>Loading...</p>;

  const { by_status, daily_uploads } = stats;
  const statusChartData = [
    { name: "Pending", count: by_status.pending ?? 0 },
    { name: "Completed", count: by_status.completed ?? 0 },
    { name: "Failed", count: by_status.failed ?? 0 },
    { name: "Downloading", count: by_status.downloading ?? 0 },
    { name: "Tagging", count: by_status.tagging ?? 0 },
    { name: "Uploading", count: by_status.uploading ?? 0 },
    { name: "Paused", count: by_status.paused ?? 0 },
    { name: "Stopped", count: by_status.stopped ?? 0 },
  ].filter(
    (d) =>
      d.count > 0 ||
      d.name === "Pending" ||
      d.name === "Completed" ||
      d.name === "Failed"
  );

  if (statusChartData.length === 0) {
    statusChartData.push(
      { name: "Pending", count: 0 },
      { name: "Completed", count: 0 },
      { name: "Failed", count: 0 }
    );
  }

  return (
    <>
      <div className="card" style={{ marginBottom: "1.5rem" }}>
        <h3 style={{ marginBottom: "0.75rem" }}>Jobs by status</h3>
        <div className="chart-container" style={{ minHeight: 220 }}>
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={statusChartData} margin={{ top: 8, right: 8, left: 8, bottom: 8 }}>
              <CartesianGrid strokeDasharray="3 3" stroke={CHART_GRID} />
              <XAxis dataKey="name" type="category" tick={{ fill: CHART_TICK, fontSize: 11 }} />
              <YAxis tick={{ fill: CHART_TICK, fontSize: 11 }} allowDecimals={false} />
              <Tooltip
                contentStyle={{
                  background: CHART_TOOLTIP_BG,
                  border: `1px solid ${CHART_TOOLTIP_BORDER}`,
                  borderRadius: 8,
                }}
              />
              <Bar dataKey="count" fill={CHART_ACCENT} radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {daily_uploads && daily_uploads.length > 0 && (
        <div className="card" style={{ marginBottom: "1.5rem" }}>
          <h3 style={{ marginBottom: "0.75rem" }}>Uploads – last 30 days</h3>
          <div className="chart-container" style={{ minHeight: 200 }}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={daily_uploads}>
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
                <Bar dataKey="count" fill={CHART_ACCENT} radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}

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
                  <th>Source</th>
                  <th>Szuru Post</th>
                  <th>Created</th>
                  <th>Actions</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {recentJobs.results.map((j) => {
                  const sources = j.url ? j.url.split("\n") : [];
                  const hasMultipleSources = sources.length > 1;
                  const firstSource = sources[0] || j.original_filename || "";
                  return (
                    <tr key={j.id}>
                      <td>
                        <StatusBadge status={j.status} />
                      </td>
                      <td>{j.job_type}</td>
                      <td>
                        {j.url ? (
                          <div className="source-cell" title={j.url}>
                            {hasMultipleSources ? (
                              <span className="multi-source">
                                <a
                                  href={firstSource}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="source-link"
                                >
                                  {firstSource.length > 30
                                    ? firstSource.substring(0, 30) + "..."
                                    : firstSource}
                                </a>
                                <span className="source-count"> +{sources.length - 1} more</span>
                              </span>
                            ) : (
                              <a
                                href={firstSource}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="source-link"
                              >
                                {firstSource.length > 30
                                  ? firstSource.substring(0, 30) + "..."
                                  : firstSource}
                              </a>
                            )}
                          </div>
                        ) : j.original_filename ? (
                          <span>{j.original_filename}</span>
                        ) : (
                          "-"
                        )}
                      </td>
                      <td>
                        {j.szuru_post_id ? (
                          <span className="post-links">
                            <a
                              href={`${booruUrl}/post/${j.szuru_post_id}`}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="post-link"
                            >
                              #{j.szuru_post_id}
                            </a>
                            {j.related_post_ids?.length ? (
                              <span
                                className="related-posts"
                                title={`Related: ${j.related_post_ids.map((id) => `#${id}`).join(", ")}`}
                              >
                                {" "}
                                +{j.related_post_ids.length}
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
