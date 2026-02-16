import { useEffect, useState } from "react";
import { useParams, Link, useNavigate } from "react-router-dom";
import {
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
} from "../api";
import { useJobUpdates } from "../hooks/useJobUpdates";

function formatDate(iso: string | undefined): string {
  if (!iso) return "-";
  return new Date(iso).toLocaleString();
}

type ActionDef = {
  label: string;
  action: () => void;
  style: string;
};

export default function JobDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [job, setJob] = useState<Job | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [booruUrl, setBooruUrl] = useState("");
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    fetchConfig()
      .then((config) => setBooruUrl(config.booru_url || ""))
      .catch(() => {});
  }, []);

  useEffect(() => {
    if (!id) return;
    fetchJob(id)
      .then(setJob)
      .catch((e: Error) => setError(e.message));
  }, [id]);

  useJobUpdates((updatedJob: Record<string, unknown>) => {
    if (String(updatedJob.id) === id || String(updatedJob.job_id) === id) {
      setJob((prev) => (prev ? { ...prev, ...updatedJob } : (updatedJob as Job)));
    }
  }, id ?? null);

  async function handleAction(
    action: (jobId: number) => Promise<Job>,
    actionName: string
  ) {
    if (!id) return;
    setActionError(null);
    setActionLoading(actionName);
    try {
      const updatedJob = await action(Number(id));
      setJob(updatedJob);
    } catch (e) {
      setActionError((e as Error).message);
    } finally {
      setActionLoading(null);
    }
  }

  async function handleDelete() {
    if (!id) return;
    if (!confirm("Are you sure you want to delete this job?")) return;
    setActionError(null);
    setActionLoading("delete");
    try {
      await deleteJob(Number(id));
      navigate("/jobs");
    } catch (e) {
      setActionError((e as Error).message);
    } finally {
      setActionLoading(null);
    }
  }

  function getAvailableActions(status: string): ActionDef[] {
    switch (status) {
      case "pending":
        return [
          { label: "Start", action: () => handleAction(startJob, "start"), style: "btn-success" },
          { label: "Delete", action: handleDelete, style: "btn-danger" },
        ];
      case "downloading":
      case "tagging":
      case "uploading":
        return [
          { label: "Pause", action: () => handleAction(pauseJob, "pause"), style: "btn-warning" },
          { label: "Stop", action: () => handleAction(stopJob, "stop"), style: "btn-danger" },
          { label: "Delete", action: handleDelete, style: "btn-danger" },
        ];
      case "paused":
      case "stopped":
        return [
          {
            label: "Resume",
            action: () => handleAction(resumeJob, "resume"),
            style: "btn-success",
          },
          { label: "Delete", action: handleDelete, style: "btn-danger" },
        ];
      case "completed":
      case "merged":
      case "failed":
        return [{ label: "Delete", action: handleDelete, style: "btn-danger" }];
      default:
        return [];
    }
  }

  if (error) return <p style={{ color: "var(--red)" }}>Error: {error}</p>;
  if (!job) return <p>Loading...</p>;

  const sources = getJobSources(job);
  const postId = job.post?.id ?? job.szuru_post_id;
  const postRelations = job.post?.relations ?? job.related_post_ids ?? [];
  const postSafety = job.post?.safety ?? job.safety;
  const postTags = job.post?.tags ?? job.tags_applied;

  return (
    <>
      <Link to="/jobs" style={{ fontSize: "0.85rem" }}>
        &larr; Back to jobs
      </Link>

      <div className="card" style={{ marginTop: "1rem" }}>
        <h3 style={{ marginBottom: "1rem" }}>
          Job <code style={{ fontSize: "0.85rem" }}>{job.id}</code>
        </h3>

        {actionError && (
          <div
            className="action-error"
            style={{ color: "var(--red)", marginBottom: "1rem" }}
          >
            Error: {actionError}
          </div>
        )}

        <div
          className="job-actions"
          style={{
            marginBottom: "1rem",
            display: "flex",
            gap: "0.5rem",
            flexWrap: "wrap",
          }}
        >
          {getAvailableActions(job.status).map((btn, idx) => (
            <button
              key={idx}
              className={`btn ${btn.style}`}
              onClick={btn.action}
              disabled={actionLoading !== null}
              style={{ opacity: actionLoading ? 0.7 : 1 }}
            >
              {actionLoading === btn.label.toLowerCase()
                ? `${btn.label}ing...`
                : btn.label}
            </button>
          ))}
        </div>

        <dl className="detail-grid">
          <dt>Status</dt>
          <dd>
            <span className={`badge ${job.status}`}>{job.status}</span>
          </dd>

          <dt>Type</dt>
          <dd>{job.job_type}</dd>

          <dt>{sources.length > 1 ? "Sources" : "URL"}</dt>
          <dd>
            {sources.length > 0 ? (
              <div className="sources-section">
                <ul className="source-list">
                  {sources.map((url, idx) => (
                    <li key={idx}>
                      <a href={url} target="_blank" rel="noopener noreferrer">
                        {url}
                      </a>
                    </li>
                  ))}
                </ul>
              </div>
            ) : (
              "-"
            )}
          </dd>

          <dt>Filename</dt>
          <dd>{job.original_filename || "-"}</dd>

          <dt>Safety</dt>
          <dd>{postSafety || "-"}</dd>

          <dt>Szuru Post ID</dt>
          <dd>
            {postId != null ? (
              <span className="post-links">
                <a
                  href={`${booruUrl}/post/${postId}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="post-link"
                >
                  View Post #{postId}
                </a>
                {postRelations.length > 0 ? (
                  <span
                    className="related-posts"
                    style={{ marginLeft: "0.5rem", color: "var(--text-muted)" }}
                  >
                    (+{postRelations.length} related)
                  </span>
                ) : null}
              </span>
            ) : (
              "-"
            )}
          </dd>

          {postRelations.length > 0 ? (
            <>
              <dt>Related Posts</dt>
              <dd>
                <span className="related-post-list">
                  {postRelations.map((pid, idx) => (
                    <span key={pid}>
                      <a
                        href={`${booruUrl}/post/${pid}`}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        #{pid}
                      </a>
                      {idx < postRelations.length - 1 ? ", " : ""}
                    </span>
                  ))}
                </span>
              </dd>
            </>
          ) : null}

          <dt>Skip Tagging</dt>
          <dd>{job.skip_tagging ? "Yes" : "No"}</dd>

          <dt>Tags from source</dt>
          <dd>
            {job.tags_from_source?.length ? (
              <span className="tag-list tag-list--source">
                {sortTags(job.tags_from_source).map((t) => (
                  <span key={t} className="tag tag--source">
                    {t}
                  </span>
                ))}
              </span>
            ) : (
              "-"
            )}
          </dd>

          <dt>Tags from AI</dt>
          <dd>
            {job.tags_from_ai?.length ? (
              <span className="tag-list tag-list--ai">
                {sortTags(job.tags_from_ai).map((t) => (
                  <span key={t} className="tag tag--ai">
                    {t}
                  </span>
                ))}
              </span>
            ) : (
              "-"
            )}
          </dd>

          {postTags?.length ? (
            <>
              <dt>Tags (on Szurubooru)</dt>
              <dd>
                <p style={{ margin: 0, fontSize: "0.8rem", color: "var(--text-muted)", marginBottom: "0.35rem" }}>
                  Combined from source, AI, and metadata (applied to the post). Colors match origin above.
                </p>
                <span className="tag-list">
                  {sortTags(postTags).map((t) => {
                    const key = t.toLowerCase();
                    const fromSource = job.tags_from_source?.some((s) => s.toLowerCase() === key);
                    const fromAi = job.tags_from_ai?.some((s) => s.toLowerCase() === key);
                    const variant = fromSource ? "source" : fromAi ? "ai" : "other";
                    return (
                      <span key={t} className={`tag tag--${variant}`}>
                        {t}
                      </span>
                    );
                  })}
                </span>
              </dd>
            </>
          ) : null}

          <dt>Error</dt>
          <dd style={{ color: job.error_message ? "var(--red)" : undefined }}>
            {job.error_message || "-"}
          </dd>

          <dt>Retries</dt>
          <dd>{job.retry_count ?? "-"}</dd>

          <dt>Created</dt>
          <dd>{formatDate(job.created_at)}</dd>

          <dt>Updated</dt>
          <dd>{formatDate(job.updated_at)}</dd>
        </dl>
      </div>
    </>
  );
}
