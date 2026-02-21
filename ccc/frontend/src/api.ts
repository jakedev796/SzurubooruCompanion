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

  // Try JWT first (preferred)
  const jwt = localStorage.getItem("ccc_jwt_token");
  if (jwt) {
    h["Authorization"] = `Bearer ${jwt}`;
    return h;
  }

  // Fallback: API key
  const key = localStorage.getItem("ccc_api_key");
  if (key) h["X-API-Key"] = key;

  // Fallback: Legacy Basic auth
  const basic = sessionStorage.getItem("dashboard_basic");
  if (basic) h["Authorization"] = "Basic " + basic;

  return h;
}

export function setJWT(token: string | null): void {
  if (token) localStorage.setItem("ccc_jwt_token", token);
  else localStorage.removeItem("ccc_jwt_token");
}

export function getJWT(): string | null {
  return localStorage.getItem("ccc_jwt_token");
}

export function setDashboardAuth(basicValue: string | null): void {
  if (basicValue) sessionStorage.setItem("dashboard_basic", basicValue);
  else sessionStorage.removeItem("dashboard_basic");
}

export function hasDashboardAuth(): boolean {
  return !!sessionStorage.getItem("dashboard_basic") || !!localStorage.getItem("ccc_jwt_token");
}

async function parseJson<T = unknown>(res: Response): Promise<T> {
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

async function handleError(res: Response): Promise<never> {
  try {
    const errorData = await res.json();
    // Extract error message from various possible formats
    const message = errorData.detail || errorData.message || errorData.error || `HTTP ${res.status}`;
    throw new Error(message);
  } catch (e) {
    // If parsing fails, throw generic error
    if (e instanceof Error && !e.message.includes("HTTP")) {
      throw e; // Re-throw if it's our custom error
    }
    throw new Error(`HTTP ${res.status}`);
  }
}

function handleUnauthorized(res: Response): void {
  if (res.status === 401) {
    // Token expired or invalid - clear auth and redirect to login
    setJWT(null);
    sessionStorage.removeItem("dashboard_basic");
    // Only redirect if not already on login page
    if (window.location.pathname !== "/login") {
      window.location.href = "/login";
    }
  }
}

// Wrapper around fetch that handles 401 globally
async function apiFetch(url: string, init?: RequestInit): Promise<Response> {
  const res = await fetch(url, init);
  handleUnauthorized(res);
  return res;
}

export interface JobsResponse {
  results: JobSummary[];
  total: number;
}

/** Mirrors the post as stored on Szurubooru (what we offload to them). */
export interface SzuruPostMirror {
  id: number;
  tags: string[];
  source?: string | null;
  safety?: string | null;
  relations: number[];
}

export interface JobSummary {
  id: string;
  status: string;
  job_type: string;
  url?: string;
  original_filename?: string;
  source_override?: string;
  safety?: string;
  szuru_user?: string;
  dashboard_username?: string;
  szuru_post_id?: number;
  related_post_ids?: number[];
  created_at?: string;
  updated_at?: string;
}

export interface Job extends JobSummary {
  source_override?: string;
  safety?: string;
  was_merge?: boolean;
  tags_from_source?: string[];
  tags_from_ai?: string[];
  tags_applied?: string[];
  error_message?: string;
  retry_count?: number;
  skip_tagging?: boolean;
  /** When completed, mirrors the post on Szurubooru. */
  post?: SzuruPostMirror | null;
}

export interface StatsResponse {
  by_status: Record<string, number>;
  daily_uploads?: { date: string; count: number; failed?: number }[];
}

export interface ConfigResponse {
  auth_required?: boolean;
  booru_url?: string;
  szuru_users?: string[];
}

/** Original page URL first, then stored source list (direct media etc.), deduped. */
export function getJobSources(job: Job): string[] {
  const overrideRaw = (job.post?.source ?? job.source_override ?? "").trim();
  const overrideLines = overrideRaw
    ? overrideRaw.split("\n").map((s) => s.trim()).filter(Boolean)
    : [];
  const url = (job.url ?? "").trim();
  const norm = (s: string) => s.replace(/\/$/, "");
  const result: string[] = [];
  if (url) result.push(url);
  const seen = new Set(result.map(norm));
  for (const s of overrideLines) {
    if (seen.has(norm(s))) continue;
    seen.add(norm(s));
    result.push(s);
  }
  return result;
}

/** Sort tags: digit-prefixed first (123), then A–Z (case-insensitive). */
export function sortTags(tags: string[]): string[] {
  return [...tags].sort((a, b) => {
    const aDigit = /^\d/.test(a);
    const bDigit = /^\d/.test(b);
    if (aDigit && !bDigit) return -1;
    if (!aDigit && bDigit) return 1;
    return a.localeCompare(b, undefined, { sensitivity: "base" });
  });
}

export async function fetchJobs({
  status,
  was_merge,
  szuru_user,
  offset = 0,
  limit = 50,
}: { status?: string; was_merge?: boolean; szuru_user?: string; offset?: number; limit?: number } = {}): Promise<JobsResponse> {
  const params = new URLSearchParams({ offset: String(offset), limit: String(limit) });
  if (status) params.set("status", status);
  if (was_merge !== undefined) params.set("was_merge", String(was_merge));
  if (szuru_user) params.set("szuru_user", szuru_user);
  const res = await apiFetch(`${BASE}/jobs?${params}`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<JobsResponse>(res);
}

export async function fetchJob(id: string): Promise<Job> {
  const res = await apiFetch(`${BASE}/jobs/${id}`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<Job>(res);
}

export async function fetchStats({ szuru_user }: { szuru_user?: string } = {}): Promise<StatsResponse> {
  const params = new URLSearchParams();
  if (szuru_user) params.set("szuru_user", szuru_user);
  const qs = params.toString();
  const res = await apiFetch(`${BASE}/stats${qs ? `?${qs}` : ""}`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<StatsResponse>(res);
}

export async function createJobUrl(
  url: string,
  opts: Record<string, unknown> = {}
): Promise<Job> {
  const res = await apiFetch(`${BASE}/jobs`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ url, ...opts }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<Job>(res);
}

export async function fetchHealth(): Promise<unknown> {
  const res = await apiFetch(`${BASE}/health`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function fetchConfig(): Promise<ConfigResponse> {
  const res = await apiFetch(`${BASE}/config`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<ConfigResponse>(res);
}

export function getSSEUrl(_jobId: string | null = null): string {
  const baseUrl = getBase();
  return `${baseUrl}/events`;
}

export async function startJob(jobId: string): Promise<Job> {
  const res = await apiFetch(`${BASE}/jobs/${jobId}/start`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<Job>(res);
}

export async function pauseJob(jobId: string): Promise<Job> {
  const res = await apiFetch(`${BASE}/jobs/${jobId}/pause`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<Job>(res);
}

export async function stopJob(jobId: string): Promise<Job> {
  const res = await apiFetch(`${BASE}/jobs/${jobId}/stop`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<Job>(res);
}

export async function deleteJob(jobId: string): Promise<void> {
  const res = await apiFetch(`${BASE}/jobs/${jobId}`, {
    method: "DELETE",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
}

export async function resumeJob(jobId: string): Promise<Job> {
  const res = await apiFetch(`${BASE}/jobs/${jobId}/resume`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<Job>(res);
}

export async function retryJob(jobId: string): Promise<Job> {
  const res = await apiFetch(`${BASE}/jobs/${jobId}/retry`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<Job>(res);
}

export interface BulkJobAccepted {
  accepted: boolean;
  job_ids: string[];
  action: string;
}

export async function bulkRetryJobs(jobIds: string[]): Promise<BulkJobAccepted> {
  const res = await apiFetch(`${BASE}/jobs/bulk/retry`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ job_ids: jobIds }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<BulkJobAccepted>(res);
}

export async function bulkDeleteJobs(jobIds: string[]): Promise<BulkJobAccepted> {
  const res = await apiFetch(`${BASE}/jobs/bulk/delete`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ job_ids: jobIds }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<BulkJobAccepted>(res);
}

export async function bulkStartJobs(jobIds: string[]): Promise<BulkJobAccepted> {
  const res = await apiFetch(`${BASE}/jobs/bulk/start`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ job_ids: jobIds }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<BulkJobAccepted>(res);
}

export async function bulkPauseJobs(jobIds: string[]): Promise<BulkJobAccepted> {
  const res = await apiFetch(`${BASE}/jobs/bulk/pause`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ job_ids: jobIds }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<BulkJobAccepted>(res);
}

export async function bulkStopJobs(jobIds: string[]): Promise<BulkJobAccepted> {
  const res = await apiFetch(`${BASE}/jobs/bulk/stop`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ job_ids: jobIds }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<BulkJobAccepted>(res);
}

export async function bulkResumeJobs(jobIds: string[]): Promise<BulkJobAccepted> {
  const res = await apiFetch(`${BASE}/jobs/bulk/resume`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ job_ids: jobIds }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<BulkJobAccepted>(res);
}

// ============================================================================
// Auth endpoints
// ============================================================================

export interface LoginResponse {
  access_token: string;
  token_type: string;
  user: {
    id: string;
    username: string;
    role: string;
  };
}

export async function login(username: string, password: string): Promise<LoginResponse> {
  const res = await apiFetch(`${BASE}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) await handleError(res);
  return parseJson<LoginResponse>(res);
}

export async function fetchMe(): Promise<{ id: string; username: string; role: string }> {
  const res = await apiFetch(`${BASE}/auth/me`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<{ id: string; username: string; role: string }>(res);
}

// ============================================================================
// User management endpoints
// ============================================================================

export interface UserResponse {
  id: string;
  username: string;
  role: string;
  is_active: boolean;
  szuru_url?: string;
  szuru_username?: string;
  created_at: string;
  updated_at: string;
}

export async function fetchUsers(): Promise<UserResponse[]> {
  const res = await apiFetch(`${BASE}/users`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<UserResponse[]>(res);
}

export async function createUser(data: {
  username: string;
  password: string;
  role?: string;
}): Promise<UserResponse> {
  const res = await apiFetch(`${BASE}/users`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<UserResponse>(res);
}

export async function updateUser(
  userId: string,
  data: {
    password?: string;
    role?: string;
    is_active?: boolean;
  }
): Promise<UserResponse> {
  const res = await apiFetch(`${BASE}/users/${userId}`, {
    method: "PUT",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<UserResponse>(res);
}

export async function deactivateUser(userId: string): Promise<{ message: string }> {
  const res = await apiFetch(`${BASE}/users/${userId}/deactivate`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function activateUser(userId: string): Promise<{ message: string }> {
  const res = await apiFetch(`${BASE}/users/${userId}/activate`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function resetUserPassword(userId: string, password: string): Promise<{ message: string }> {
  const res = await apiFetch(`${BASE}/users/${userId}/reset-password`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function promoteToAdmin(userId: string): Promise<{ message: string }> {
  const res = await apiFetch(`${BASE}/users/${userId}/promote-admin`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function demoteFromAdmin(userId: string): Promise<{ message: string }> {
  const res = await apiFetch(`${BASE}/users/${userId}/demote-admin`, {
    method: "POST",
    headers: headers(),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function changeMyPassword(oldPassword: string, newPassword: string): Promise<{ message: string }> {
  const res = await apiFetch(`${BASE}/users/me/change-password`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ old_password: oldPassword, new_password: newPassword }),
  });
  if (!res.ok) await handleError(res);
  return parseJson(res);
}

// ============================================================================
// User config endpoints
// ============================================================================

export interface UserConfig {
  szuru_url?: string;
  szuru_public_url?: string;
  szuru_username?: string;
  szuru_token?: string;
  site_credentials?: Record<string, Record<string, string>>;
}

export async function fetchMyConfig(): Promise<UserConfig> {
  const res = await apiFetch(`${BASE}/users/me/config`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<UserConfig>(res);
}

export async function updateMyConfig(data: UserConfig): Promise<void> {
  const res = await apiFetch(`${BASE}/users/me/config`, {
    method: "PUT",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
}

// ============================================================================
// Global settings endpoints
// ============================================================================

export interface GlobalSettings {
  wd14_enabled: boolean;
  wd14_model: string;
  wd14_confidence_threshold: number;
  wd14_max_tags: number;
  worker_concurrency: number;
  gallery_dl_timeout: number;
  ytdlp_timeout: number;
  max_retries: number;
  retry_delay: number;
  video_tagging_enabled: boolean;
  video_scene_threshold: number;
  video_max_frames: number;
  video_tag_min_frame_ratio: number;
}

export async function fetchGlobalSettings(): Promise<GlobalSettings> {
  const res = await apiFetch(`${BASE}/settings/global`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson<GlobalSettings>(res);
}

export async function updateGlobalSettings(data: Partial<GlobalSettings>): Promise<void> {
  const res = await apiFetch(`${BASE}/settings/global`, {
    method: "PUT",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
}


export async function fetchSzuruCategories(
  szuru_url: string,
  szuru_username: string,
  szuru_token: string
): Promise<{ results?: Array<{ name: string; color: string; order: number }>; error?: string }> {
  const res = await apiFetch(`${BASE}/settings/szuru-categories`, {
    method: "POST",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ szuru_url, szuru_username, szuru_token }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function fetchCategoryMappings(): Promise<{ mappings: Record<string, string> }> {
  const res = await apiFetch(`${BASE}/settings/category-mappings`, { headers: headers() });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}

export async function updateCategoryMappings(mappings: Record<string, string>): Promise<{ message: string }> {
  const res = await apiFetch(`${BASE}/settings/category-mappings`, {
    method: "PUT",
    headers: { ...headers(), "Content-Type": "application/json" },
    body: JSON.stringify({ mappings }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return parseJson(res);
}
