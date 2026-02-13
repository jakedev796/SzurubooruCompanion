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

/** POST a URL job to the CCC backend. */
export async function submitJob(url: string): Promise<{ id: string; status: string }> {
  const cfg = await loadConfig();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  if (cfg.apiKey) headers["X-API-Key"] = cfg.apiKey;

  const res = await fetch(`${cfg.baseUrl}/api/jobs`, {
    method: "POST",
    headers,
    body: JSON.stringify({ url }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`CCC returned ${res.status}: ${text}`);
  }

  return res.json();
}
