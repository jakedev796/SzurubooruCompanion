import { loadConfig, saveConfig, isAuthenticated, savePreferences } from "../utils/api";

document.addEventListener("DOMContentLoaded", async () => {
  // Auth routing: check setup → login → popup
  const cfg = await loadConfig();
  const authed = await isAuthenticated();

  if (!cfg.baseUrl) {
    window.location.href = "setup.html";
    return;
  }

  if (!authed) {
    window.location.href = "login.html";
    return;
  }

  // Normal popup flow (user is authenticated)
  const baseUrlInput = document.getElementById("baseUrl") as HTMLInputElement;
  const saveBtn = document.getElementById("save") as HTMLButtonElement;
  const msgEl = document.getElementById("msg") as HTMLDivElement;

  // Load stored config
  baseUrlInput.value = cfg.baseUrl;

  saveBtn.addEventListener("click", async () => {
    const baseUrl = baseUrlInput.value.trim().replace(/\/+$/, "");

    if (!baseUrl) {
      msgEl.textContent = "Base URL is required.";
      msgEl.className = "msg err";
      return;
    }

    await saveConfig({ baseUrl });

    // Sync preferences to backend
    try {
      await savePreferences({});
    } catch (e) {
      console.warn("Failed to sync preferences:", e);
      // Don't fail the save if sync fails
    }

    msgEl.textContent = "Saved.";
    msgEl.className = "msg ok";
  });
});
