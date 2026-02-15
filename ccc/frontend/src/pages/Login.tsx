import { useState, FormEvent } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { fetchStats, setDashboardAuth } from "../api";

export default function Login() {
  const [user, setUser] = useState("");
  const [pass, setPass] = useState("");
  const [error, setError] = useState("");
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: { pathname?: string } } | null)?.from?.pathname || "/";

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    const basic = btoa(unescape(encodeURIComponent(user + ":" + pass)));
    setDashboardAuth(basic);
    fetchStats()
      .then(() => navigate(from, { replace: true }))
      .catch((err: Error) => {
        setDashboardAuth(null);
        setError(err.message || "Login failed.");
      });
  }

  return (
    <div className="login-page">
      <div className="login-hero">
        <img src="/assets/reimu.jpg" alt="" className="login-hero-img" />
      </div>
      <div className="card login-card">
        <h2 style={{ marginBottom: "1rem" }}>Log in</h2>
        <form onSubmit={handleSubmit}>
          <div style={{ marginBottom: "0.75rem" }}>
            <label htmlFor="login-user" style={{ display: "block", marginBottom: 4 }}>
              Username
            </label>
            <input
              id="login-user"
              type="text"
              value={user}
              onChange={(e) => setUser(e.target.value)}
              autoComplete="username"
              required
              style={{ width: "100%", padding: 8 }}
            />
          </div>
          <div style={{ marginBottom: "1rem" }}>
            <label htmlFor="login-pass" style={{ display: "block", marginBottom: 4 }}>
              Password
            </label>
            <input
              id="login-pass"
              type="password"
              value={pass}
              onChange={(e) => setPass(e.target.value)}
              autoComplete="current-password"
              required
              style={{ width: "100%", padding: 8 }}
            />
          </div>
          {error && (
            <p style={{ color: "var(--red)", marginBottom: "0.75rem" }}>{error}</p>
          )}
          <button type="submit">Log in</button>
        </form>
      </div>
    </div>
  );
}
