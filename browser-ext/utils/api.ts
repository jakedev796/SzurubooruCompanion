/**
 * Shared helpers for talking to the CCC backend.
 */

export interface CccConfig {
  baseUrl: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

const STORAGE_KEY = "ccc_config";
const STORAGE_KEY_AUTH = "ccc_auth";
const STORAGE_KEY_NOTIFICATIONS = "ccc_notifications_enabled";
const STORAGE_KEY_SAFETY = "ccc_default_safety";
const CLIENT_TYPE = "extension-chrome";  // TODO: Detect Firefox and use "extension-firefox"

export type SafetyRating = "safe" | "sketchy" | "unsafe";

/** Load default safety for uploads. Default "unsafe". */
export async function getDefaultSafety(): Promise<SafetyRating> {
  const result = await browser.storage.local.get(STORAGE_KEY_SAFETY);
  const v = result[STORAGE_KEY_SAFETY];
  if (v === "safe" || v === "sketchy" || v === "unsafe") return v;
  return "unsafe";
}

/** Persist default safety for uploads. */
export async function setDefaultSafety(safety: SafetyRating): Promise<void> {
  await browser.storage.local.set({ [STORAGE_KEY_SAFETY]: safety });
}

/** Load notifications enabled preference. Default true. */
export async function getNotificationsEnabled(): Promise<boolean> {
  const result = await browser.storage.local.get(STORAGE_KEY_NOTIFICATIONS);
  if (result[STORAGE_KEY_NOTIFICATIONS] === false) return false;
  return true;
}

/** Persist notifications enabled preference. */
export async function setNotificationsEnabled(enabled: boolean): Promise<void> {
  await browser.storage.local.set({ [STORAGE_KEY_NOTIFICATIONS]: enabled });
}

/** Load persisted CCC config from extension storage. */
export async function loadConfig(): Promise<CccConfig> {
  const result = await browser.storage.local.get(STORAGE_KEY);
  return (
    result[STORAGE_KEY] ?? {
      baseUrl: "",
    }
  );
}

/** Persist CCC config to extension storage. */
export async function saveConfig(cfg: CccConfig): Promise<void> {
  await browser.storage.local.set({ [STORAGE_KEY]: cfg });
}

/** Login with username/password and store JWT tokens. */
export async function login(username: string, password: string): Promise<AuthTokens> {
  const cfg = await loadConfig();
  const res = await fetch(`${cfg.baseUrl}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Login failed: ${res.status} ${text}`);
  }

  const data = await res.json();
  const tokens = {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
  };

  await browser.storage.local.set({ [STORAGE_KEY_AUTH]: tokens });
  return tokens;
}

/** Refresh access token using stored refresh token. */
export async function refreshAccessToken(): Promise<AuthTokens | null> {
  const result = await browser.storage.local.get(STORAGE_KEY_AUTH);
  const tokens = result[STORAGE_KEY_AUTH];
  if (!tokens) return null;

  const cfg = await loadConfig();
  const res = await fetch(`${cfg.baseUrl}/api/auth/refresh`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: tokens.refreshToken }),
  });

  if (!res.ok) return null;

  const data = await res.json();
  const newTokens = {
    accessToken: data.access_token,
    refreshToken: tokens.refreshToken,
  };

  await browser.storage.local.set({ [STORAGE_KEY_AUTH]: newTokens });
  return newTokens;
}

/** Check if user is authenticated (has tokens stored). */
export async function isAuthenticated(): Promise<boolean> {
  const result = await browser.storage.local.get(STORAGE_KEY_AUTH);
  return !!result[STORAGE_KEY_AUTH];
}

/** Get auth headers (JWT or API key fallback). */
async function getAuthHeaders(): Promise<Record<string, string>> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };

  const result = await browser.storage.local.get(STORAGE_KEY_AUTH);
  const tokens = result[STORAGE_KEY_AUTH];

  if (tokens) {
    headers["Authorization"] = `Bearer ${tokens.accessToken}`;
  }

  return headers;
}

