/**
 * Shared helpers for talking to the CCC backend.
 */

export interface CccConfig {
  baseUrl: string;
  apiKey: string;
}

const STORAGE_KEY = "ccc_config";

/** Load persisted CCC config from extension storage. */
export async function loadConfig(): Promise<CccConfig> {
  const result = await browser.storage.local.get(STORAGE_KEY);
  return (
    result[STORAGE_KEY] ?? {
      baseUrl: "http://localhost:21425",
      apiKey: "",
    }
  );
}

/** Persist CCC config to extension storage. */
export async function saveConfig(cfg: CccConfig): Promise<void> {
  await browser.storage.local.set({ [STORAGE_KEY]: cfg });
}

export interface SubmitJobOptions {
  source?: string;
  tags?: string[];
}

/** POST a URL job to the CCC backend. */
export async function submitJob(
  url: string,
  opts?: SubmitJobOptions
): Promise<{ id: string; status: string }> {
  const cfg = await loadConfig();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  if (cfg.apiKey) headers["X-API-Key"] = cfg.apiKey;

  const body: { url: string; source?: string; tags?: string[] } = { url };
  if (opts?.source) body.source = opts.source;
  if (opts?.tags?.length) body.tags = opts.tags;

  const res = await fetch(`${cfg.baseUrl}/api/jobs`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });

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
  szuru_post_id?: number;
  error_message?: string | null;
}

/** GET a single job by ID. */
export async function fetchJob(id: string): Promise<Job> {
  const cfg = await loadConfig();
  const headers: Record<string, string> = { Accept: "application/json" };
  if (cfg.apiKey) headers["X-API-Key"] = cfg.apiKey;

  const res = await fetch(`${cfg.baseUrl}/api/jobs/${id}`, { headers });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`CCC returned ${res.status}: ${text}`);
  }

  return res.json();
}
