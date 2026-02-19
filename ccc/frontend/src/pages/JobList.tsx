import { useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  Play,
  Pause,
  Square,
  Trash2,
  RefreshCcw,
  Clock,
  Download,
  Tag,
  Upload,
  CheckCircle2,
  GitMerge,
  XCircle,
  Ban,
} from "lucide-react";
import {
  fetchJobs,
  fetchJob,
  fetchConfig,
  startJob,
  pauseJob,
  stopJob,
  deleteJob,
  resumeJob,
  retryJob,
  bulkRetryJobs,
  bulkDeleteJobs,
  bulkStartJobs,
  bulkPauseJobs,
  bulkStopJobs,
  bulkResumeJobs,
  getJobSources,
  type Job,
  type JobSummary,
  type JobsResponse,
} from "../api";
import { useJobUpdates } from "../hooks/useJobUpdates";

const PAGE_SIZE = 20;

const STATUS_ICONS: Record<string, React.ReactNode> = {
  pending: <Clock size={12} />,
  downloading: <Download size={12} />,
  tagging: <Tag size={12} />,
  uploading: <Upload size={12} />,
  paused: <Pause size={12} />,
  completed: <CheckCircle2 size={12} />,
  merged: <GitMerge size={12} />,
  stopped: <Ban size={12} />,
  failed: <XCircle size={12} />,
};

function StatusBadge({ status }: { status: string }) {
  const key = status.toLowerCase();
  const icon = STATUS_ICONS[key];
  return (
    <span className={`badge ${key}`}>
      {icon && <span className="badge-icon">{icon}</span>}
      {status}
    </span>
  );
}

const STATUS_FILTER_ORDER: { value: string; label: string; icon: React.ReactNode }[] = [
  { value: "", label: "All statuses", icon: null },
  { value: "pending", label: "Pending", icon: <Clock size={12} /> },
  { value: "downloading", label: "Downloading", icon: <Download size={12} /> },
  { value: "tagging", label: "Tagging", icon: <Tag size={12} /> },
  { value: "uploading", label: "Uploading", icon: <Upload size={12} /> },
  { value: "paused", label: "Paused", icon: <Pause size={12} /> },
  { value: "completed", label: "Completed", icon: <CheckCircle2 size={12} /> },
  { value: "merged", label: "Merged", icon: <GitMerge size={12} /> },
  { value: "stopped", label: "Stopped", icon: <Ban size={12} /> },
  { value: "failed", label: "Failed", icon: <XCircle size={12} /> },
];

function formatDate(iso: string | undefined): string {
  if (!iso) return "-";
  return new Date(iso).toLocaleString();
}

