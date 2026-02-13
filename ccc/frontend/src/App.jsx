import { Routes, Route, NavLink } from "react-router-dom";
import JobList from "./pages/JobList";
import JobDetail from "./pages/JobDetail";
import Dashboard from "./pages/Dashboard";

export default function App() {
  return (
    <div className="app-shell">
      <header>
        <h1>CCC Dashboard</h1>
        <nav>
          <NavLink to="/" end className={({ isActive }) => (isActive ? "active" : "")}>
            Overview
          </NavLink>
          <NavLink to="/jobs" className={({ isActive }) => (isActive ? "active" : "")}>
            Jobs
          </NavLink>
        </nav>
      </header>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/jobs" element={<JobList />} />
        <Route path="/jobs/:id" element={<JobDetail />} />
      </Routes>
    </div>
  );
}
