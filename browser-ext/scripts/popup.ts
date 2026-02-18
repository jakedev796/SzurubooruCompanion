import { loadConfig, saveConfig, isAuthenticated, savePreferences, getNotificationsEnabled, setNotificationsEnabled, getDefaultSafety, setDefaultSafety, type SafetyRating } from "../utils/api";

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
  const notificationsCheckbox = document.getElementById("notifications") as HTMLInputElement;
  const safetyRow = document.getElementById("safetyRow")!;

  // Load stored config and preferences
  baseUrlInput.value = cfg.baseUrl;
  notificationsCheckbox.checked = await getNotificationsEnabled();
  const currentSafety = await getDefaultSafety();
  safetyRow.querySelectorAll(".safety-btn").forEach((btn) => {
    const el = btn as HTMLButtonElement;
    el.classList.toggle("selected", el.dataset.safety === currentSafety);
  });

  safetyRow.addEventListener("click", async (e) => {
    const btn = (e.target as HTMLElement).closest(".safety-btn") as HTMLButtonElement | null;
    if (!btn?.dataset.safety) return;
    const safety = btn.dataset.safety as SafetyRating;
    await setDefaultSafety(safety);
    safetyRow.querySelectorAll(".safety-btn").forEach((b) => {
      (b as HTMLButtonElement).classList.toggle("selected", (b as HTMLButtonElement).dataset.safety === safety);
    });
  });

  notificationsCheckbox.addEventListener("change", async () => {
    await setNotificationsEnabled(notificationsCheckbox.checked);
  });

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
