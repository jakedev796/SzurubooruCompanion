import { useState, FormEvent } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useAuth } from "../contexts/AuthContext";
import { useToast } from "../contexts/ToastContext";

export default function Login() {
  const [user, setUser] = useState("");
  const [pass, setPass] = useState("");
  const { login } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: { pathname?: string } } | null)?.from?.pathname || "/";

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    try {
      await login(user, pass);
      navigate(from, { replace: true });
    } catch (err: any) {
      showToast(err.message || "Login failed", "error");
    }
  }

  return (
    <div className="login-page">
      <div className="login-hero">
        <img src="/assets/reimu.jpg" alt="" className="login-hero-img" />
        <blockquote className="login-quote">
          Hello slacker,
          <br />
          is it all right for you to slack around here?
          <cite>— Reimu</cite>
        </blockquote>
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
          <button type="submit">Log in</button>
        </form>
      </div>
    </div>
  );
}
