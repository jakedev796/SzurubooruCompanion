import { Link } from "react-router-dom";

export default function SzuruConfigRequired() {
  return (
    <div className="card" style={{ marginBottom: "1.5rem" }}>
      <p style={{ marginBottom: "0.75rem", color: "var(--text)" }}>
        Configure your Szurubooru connection in Settings to see your jobs and stats.
      </p>
      <Link to="/settings" className="btn btn-primary">
        Go to Settings
      </Link>
    </div>
  );
}
