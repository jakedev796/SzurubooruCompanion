/**
 * CCC API client.
 * Reads API_KEY from localStorage if present.
 * BASE: VITE_API_BASE at build time, or on localhost (no proxy) use backend :21425, else same-origin "/api".
 */

function getBase(): string {
  const env = (import.meta.env.VITE_API_BASE ?? "").replace(/\/$/, "");
  if (env) return env;
  const { hostname } = typeof location !== "undefined" ? location : {};
  if (hostname === "localhost" || hostname === "127.0.0.1") {
    return "http://localhost:21425/api";
  }
  return "/api";
}
const BASE = getBase();

function headers(): Record<string, string> {
  const h: Record<string, string> = { Accept: "application/json" };
  const key = localStorage.getItem("ccc_api_key");
  if (key) h["X-API-Key"] = key;
  const basic = sessionStorage.getItem("dashboard_basic");
  if (basic) h["Authorization"] = "Basic " + basic;
  return h;
}

export function setDashboardAuth(basicValue: string | null): void {
  if (basicValue) sessionStorage.setItem("dashboard_basic", basicValue);
  else sessionStorage.removeItem("dashboard_basic");
}

async function parseJson(res: Response): Promise<unknown> {
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

export interface JobSummary {
  id: number;
  status: string;
  job_type: string;
  url?: string;
  original_filename?: string;
  szuru_user?: string;
  szuru_post_id?: number;
  related_post_ids?: number[];
  created_at?: string;
  updated_at?: string;
}

export interface Job extends JobSummary {
  safety?: string;
  tags_from_source?: string[];
  tags_from_ai?: string[];
  tags_applied?: string[];
  error_message?: string;
  retry_count?: number;
  skip_tagging?: boolean;
}

export interface JobsResponse {
  results: JobSummary[];
  total: number;
}

export interface StatsResponse {
  by_status: Record<string, number>;
  daily_uploads?: { date: string; count: number }[];
}

export interface ConfigResponse {
  auth_required?: boolean;
  booru_url?: string;
  szuru_users?: string[];
}

export async function fetchJobs({
  status,
  szuru_user,
  offset = 0,
  limit = 50,
}: { status?: string; szuru_user?: string; offset?: number; limit?: number } = {}): Promise<JobsResponse> {
  const params = new URLSearchParams({ offset: String(offset), limit: String(limit) });
  if (status) params.set("status", status);
  if (szuru_user) params.set("szuru_user", szuru_user);
  const res = await fetch(`${BASE}/jobs?${params}`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<JobsResponse>;
}

export async function fetchJob(id: string): Promise<Job> {
  const res = await fetch(`${BASE}/jobs/${id}`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<Job>;
}

export async function fetchStats(): Promise<StatsResponse> {
  const res = await fetch(`${BASE}/stats`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<StatsResponse>;
}

export async function createJobUrl(
  url: string,
  opts: Record<string, unknown> = {}
): Promise<Job> {
  const res = await fetch(`${BASE}/jobs`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ url, ...opts }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<Job>;
}

export async function fetchHealth(): Promise<unknown> {
  const res = await fetch(`${BASE}/health`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function fetchConfig(): Promise<ConfigResponse> {
  const res = await fetch(`${BASE}/config`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<ConfigResponse>;
}

export function getSSEUrl(_jobId: string | null = null): string {
  const baseUrl = getBase();
  return `${baseUrl}/events`;
}

export async function startJob(jobId: number): Promise<Job> {
  const res = await fetch(`${BASE}/jobs/${jobId}/start`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<Job>;
}

export async function pauseJob(jobId: number): Promise<Job> {
  const res = await fetch(`${BASE}/jobs/${jobId}/pause`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<Job>;
}

export async function stopJob(jobId: number): Promise<Job> {
  const res = await fetch(`${BASE}/jobs/${jobId}/stop`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<Job>;
}

export async function deleteJob(jobId: number): Promise<void> {
  const res = await fetch(`${BASE}/jobs/${jobId}`, {
    method: "DELETE",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
}

export async function resumeJob(jobId: number): Promise<Job> {
  const res = await fetch(`${BASE}/jobs/${jobId}/resume`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res) as Promise<Job>;
}
