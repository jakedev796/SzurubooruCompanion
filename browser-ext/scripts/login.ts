import { login, fetchPreferences, saveConfig, loadConfig } from "../utils/api";

document.addEventListener("DOMContentLoaded", () => {
  const usernameInput = document.getElementById("username") as HTMLInputElement;
  const passwordInput = document.getElementById("password") as HTMLInputElement;
  const loginBtn = document.getElementById("login") as HTMLButtonElement;
  const msgEl = document.getElementById("msg") as HTMLDivElement;

  // Handle Enter key
  passwordInput.addEventListener("keypress", (e) => {
    if (e.key === "Enter") loginBtn.click();
  });

  loginBtn.addEventListener("click", async () => {
    const username = usernameInput.value.trim();
    const password = passwordInput.value;

    if (!username || !password) {
      msgEl.textContent = "Username and password are required.";
      msgEl.className = "msg err";
      return;
    }

    loginBtn.disabled = true;
    msgEl.textContent = "Logging in...";
    msgEl.className = "msg";

    try {
      // Login and store tokens
      await login(username, password);

      msgEl.textContent = "Fetching preferences...";

      // Fetch preferences from backend
      const prefs = await fetchPreferences();

      // Keep baseUrl from setup
      const cfg = await loadConfig();
      await saveConfig({
        baseUrl: cfg.baseUrl,
      });

      msgEl.textContent = "Login successful! Redirecting...";
      msgEl.className = "msg ok";

      setTimeout(() => {
        window.location.href = "popup.html";
      }, 500);
    } catch (error) {
      msgEl.textContent = `Login failed: ${error instanceof Error ? error.message : String(error)}`;
      msgEl.className = "msg err";
      loginBtn.disabled = false;
    }
  });
});
