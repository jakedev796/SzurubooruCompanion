import { useEffect, useState } from "react";
import { fetchStats } from "../api";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
} from "recharts";

export default function Dashboard() {
  const [stats, setStats] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchStats()
      .then(setStats)
      .catch((e) => setError(e.message));
  }, []);

  if (error) return <p style={{ color: "var(--red)" }}>Error: {error}</p>;
  if (!stats) return <p>Loading...</p>;

  const { total_jobs, by_status, daily_uploads } = stats;

  return (
    <>
      {/* Summary cards */}
      <div className="stat-grid">
        <div className="card stat-card">
          <div className="value">{total_jobs}</div>
          <div className="label">Total Jobs</div>
        </div>
        <div className="card stat-card">
          <div className="value">{by_status.completed || 0}</div>
          <div className="label">Completed</div>
        </div>
        <div className="card stat-card">
          <div className="value">{by_status.failed || 0}</div>
          <div className="label">Failed</div>
        </div>
        <div className="card stat-card">
          <div className="value">{by_status.pending || 0}</div>
          <div className="label">Pending</div>
        </div>
      </div>

      {/* Daily uploads chart */}
      <div className="card">
        <h3 style={{ marginBottom: "0.75rem" }}>Uploads – Last 30 Days</h3>
        {daily_uploads && daily_uploads.length > 0 ? (
          <div className="chart-container">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={daily_uploads}>
                <CartesianGrid strokeDasharray="3 3" stroke="#2a2d36" />
                <XAxis
                  dataKey="date"
                  tick={{ fill: "#71717a", fontSize: 11 }}
                  tickFormatter={(v) => v.slice(5)}
                />
                <YAxis tick={{ fill: "#71717a", fontSize: 11 }} allowDecimals={false} />
                <Tooltip
                  contentStyle={{
                    background: "#181a20",
                    border: "1px solid #2a2d36",
                    borderRadius: 6,
                  }}
                />
                <Bar dataKey="count" fill="#6366f1" radius={[3, 3, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        ) : (
          <p style={{ color: "var(--text-muted)" }}>No data yet.</p>
        )}
      </div>
    </>
  );
}
