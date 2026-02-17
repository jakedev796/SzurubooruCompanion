import { useEffect, useState } from "react";
import { Routes, Route, Navigate, useNavigate, useLocation, Link, NavLink } from "react-router-dom";
import { LogOut } from "lucide-react";
import JobList from "./pages/JobList";
import JobDetail from "./pages/JobDetail";
import Dashboard from "./pages/Dashboard";
import Login from "./pages/Login";
import Settings from "./pages/Settings";
import { fetchConfig, setDashboardAuth } from "./api";
import { AuthProvider, useAuth } from "./contexts/AuthContext";
import { ToastProvider } from "./contexts/ToastContext";

function hasDashboardAuth(): boolean {
  return typeof sessionStorage !== "undefined" && !!sessionStorage.getItem("dashboard_basic");
}

function AppContent() {
  const [authRequired, setAuthRequired] = useState(false);
  const [configLoaded, setConfigLoaded] = useState(false);
  const navigate = useNavigate();
  const location = useLocation();
  const auth = useAuth();

  // Compute before useEffect so it can be used as a dependency
  const loggedIn = hasDashboardAuth() || !!auth.user;
  const onLoginPage = location.pathname === "/login";

  useEffect(() => {
    fetchConfig()
      .then((c) => {
        setAuthRequired(!!c.auth_required);
        setConfigLoaded(true);
      })
      .catch(() => setConfigLoaded(true));
  }, [loggedIn]);

  function handleLogout() {
    setDashboardAuth(null);
    auth.logout();
    navigate("/login", { replace: true });
  }

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
            {auth.user && (
              <NavLink to="/settings" className={({ isActive }) => (isActive ? "active" : "")}>
                Settings
              </NavLink>
            )}
            {auth.user && (
              <button type="button" onClick={handleLogout} className="logout-btn" title="Log out">
                <LogOut size={18} />
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
        <Route path="/settings" element={<Settings />} />
      </Routes>
    </div>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <ToastProvider>
        <AppContent />
      </ToastProvider>
    </AuthProvider>
  );
}
