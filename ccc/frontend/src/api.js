/**
 * CCC API client.
 * Reads API_KEY from localStorage if present.
 * BASE: VITE_API_BASE at build time, or on localhost (no proxy) use backend :21425, else same-origin "/api".
 */
function getBase() {
  const env = (import.meta.env.VITE_API_BASE ?? "").replace(/\/$/, "");
  if (env) return env;
  const { hostname } = typeof location !== "undefined" ? location : {};
  if (hostname === "localhost" || hostname === "127.0.0.1") {
    return "http://localhost:21425/api";
  }
  return "/api";
}
const BASE = getBase();

function headers() {
  const h = { Accept: "application/json" };
  const key = localStorage.getItem("ccc_api_key");
  if (key) h["X-API-Key"] = key;
  return h;
}

async function parseJson(res) {
  const text = await res.text();
  if (text.trimStart().startsWith("<")) {
    throw new Error(
      "API returned HTML instead of JSON. Ensure your reverse proxy forwards /api to the backend (port 21425). See README."
    );
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(text || `HTTP ${res.status}`);
  }
}

export async function fetchJobs({ status, offset = 0, limit = 50 } = {}) {
  const params = new URLSearchParams({ offset, limit });
  if (status) params.set("status", status);
  const res = await fetch(`${BASE}/jobs?${params}`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function fetchJob(id) {
  const res = await fetch(`${BASE}/jobs/${id}`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function fetchStats() {
  const res = await fetch(`${BASE}/stats`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function createJobUrl(url, opts = {}) {
  const res = await fetch(`${BASE}/jobs`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ url, ...opts }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function fetchHealth() {
  const res = await fetch(`${BASE}/health`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}
