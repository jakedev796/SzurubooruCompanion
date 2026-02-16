import { loadConfig, saveConfig, fetchSzuruUsers } from "../utils/api";

document.addEventListener("DOMContentLoaded", async () => {
  const baseUrlInput = document.getElementById("baseUrl") as HTMLInputElement;
  const apiKeyInput = document.getElementById("apiKey") as HTMLInputElement;
  const szuruUserSelect = document.getElementById("szuruUser") as HTMLSelectElement;
  const saveBtn = document.getElementById("save") as HTMLButtonElement;
  const msgEl = document.getElementById("msg") as HTMLDivElement;

  // Load stored config.
  const cfg = await loadConfig();
  baseUrlInput.value = cfg.baseUrl;
  apiKeyInput.value = cfg.apiKey;

  // Fetch available users from the backend and populate the dropdown.
  async function refreshUsers() {
    // Always read fresh config so we never use a stale selection.
    const currentCfg = await loadConfig();
    const users = await fetchSzuruUsers();
    // Keep the "Default user" option, replace the rest.
    szuruUserSelect.innerHTML = '<option value="">Default user</option>';
    for (const u of users) {
      const opt = document.createElement("option");
      opt.value = u;
      opt.textContent = u;
      szuruUserSelect.appendChild(opt);
    }
    // Restore saved selection.
    if (currentCfg.szuruUser) szuruUserSelect.value = currentCfg.szuruUser;
  }

  await refreshUsers();

  saveBtn.addEventListener("click", async () => {
    const baseUrl = baseUrlInput.value.trim().replace(/\/+$/, "");
    const apiKey = apiKeyInput.value.trim();
    const szuruUser = szuruUserSelect.value;

    if (!baseUrl) {
      msgEl.textContent = "Base URL is required.";
      msgEl.className = "msg err";
      return;
    }

    await saveConfig({ baseUrl, apiKey, szuruUser });
    msgEl.textContent = "Saved.";
    msgEl.className = "msg ok";

    // Refresh user list in case URL/key changed.
    await refreshUsers();
  });
});
