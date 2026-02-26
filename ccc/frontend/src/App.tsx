import { useEffect, useState } from "react";
import { Routes, Route, Navigate, useNavigate, useLocation, Link, NavLink } from "react-router-dom";
import { LogOut } from "lucide-react";
import JobList from "./pages/JobList";
import JobDetail from "./pages/JobDetail";
import Dashboard from "./pages/Dashboard";
import Tagger from "./pages/Tagger";
import Login from "./pages/Login";
import Settings from "./pages/Settings";
import Onboarding from "./pages/Onboarding";
import { fetchConfig, fetchSetupStatus, fetchOnboardingStatus, setDashboardAuth } from "./api";
import { AuthProvider, useAuth } from "./contexts/AuthContext";
import { ToastProvider } from "./contexts/ToastContext";

function hasDashboardAuth(): boolean {
  return typeof sessionStorage !== "undefined" && !!sessionStorage.getItem("dashboard_basic");
}

function AppContent() {
  const [authRequired, setAuthRequired] = useState(false);
  const [configLoaded, setConfigLoaded] = useState(false);
  const [needsSetup, setNeedsSetup] = useState<boolean | null>(null);
  const [onboardingComplete, setOnboardingComplete] = useState<boolean | null>(null);
  const navigate = useNavigate();
  const location = useLocation();
  const auth = useAuth();

  // Compute before useEffect so it can be used as a dependency
  const loggedIn = hasDashboardAuth() || !!auth.user;
  const onLoginPage = location.pathname === "/login";
  const onOnboardingPage = location.pathname.startsWith("/onboarding");

  // Step 1: Check setup status, then load config if setup is done
  useEffect(() => {
    fetchSetupStatus()
      .then((s) => {
        if (s.needs_setup) {
          setNeedsSetup(true);
          setConfigLoaded(true);
        } else {
          setNeedsSetup(false);
          fetchConfig()
            .then((c) => {
              setAuthRequired(!!c.auth_required);
              setConfigLoaded(true);
            })
            .catch(() => setConfigLoaded(true));
        }
      })
      .catch(() => {
        // If setup status check fails, fall back to loading config directly
        setNeedsSetup(false);
        fetchConfig()
          .then((c) => {
            setAuthRequired(!!c.auth_required);
            setConfigLoaded(true);
          })
          .catch(() => setConfigLoaded(true));
      });
  }, [loggedIn]);

  // Step 2: When logged in and setup is done, check user onboarding status
  useEffect(() => {
    if (!loggedIn || needsSetup !== false) return;
    fetchOnboardingStatus()
      .then((s) => setOnboardingComplete(s.onboarding_complete))
      .catch(() => setOnboardingComplete(null));
  }, [loggedIn, needsSetup]);

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

  // First-time setup: redirect to onboarding
  if (needsSetup && !onOnboardingPage) {
    return <Navigate to="/onboarding" replace />;
  }

  // Auth redirect (skip if on onboarding pages)
  if (authRequired && !loggedIn && !onLoginPage && !onOnboardingPage) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if (onLoginPage && loggedIn) {
    return <Navigate to="/" replace />;
  }

  // User needs personal config onboarding
  if (
    loggedIn &&
    onboardingComplete === false &&
    !onOnboardingPage &&
    !onLoginPage &&
    location.pathname !== "/settings"
  ) {
    return <Navigate to="/onboarding/user" replace />;
  }

  return (
    <div className="app-shell">
      {!onLoginPage && !onOnboardingPage && (
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
            <NavLink to="/tagger" className={({ isActive }) => (isActive ? "active" : "")}>
              Tagger
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
        <Route path="/tagger" element={<Tagger />} />
        <Route path="/settings" element={<Settings />} />
        <Route path="/onboarding" element={<Onboarding variant="admin" />} />
        <Route path="/onboarding/user" element={<Onboarding variant="user" />} />
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
