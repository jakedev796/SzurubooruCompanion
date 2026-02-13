import { loadConfig, saveConfig } from "../utils/api";

document.addEventListener("DOMContentLoaded", async () => {
  const baseUrlInput = document.getElementById("baseUrl") as HTMLInputElement;
  const apiKeyInput = document.getElementById("apiKey") as HTMLInputElement;
  const saveBtn = document.getElementById("save") as HTMLButtonElement;
  const msgEl = document.getElementById("msg") as HTMLDivElement;

  // Load stored config.
  const cfg = await loadConfig();
  baseUrlInput.value = cfg.baseUrl;
  apiKeyInput.value = cfg.apiKey;

  saveBtn.addEventListener("click", async () => {
    const baseUrl = baseUrlInput.value.trim().replace(/\/+$/, "");
    const apiKey = apiKeyInput.value.trim();

    if (!baseUrl) {
      msgEl.textContent = "Base URL is required.";
      msgEl.className = "msg err";
      return;
    }

    await saveConfig({ baseUrl, apiKey });
    msgEl.textContent = "Saved.";
    msgEl.className = "msg ok";
  });
});
