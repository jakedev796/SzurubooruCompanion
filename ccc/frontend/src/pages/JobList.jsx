import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { fetchJobs } from "../api";

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

  useEffect(() => {
    fetchJobs({ status: statusFilter || undefined, offset: page * PAGE_SIZE, limit: PAGE_SIZE })
      .then(setData)
      .catch((e) => setError(e.message));
  }, [statusFilter, page]);

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
              <th></th>
            </tr>
          </thead>
          <tbody>
            {data.results.map((j) => (
              <tr key={j.id}>
                <td><StatusBadge status={j.status} /></td>
                <td>{j.job_type}</td>
                <td style={{ maxWidth: 300, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {j.url || j.original_filename || "-"}
                </td>
                <td>{j.szuru_post_id ?? "-"}</td>
                <td>{formatDate(j.created_at)}</td>
                <td><Link to={`/jobs/${j.id}`}>details</Link></td>
              </tr>
            ))}
            {data.results.length === 0 && (
              <tr><td colSpan={6} style={{ textAlign: "center", color: "var(--text-muted)" }}>No jobs found.</td></tr>
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