export default function JobList() {
  const [searchParams, setSearchParams] = useSearchParams();
  const statusFilter = searchParams.get("status") || "";
  const page = parseInt(searchParams.get("page") || "0", 10);

  const [data, setData] = useState<JobsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [booruUrl, setBooruUrl] = useState("");
  const [loadingActions, setLoadingActions] = useState<Record<string, boolean>>({});
  const [selectedJobIds, setSelectedJobIds] = useState<Set<string>>(new Set());
  const [bulkLoading, setBulkLoading] = useState<string | null>(null);
  const [bulkMessage, setBulkMessage] = useState<{ type: "ok" | "err"; text: string } | null>(null);
  const selectAllRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    fetchConfig()
      .then((config) => setBooruUrl(config.booru_url || ""))
      .catch(() => {});
  }, []);

  useEffect(() => {
    setError(null);
    setSelectedJobIds(new Set());
    fetchJobs({
      status: statusFilter || undefined,
      offset: page * PAGE_SIZE,
      limit: PAGE_SIZE,
    })
      .then((d) => {
        setData(d);
        setError(null);
      })
      .catch((e: Error) => setError(e.message));
  }, [statusFilter, page]);

  useJobUpdates((payload: Record<string, unknown>) => {
    const id = String(payload.id ?? payload.job_id ?? "");
    if (!id) return;
    const updatedJob = { ...payload, id } as JobSummary;
    const status = String(payload.status ?? "").toLowerCase();
    const hasTerminalStatus =
      status === "completed" || status === "merged" || status === "failed";

    setData((prevData) => {
      if (!prevData) return prevData;
      const index = prevData.results.findIndex((j) => j.id === id);
      if (index >= 0) {
        const existing = prevData.results[index];
        const prevStatus = existing?.status?.toLowerCase();
        const statusChanged = prevStatus != null && prevStatus !== status;

        // Refetch full job on terminal status or status change to ensure accurate state
        if (hasTerminalStatus || statusChanged) {
          fetchJob(id)
            .then((fullJob) => {
              setData((current) => {
                if (!current) return current;
                const idx = current.results.findIndex((j) => j.id === id);
                if (idx >= 0) {
                  const newResults = [...current.results];
                  newResults[idx] = fullJob as JobSummary;
                  return { ...current, results: newResults };
                }
                return current;
              });
            })
            .catch((e: Error) => {
              console.error(`Failed to refetch job ${id} after SSE update:`, e.message);
              // Fallback: at least update with SSE payload
              const newResults = [...prevData.results];
              newResults[index] = { ...existing, ...updatedJob };
              setData({ ...prevData, results: newResults });
            });
          return prevData; // Return unchanged while fetching
        }

        const newResults = [...prevData.results];
        newResults[index] = { ...existing, ...updatedJob };
        return { ...prevData, results: newResults };
      }
      // Job not in the current page; try to fetch and insert it if visible to this user
      fetchJob(id)
        .then((fullJob) => {
          setData((current) => {
            if (!current) return current;
            const exists = current.results.some((j) => j.id === id);
            if (exists) return current;

            // Respect current status filter if present
            if (statusFilter && fullJob.status !== statusFilter) {
              return current;
            }

            const results = [{ ...(fullJob as JobSummary), ...updatedJob }, ...current.results].slice(
              0,
              PAGE_SIZE
            );
            return { ...current, results, total: current.total + 1 };
          });
        })
        .catch((e: Error) => {
          // If the job is not visible (e.g. belongs to another user), ignore the update
          console.debug(`Ignoring SSE for job ${id} (not visible or error):`, e.message);
        });
      return prevData;
    });
  });

  function setFilter(s: string) {
    const p = new URLSearchParams(searchParams);
    if (s) p.set("status", s);
    else p.delete("status");
    p.set("page", "0");
    setSearchParams(p);
  }

  function setPage(n: number) {
    const p = new URLSearchParams(searchParams);
    p.set("page", String(n));
    setSearchParams(p);
  }

  async function handleJobAction(
    jobId: string,
    action: string,
    actionFn: (id: string) => Promise<Job>
  ) {
    setLoadingActions((prev) => ({ ...prev, [`${jobId}-${action}`]: true }));
    try {
      const updatedJob = await actionFn(jobId);
      setData((prevData) => {
        if (!prevData) return prevData;
        const index = prevData.results.findIndex((j) => j.id === jobId);
        if (index >= 0) {
          const newResults = [...prevData.results];
          newResults[index] = updatedJob;
          return { ...prevData, results: newResults };
        }
        return prevData;
      });
    } catch (e) {
      console.error(`Failed to ${action} job ${jobId}:`, (e as Error).message);
    } finally {
      setLoadingActions((prev) => ({ ...prev, [`${jobId}-${action}`]: false }));
    }
  }

  async function handleDeleteJob(jobId: string) {
    if (!confirm("Are you sure you want to delete this job?")) return;
    setLoadingActions((prev) => ({ ...prev, [`${jobId}-delete`]: true }));
    try {
      await deleteJob(jobId);
      setData((prevData) => {
        if (!prevData) return prevData;
        return {
          ...prevData,
          results: prevData.results.filter((j) => j.id !== jobId),
          total: Math.max(0, prevData.total - 1),
        };
      });
    } catch (e) {
      console.error(`Failed to delete job ${jobId}:`, (e as Error).message);
    } finally {
      setLoadingActions((prev) => ({ ...prev, [`${jobId}-delete`]: false }));
    }
  }

  const pageJobIds = data?.results?.map((j) => j.id) ?? [];
  const allSelectedOnPage =
    pageJobIds.length > 0 && pageJobIds.every((id) => selectedJobIds.has(id));

  useEffect(() => {
    const el = selectAllRef.current;
    if (!el) return;
    el.indeterminate = selectedJobIds.size > 0 && !allSelectedOnPage;
  }, [selectedJobIds.size, allSelectedOnPage]);

  function toggleSelection(jobId: string) {
    setSelectedJobIds((prev) => {
      const next = new Set(prev);
      if (next.has(jobId)) next.delete(jobId);
      else next.add(jobId);
      return next;
    });
  }

  function toggleSelectAllOnPage() {
    if (allSelectedOnPage) {
      setSelectedJobIds((prev) => {
        const next = new Set(prev);
        pageJobIds.forEach((id) => next.delete(id));
        return next;
      });
    } else {
      setSelectedJobIds((prev) => new Set([...prev, ...pageJobIds]));
    }
  }

  async function handleBulkAction(
    action: "retry" | "delete" | "start" | "pause" | "stop" | "resume"
  ) {
    const ids = Array.from(selectedJobIds);
    if (ids.length === 0) return;
    if (action === "delete" && !confirm(`Delete ${ids.length} job(s)? This cannot be undone.`))
      return;

    setBulkMessage(null);
    setBulkLoading(action);

    const bulkFn =
      action === "retry"
        ? bulkRetryJobs
        : action === "delete"
          ? bulkDeleteJobs
          : action === "start"
            ? bulkStartJobs
            : action === "pause"
              ? bulkPauseJobs
              : action === "stop"
                ? bulkStopJobs
                : bulkResumeJobs;

    try {
      const result = await bulkFn(ids);
      const n = result.job_ids.length;
      setBulkMessage({
        type: "ok",
        text: `Bulk ${result.action} accepted for ${n} job(s). Updates will appear shortly.`,
      });
      setSelectedJobIds(new Set());
      setData((prev) => {
        if (!prev) return prev;
        if (action === "delete") {
          const removed = new Set(result.job_ids);
          return {
            ...prev,
            results: prev.results.filter((j) => !removed.has(j.id)),
            total: Math.max(0, prev.total - removed.size),
          };
        }
        return prev;
      });
      if (action !== "delete" && ids.length > 0) {
        fetchJobs({
          status: statusFilter || undefined,
          offset: page * PAGE_SIZE,
          limit: PAGE_SIZE,
        })
          .then(setData)
          .catch((e: Error) => console.error("Refetch after bulk:", e.message));
      }
    } catch (e: Error) {
      setBulkMessage({ type: "err", text: (e as Error).message });
    } finally {
      setBulkLoading(null);
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
      case "failed":
        return (
          <>
            <button
              className="btn btn-warning btn-sm"
              onClick={() => handleJobAction(id, "retry", retryJob)}
              disabled={isLoading("retry")}
              title="Retry job"
            >
              {isLoading("retry") ? "..." : <RefreshCcw size={14} />}
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
      default:
        return null;
    }
  }

  if (!data && !error) return <p>Loading...</p>;

  const totalPages = data ? Math.ceil(data.total / PAGE_SIZE) : 0;

  return (
    <>
      {error && (
        <div
          style={{
            marginBottom: "1rem",
            padding: "0.75rem 1rem",
            background: "rgba(248, 113, 113, 0.15)",
            border: "1px solid var(--red)",
            borderRadius: 8,
            color: "var(--red)",
          }}
        >
          {error}
          {data ? " Showing last loaded results." : ""}
        </div>
      )}
      <div className="filters filter-pills">
        {STATUS_FILTER_ORDER.map(({ value, label, icon }) => {
          const isActive = statusFilter === value;
          return (
            <button
              key={value || "all"}
              type="button"
              className={`filter-pill badge ${value ? value : "all"} ${isActive ? "active" : ""}`}
              onClick={() => setFilter(value)}
            >
              {icon && <span className="badge-icon">{icon}</span>}
              {label}
            </button>
          );
        })}
      </div>

      {selectedJobIds.size > 0 && (
        <div
          className="card"
          style={{
            marginBottom: "0.75rem",
            padding: "0.5rem 1rem",
            display: "flex",
            alignItems: "center",
            flexWrap: "wrap",
            gap: "0.75rem",
          }}
        >
          <span style={{ fontWeight: 600, fontSize: "0.9rem" }}>
            {selectedJobIds.size} selected
          </span>
          <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
            {statusFilter === "failed" && (
              <button
                type="button"
                className="btn btn-warning btn-sm"
                onClick={() => handleBulkAction("retry")}
                disabled={!!bulkLoading}
                title="Retry selected jobs"
              >
                {bulkLoading === "retry" ? "..." : <RefreshCcw size={14} />} Retry
              </button>
            )}
            {statusFilter === "pending" && (
              <button
                type="button"
                className="btn btn-success btn-sm"
                onClick={() => handleBulkAction("start")}
                disabled={!!bulkLoading}
                title="Start selected jobs"
              >
                {bulkLoading === "start" ? "..." : <Play size={14} />} Start
              </button>
            )}
            {(statusFilter === "downloading" ||
              statusFilter === "tagging" ||
              statusFilter === "uploading") && (
              <>
                <button
                  type="button"
                  className="btn btn-warning btn-sm"
                  onClick={() => handleBulkAction("pause")}
                  disabled={!!bulkLoading}
                  title="Pause selected jobs"
                >
                  {bulkLoading === "pause" ? "..." : <Pause size={14} />} Pause
                </button>
                <button
                  type="button"
                  className="btn btn-danger btn-sm"
                  onClick={() => handleBulkAction("stop")}
                  disabled={!!bulkLoading}
                  title="Stop selected jobs"
                >
                  {bulkLoading === "stop" ? "..." : <Square size={14} />} Stop
                </button>
              </>
            )}
            {(statusFilter === "paused" || statusFilter === "stopped") && (
              <button
                type="button"
                className="btn btn-success btn-sm"
                onClick={() => handleBulkAction("resume")}
                disabled={!!bulkLoading}
                title="Resume selected jobs"
              >
                {bulkLoading === "resume" ? "..." : <Play size={14} />} Resume
              </button>
            )}
            <button
              type="button"
              className="btn btn-danger btn-sm"
              onClick={() => handleBulkAction("delete")}
              disabled={!!bulkLoading}
              title="Delete selected jobs"
            >
              {bulkLoading === "delete" ? "..." : <Trash2 size={14} />} Delete
            </button>
          </div>
          <button
            type="button"
            className="btn btn-sm"
            style={{ marginLeft: "auto" }}
            onClick={() => {
              setSelectedJobIds(new Set());
              setBulkMessage(null);
            }}
          >
            Clear selection
          </button>
          {bulkMessage && (
            <span
              style={{
                width: "100%",
                fontSize: "0.85rem",
                color: bulkMessage.type === "err" ? "var(--red)" : "var(--green)",
              }}
            >
              {bulkMessage.text}
            </span>
          )}
        </div>
      )}

      <div className="card">
        {!data ? (
          <p style={{ color: "var(--text-muted)" }}>No job list loaded. Try changing the filter or refresh.</p>
        ) : (
        <table>
          <thead>
            <tr>
              <th style={{ width: 36 }}>
                <input
                  ref={selectAllRef}
                  type="checkbox"
                  checked={allSelectedOnPage}
                  onChange={toggleSelectAllOnPage}
                  title="Select all on this page"
                />
              </th>
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
            {data.results.map((j) => {
              const sources = getJobSources(j);
              const maxVisible = 2;
              const visible = sources.slice(0, maxVisible);
              const extra = sources.length - maxVisible;
              const truncate = (s: string) => (s.length > 30 ? s.substring(0, 30) + "..." : s);
              return (
                <tr key={j.id}>
                  <td style={{ verticalAlign: "middle" }}>
                    <input
                      type="checkbox"
                      checked={selectedJobIds.has(j.id)}
                      onChange={() => toggleSelection(j.id)}
                      title="Select job"
                    />
                  </td>
                  <td>
                    <StatusBadge status={j.status} />
                  </td>
                  <td>{j.job_type}</td>
                  <td>{j.dashboard_username || "-"}</td>
                  <td>
                    {sources.length > 0 ? (
                      <div className="source-cell" title={sources.join("\n")}>
                        <div className="multi-source">
                          {visible[0] && (
                            <a
                              href={visible[0]}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="source-link"
                            >
                              {truncate(visible[0])}
                            </a>
                          )}
                          {visible.length > 1 ? (
                            <span className="source-row">
                              <a
                                href={visible[1]}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="source-link"
                              >
                                {truncate(visible[1])}
                              </a>
                              {extra > 0 && <span className="source-count">+{extra}</span>}
                            </span>
                          ) : extra > 0 ? (
                            <span className="source-count">+{extra}</span>
                          ) : null}
                        </div>
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
                        {(() => {
                          const allIds = Array.from(
                            new Set(
                              [
                                j.post?.id ?? j.szuru_post_id,
                                ...((j.post?.relations ?? j.related_post_ids) ?? []),
                              ].filter((id): id is number => id != null)
                            )
                          );
                          const maxVisible = 3;
                          const visible = allIds.slice(0, maxVisible);
                          const remaining = allIds.length - maxVisible;
                          return (
                            <>
                              {visible.map((id, idx) => (
                                <span key={id}>
                                  {idx > 0 && " "}
                                  <a
                                    href={`${booruUrl}/post/${id}`}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="post-link"
                                  >
                                    #{id}
                                  </a>
                                </span>
                              ))}
                              {remaining > 0 && (
                                <span className="related-posts"> +{remaining}</span>
                              )}
                            </>
                          );
                        })()}
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
            {data.results.length === 0 && (
              <tr>
                <td colSpan={9} style={{ textAlign: "center", color: "var(--text-muted)" }}>
                  No jobs found.
                </td>
              </tr>
            )}
          </tbody>
        </table>
        )}
      </div>

      {totalPages > 1 && (
        <div className="pagination">
          <button disabled={page === 0} onClick={() => setPage(page - 1)}>
            Prev
          </button>
          <span style={{ lineHeight: "2rem", fontSize: "0.85rem", color: "var(--text-muted)" }}>
            Page {page + 1} of {totalPages}
          </span>
          <button
            disabled={page >= totalPages - 1}
            onClick={() => setPage(page + 1)}
          >
            Next
          </button>
        </div>
      )}
    </>
  );
}
