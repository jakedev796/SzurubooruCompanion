import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { Play, Pause, Square, Trash2 } from "lucide-react";
import {
  fetchJobs,
  fetchJob,
  fetchConfig,
  startJob,
  pauseJob,
  stopJob,
  deleteJob,
  resumeJob,
  getJobSources,
  type Job,
  type JobSummary,
  type JobsResponse,
} from "../api";
import { useJobUpdates } from "../hooks/useJobUpdates";

const PAGE_SIZE = 20;

function StatusBadge({ status }: { status: string }) {
  return <span className={`badge ${status}`}>{status}</span>;
}

function formatDate(iso: string | undefined): string {
  if (!iso) return "-";
  return new Date(iso).toLocaleString();
}

export default function JobList({ szuruUser }: { szuruUser?: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const statusFilter = searchParams.get("status") || "";
  const page = parseInt(searchParams.get("page") || "0", 10);

  const [data, setData] = useState<JobsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [booruUrl, setBooruUrl] = useState("");
  const [loadingActions, setLoadingActions] = useState<Record<string, boolean>>({});

  useEffect(() => {
    fetchConfig()
      .then((config) => setBooruUrl(config.booru_url || ""))
      .catch(() => {});
  }, []);

  useEffect(() => {
    setError(null);
    fetchJobs({
      status: statusFilter || undefined,
      szuru_user: szuruUser || undefined,
      offset: page * PAGE_SIZE,
      limit: PAGE_SIZE,
    })
      .then((d) => {
        setData(d);
        setError(null);
      })
      .catch((e: Error) => setError(e.message));
  }, [statusFilter, szuruUser, page]);

  useJobUpdates((payload: Record<string, unknown>) => {
    const id = (payload.id ?? payload.job_id) as number;
    const updatedJob = { ...payload, id } as JobSummary;

    setData((prevData) => {
      if (!prevData) return prevData;
      const index = prevData.results.findIndex((j) => String(j.id) === String(id));
      if (index >= 0) {
        const newResults = [...prevData.results];
        newResults[index] = { ...prevData.results[index], ...updatedJob };
        return { ...prevData, results: newResults };
      }
      if (!statusFilter || updatedJob.status === statusFilter) {
        fetchJob(String(id))
          .then((fullJob) => {
            setData((prev) => {
              if (!prev) return prev;
              const idx = prev.results.findIndex((j) => String(j.id) === String(id));
              if (idx >= 0) return prev;
              return {
                ...prev,
                results: [{ ...fullJob, ...updatedJob }, ...prev.results],
                total: prev.total + 1,
              };
            });
          })
          .catch(() => {});
      }
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
    jobId: number,
    action: string,
    actionFn: (id: number) => Promise<Job>
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

  async function handleDeleteJob(jobId: number) {
    if (!confirm("Are you sure you want to delete this job?")) return;
    setLoadingActions((prev) => ({ ...prev, [`${jobId}-delete`]: true }));
    try {
      await deleteJob(jobId);
      setData((prevData) => {
        if (!prevData) return prevData;
        return {
          ...prevData,
          results: prevData.results.filter((j) => j.id !== jobId),
          total: prevData.total - 1,
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
        {[
          { value: "", label: "All statuses" },
          { value: "pending", label: "Pending" },
          { value: "downloading", label: "Downloading" },
          { value: "tagging", label: "Tagging" },
          { value: "uploading", label: "Uploading" },
          { value: "paused", label: "Paused" },
          { value: "stopped", label: "Stopped" },
          { value: "completed", label: "Completed" },
          { value: "merged", label: "Merged" },
          { value: "failed", label: "Failed" },
        ].map(({ value, label }) => {
          const isActive = statusFilter === value;
          return (
            <button
              key={value || "all"}
              type="button"
              className={`filter-pill badge ${value ? value : "all"} ${isActive ? "active" : ""}`}
              onClick={() => setFilter(value)}
            >
              {label}
            </button>
          );
        })}
      </div>

      <div className="card">
        {!data ? (
          <p style={{ color: "var(--text-muted)" }}>No job list loaded. Try changing the filter or refresh.</p>
        ) : (
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
            {data.results.map((j) => {
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
                  <td>{j.szuru_user || "-"}</td>
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
            {data.results.length === 0 && (
              <tr>
                <td colSpan={8} style={{ textAlign: "center", color: "var(--text-muted)" }}>
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
