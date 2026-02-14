import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import { fetchJob } from "../api";

function formatDate(iso) {
  if (!iso) return "-";
  return new Date(iso).toLocaleString();
}

export default function JobDetail() {
  const { id } = useParams();
  const [job, setJob] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchJob(id)
      .then(setJob)
      .catch((e) => setError(e.message));
  }, [id]);

  if (error) return <p style={{ color: "var(--red)" }}>Error: {error}</p>;
  if (!job) return <p>Loading...</p>;

  return (
    <>
      <Link to="/jobs" style={{ fontSize: "0.85rem" }}>&larr; Back to jobs</Link>

      <div className="card" style={{ marginTop: "1rem" }}>
        <h3 style={{ marginBottom: "1rem" }}>
          Job <code style={{ fontSize: "0.85rem" }}>{job.id}</code>
        </h3>

        <dl className="detail-grid">
          <dt>Status</dt>
          <dd><span className={`badge ${job.status}`}>{job.status}</span></dd>

          <dt>Type</dt>
          <dd>{job.job_type}</dd>

          <dt>URL</dt>
          <dd>{job.url || "-"}</dd>

          <dt>Filename</dt>
          <dd>{job.original_filename || "-"}</dd>

          <dt>Safety</dt>
          <dd>{job.safety || "-"}</dd>

          <dt>Szuru Post ID</dt>
          <dd>{job.szuru_post_id ?? "-"}</dd>

          <dt>Tags from source</dt>
          <dd>
            {job.tags_from_source && job.tags_from_source.length > 0 ? (
              <span className="tag-list tag-list--source">
                {job.tags_from_source.map((t) => (
                  <span key={t} className="tag tag--source">{t}</span>
                ))}
              </span>
            ) : "-"}
          </dd>

          <dt>Tags from AI</dt>
          <dd>
            {job.tags_from_ai && job.tags_from_ai.length > 0 ? (
              <span className="tag-list tag-list--ai">
                {job.tags_from_ai.map((t) => (
                  <span key={t} className="tag tag--ai">{t}</span>
                ))}
              </span>
            ) : "-"}
          </dd>

          {(!job.tags_from_source?.length && !job.tags_from_ai?.length) && job.tags_applied?.length > 0 && (
            <>
              <dt>Tags applied</dt>
              <dd>{job.tags_applied.join(", ")}</dd>
            </>
          )}

          <dt>Error</dt>
          <dd style={{ color: job.error_message ? "var(--red)" : undefined }}>
            {job.error_message || "-"}
          </dd>

          <dt>Retries</dt>
          <dd>{job.retry_count}</dd>

          <dt>Created</dt>
          <dd>{formatDate(job.created_at)}</dd>

          <dt>Updated</dt>
          <dd>{formatDate(job.updated_at)}</dd>
        </dl>
      </div>
    </>
  );
}
