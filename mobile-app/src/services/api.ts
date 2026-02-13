/**
 * CCC API client for the mobile app.
 */

import AsyncStorage from "@react-native-async-storage/async-storage";

const CONFIG_KEY = "ccc_config";

export interface CccConfig {
  baseUrl: string;
  apiKey: string;
}

export async function loadConfig(): Promise<CccConfig> {
  try {
    const raw = await AsyncStorage.getItem(CONFIG_KEY);
    if (raw) return JSON.parse(raw);
  } catch {}
  return { baseUrl: "http://10.0.2.2:21425", apiKey: "" };
}

export async function saveConfig(cfg: CccConfig): Promise<void> {
  await AsyncStorage.setItem(CONFIG_KEY, JSON.stringify(cfg));
}

function authHeaders(cfg: CccConfig): Record<string, string> {
  const h: Record<string, string> = {
    Accept: "application/json",
  };
  if (cfg.apiKey) h["X-API-Key"] = cfg.apiKey;
  return h;
}

/** Submit a URL job. */
export async function submitUrlJob(url: string): Promise<{ id: string; status: string }> {
  const cfg = await loadConfig();
  const res = await fetch(`${cfg.baseUrl}/api/jobs`, {
    method: "POST",
    headers: { ...authHeaders(cfg), "Content-Type": "application/json" },
    body: JSON.stringify({ url }),
  });
  if (!res.ok) throw new Error(`CCC ${res.status}: ${await res.text()}`);
  return res.json();
}

/** Upload a file job. */
export async function submitFileJob(filePath: string, fileName: string): Promise<{ id: string; status: string }> {
  const cfg = await loadConfig();
  const form = new FormData();
  form.append("file", {
    uri: filePath,
    name: fileName,
    type: "application/octet-stream",
  } as any);
  form.append("safety", "unsafe");

  const res = await fetch(`${cfg.baseUrl}/api/jobs/upload`, {
    method: "POST",
    headers: authHeaders(cfg),
    body: form,
  });
  if (!res.ok) throw new Error(`CCC ${res.status}: ${await res.text()}`);
  return res.json();
}