/** Fetch client preferences from backend. */
export async function fetchPreferences(): Promise<any> {
  const cfg = await loadConfig();
  let headers = await getAuthHeaders();

  let res = await fetch(`${cfg.baseUrl}/api/preferences/${CLIENT_TYPE}`, { headers });

  // Auto-refresh on 401
  if (res.status === 401) {
    const refreshed = await refreshAccessToken();
    if (refreshed) {
      headers = await getAuthHeaders();
      res = await fetch(`${cfg.baseUrl}/api/preferences/${CLIENT_TYPE}`, { headers });
    } else {
      throw new Error("Authentication expired. Please log in again.");
    }
  }

  if (!res.ok) throw new Error(`Failed to fetch preferences: ${res.status}`);
  const data = await res.json();
  return data.preferences;
}

/** Save client preferences to backend. */
export async function savePreferences(prefs: any): Promise<void> {
  const cfg = await loadConfig();
  let headers = await getAuthHeaders();

  let res = await fetch(`${cfg.baseUrl}/api/preferences/${CLIENT_TYPE}`, {
    method: "PUT",
    headers,
    body: JSON.stringify({ preferences: prefs }),
  });

  // Auto-refresh on 401
  if (res.status === 401) {
    const refreshed = await refreshAccessToken();
    if (refreshed) {
      headers = await getAuthHeaders();
      res = await fetch(`${cfg.baseUrl}/api/preferences/${CLIENT_TYPE}`, {
        method: "PUT",
        headers,
        body: JSON.stringify({ preferences: prefs }),
      });
    } else {
      throw new Error("Authentication expired. Please log in again.");
    }
  }

  if (!res.ok) throw new Error(`Failed to save preferences: ${res.status}`);
}

export interface SubmitJobOptions {
  source?: string;
  tags?: string[];
  safety?: 'safe' | 'sketchy' | 'unsafe';
  skipTagging?: boolean;
}

/** POST a URL job to the CCC backend. */
export async function submitJob(
  url: string,
  opts?: SubmitJobOptions
): Promise<{ id: string; status: string }> {
  const cfg = await loadConfig();
  let headers = await getAuthHeaders();

  const body: {
    url: string;
    source?: string;
    tags?: string[];
    safety?: string;
    skip_tagging?: boolean;
  } = { url };

  if (opts?.source) body.source = opts.source;
  if (opts?.tags?.length) body.tags = opts.tags;
  if (opts?.safety) body.safety = opts.safety;
  if (opts?.skipTagging) body.skip_tagging = opts.skipTagging;

  let res = await fetch(`${cfg.baseUrl}/api/jobs`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });

  // Auto-refresh on 401
  if (res.status === 401) {
    const refreshed = await refreshAccessToken();
    if (refreshed) {
      headers = await getAuthHeaders();
      res = await fetch(`${cfg.baseUrl}/api/jobs`, {
        method: "POST",
        headers,
        body: JSON.stringify(body),
      });
    } else {
      throw new Error("Authentication expired. Please log in again.");
    }
  }

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`CCC returned ${res.status}: ${text}`);
  }

  return res.json();
}

export interface Job {
  id: string;
  status: string;
  job_type?: string;
  url?: string;
  original_filename?: string;
  source_override?: string;
  safety?: string;
  skip_tagging?: boolean;
  szuru_post_id?: number;
  related_post_ids?: number[];
  error_message?: string | null;
  tags_applied?: string[];
  tags_from_source?: string[];
  tags_from_ai?: string[];
  retry_count?: number;
  created_at?: string;
  updated_at?: string;
}

/** GET a single job by ID. */
export async function fetchJob(id: string): Promise<Job> {
  const cfg = await loadConfig();
  let headers = await getAuthHeaders();

  let res = await fetch(`${cfg.baseUrl}/api/jobs/${id}`, { headers });

  // Auto-refresh on 401
  if (res.status === 401) {
    const refreshed = await refreshAccessToken();
    if (refreshed) {
      headers = await getAuthHeaders();
      res = await fetch(`${cfg.baseUrl}/api/jobs/${id}`, { headers });
    } else {
      throw new Error("Authentication expired. Please log in again.");
    }
  }

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`CCC returned ${res.status}: ${text}`);
  }

  return res.json();
}
