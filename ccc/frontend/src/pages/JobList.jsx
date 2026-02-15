import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { fetchJobs, fetchConfig, startJob, pauseJob, stopJob, deleteJob, resumeJob } from "../api";
import { useJobUpdates } from "../hooks/useJobUpdates";

const PAGE_SIZE = 50;

function StatusBadge({ status }) {
  return <span className={`badge ${status}`}>{status}</span>;
}

function formatDate(iso) {
  if (!iso) return "-";
  const d = new Date(iso);
  return d.toLocaleString();
}

export default function JobList() {
  const [searchParams, setSearchParams] = useSearchParams();
  const statusFilter = searchParams.get("status") || "";
  const page = parseInt(searchParams.get("page") || "0", 10);

  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [booruUrl, setBooruUrl] = useState("");
  const [loadingActions, setLoadingActions] = useState({});

  useEffect(() => {
    fetchConfig()
      .then((config) => setBooruUrl(config.booru_url || ""))
      .catch(() => {}); // Silently fail if config unavailable
  }, []);

  useEffect(() => {
    fetchJobs({ status: statusFilter || undefined, offset: page * PAGE_SIZE, limit: PAGE_SIZE })
      .then(setData)
      .catch((e) => setError(e.message));
  }, [statusFilter, page]);

  useJobUpdates((updatedJob) => {
    setData((prevData) => {
      if (!prevData) return prevData;
      const index = prevData.results.findIndex((j) => j.id === updatedJob.id);
      if (index >= 0) {
        const newResults = [...prevData.results];
        newResults[index] = updatedJob;
        return { ...prevData, results: newResults };
      }
      // New job, add to list if no status filter or matches filter
      if (!statusFilter || updatedJob.status === statusFilter) {
        return { ...prevData, results: [updatedJob, ...prevData.results], total: prevData.total + 1 };
      }
      return prevData;
    });
  });

  function setFilter(s) {
    const p = new URLSearchParams(searchParams);
    if (s) p.set("status", s);
    else p.delete("status");
    p.set("page", "0");
    setSearchParams(p);
  }
  function setPage(n) {
    const p = new URLSearchParams(searchParams);
    p.set("page", String(n));
    setSearchParams(p);
  }

  async function handleJobAction(jobId, action, actionFn) {
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
      console.error(`Failed to ${action} job ${jobId}:`, e.message);
    } finally {
      setLoadingActions((prev) => ({ ...prev, [`${jobId}-${action}`]: false }));
    }
  }

  async function handleDeleteJob(jobId) {
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
      console.error(`Failed to delete job ${jobId}:`, e.message);
    } finally {
      setLoadingActions((prev) => ({ ...prev, [`${jobId}-delete`]: false }));
    }
  }

  function getQuickActions(job) {
    const { id, status } = job;
    const isLoading = (action) => loadingActions[`${id}-${action}`];
    
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
              {isLoading("start") ? "..." : "▶"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : "✕"}
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
              {isLoading("pause") ? "..." : "⏸"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleJobAction(id, "stop", stopJob)}
              disabled={isLoading("stop")}
              title="Stop job"
            >
              {isLoading("stop") ? "..." : "⏹"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : "✕"}
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
              {isLoading("resume") ? "..." : "▶"}
            </button>
            <button
              className="btn btn-danger btn-sm"
              onClick={() => handleDeleteJob(id)}
              disabled={isLoading("delete")}
              title="Delete job"
            >
              {isLoading("delete") ? "..." : "✕"}
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
            {isLoading("delete") ? "..." : "✕"}
          </button>
        );
      default:
        return null;
    }
  }

  if (error) return <p style={{ color: "var(--red)" }}>Error: {error}</p>;
  if (!data) return <p>Loading...</p>;

  const totalPages = Math.ceil(data.total / PAGE_SIZE);

  return (
    <>
      <div className="filters">
        <select value={statusFilter} onChange={(e) => setFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="pending">Pending</option>
          <option value="downloading">Downloading</option>
          <option value="tagging">Tagging</option>
          <option value="uploading">Uploading</option>
          <option value="paused">Paused</option>
          <option value="stopped">Stopped</option>
          <option value="completed">Completed</option>
          <option value="failed">Failed</option>
        </select>
      </div>

      <div className="card">
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
            {data.results.map((j) => {
              const sources = j.url ? j.url.split('\n') : [];
              const hasMultipleSources = sources.length > 1;
              const firstSource = sources[0] || j.original_filename;
              
              return (
                <tr key={j.id}>
                  <td><StatusBadge status={j.status} /></td>
                  <td>{j.job_type}</td>
                  <td>
                    {j.url ? (
                      <div className="source-cell" title={j.url}>
                        {hasMultipleSources ? (
                          <span className="multi-source">
                            <a href={firstSource} target="_blank" rel="noopener noreferrer" className="source-link">
                              {firstSource.length > 30 ? firstSource.substring(0, 30) + '...' : firstSource}
                            </a>
                            <span className="source-count"> +{sources.length - 1} more</span>
                          </span>
                        ) : (
                          <a href={firstSource} target="_blank" rel="noopener noreferrer" className="source-link">
                            {firstSource.length > 30 ? firstSource.substring(0, 30) + '...' : firstSource}
                          </a>
                        )}
                      </div>
                    ) : j.original_filename ? (
                      <span>{j.original_filename}</span>
                    ) : "-"}
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
                        {j.related_post_ids && j.related_post_ids.length > 0 && (
                          <span className="related-posts" title={`Related: ${j.related_post_ids.map(id => `#${id}`).join(', ')}`}>
                            {' '}+{j.related_post_ids.length}
                          </span>
                        )}
                      </span>
                    ) : "-"}
                  </td>
                  <td>{formatDate(j.created_at)}</td>
                  <td>
                    <div className="quick-actions" style={{ display: "flex", gap: "0.25rem" }}>
                      {getQuickActions(j)}
                    </div>
                  </td>
                  <td><Link to={`/jobs/${j.id}`}>details</Link></td>
                </tr>
              );
            })}
            {data.results.length === 0 && (
              <tr><td colSpan={7} style={{ textAlign: "center", color: "var(--text-muted)" }}>No jobs found.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {totalPages > 1 && (
        <div className="pagination">
          <button disabled={page === 0} onClick={() => setPage(page - 1)}>
            Prev
          </button>
          <span style={{ lineHeight: "2rem", fontSize: "0.85rem", color: "var(--text-muted)" }}>
            Page {page + 1} of {totalPages}
          </span>
          <button disabled={page >= totalPages - 1} onClick={() => setPage(page + 1)}>
            Next
          </button>
        </div>
      )}
    </>
  );
}
