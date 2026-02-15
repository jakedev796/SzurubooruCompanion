import { useEffect, useState } from "react";
import { Routes, Route, Navigate, useNavigate, useLocation, Link, NavLink } from "react-router-dom";
import JobList from "./pages/JobList";
import JobDetail from "./pages/JobDetail";
import Dashboard from "./pages/Dashboard";
import Login from "./pages/Login";
import { fetchConfig, setDashboardAuth } from "./api";

function hasDashboardAuth(): boolean {
  return typeof sessionStorage !== "undefined" && !!sessionStorage.getItem("dashboard_basic");
}

export default function App() {
  const [authRequired, setAuthRequired] = useState(false);
  const [configLoaded, setConfigLoaded] = useState(false);
  const navigate = useNavigate();
  const location = useLocation();

  useEffect(() => {
    fetchConfig()
      .then((c) => {
        setAuthRequired(!!c.auth_required);
        setConfigLoaded(true);
      })
      .catch(() => setConfigLoaded(true));
  }, []);

  function handleLogout() {
    setDashboardAuth(null);
    navigate("/login", { replace: true });
  }

  const loggedIn = hasDashboardAuth();
  const onLoginPage = location.pathname === "/login";

  if (!configLoaded) {
    return (
      <div className="app-shell">
        <p style={{ color: "var(--text-muted)" }}>Loading...</p>
      </div>
    );
  }

  if (authRequired && !loggedIn && !onLoginPage) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if (onLoginPage && loggedIn) {
    return <Navigate to="/" replace />;
  }

  return (
    <div className="app-shell">
      {!onLoginPage && (
        <header>
          <Link to="/" className="header-brand">
            <img src="/assets/32.png" alt="" className="header-logo" />
            <h1>SzuruCompanion Dashboard</h1>
          </Link>
          <nav>
            <NavLink to="/" end className={({ isActive }) => (isActive ? "active" : "")}>
              Home
            </NavLink>
            <NavLink to="/jobs" className={({ isActive }) => (isActive ? "active" : "")}>
              Jobs
            </NavLink>
            {authRequired && loggedIn && (
              <button type="button" onClick={handleLogout} className="logout-btn">
                Log out
              </button>
            )}
          </nav>
        </header>
      )}
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/login" element={<Login />} />
        <Route path="/jobs" element={<JobList />} />
        <Route path="/jobs/:id" element={<JobDetail />} />
      </Routes>
    </div>
  );
}
