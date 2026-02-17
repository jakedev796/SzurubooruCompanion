import { saveConfig } from "../utils/api";

document.addEventListener("DOMContentLoaded", () => {
  const baseUrlInput = document.getElementById("baseUrl") as HTMLInputElement;
  const testBtn = document.getElementById("testConnection") as HTMLButtonElement;
  const msgEl = document.getElementById("msg") as HTMLDivElement;

  testBtn.addEventListener("click", async () => {
    const baseUrl = baseUrlInput.value.trim().replace(/\/+$/, "");

    if (!baseUrl) {
      msgEl.textContent = "Backend URL is required.";
      msgEl.className = "msg err";
      return;
    }

    // Validate URL format
    try {
      const url = new URL(baseUrl);
      if (!url.protocol.match(/^https?:$/)) {
        msgEl.textContent = "URL must start with http:// or https://";
        msgEl.className = "msg err";
        return;
      }
    } catch {
      msgEl.textContent = "Invalid URL format.";
      msgEl.className = "msg err";
      return;
    }

    // Test connection to /api/health
    testBtn.disabled = true;
    msgEl.textContent = "Testing connection...";
    msgEl.className = "msg";

    try {
      const res = await fetch(`${baseUrl}/api/health`, {
        method: "GET",
        headers: { Accept: "application/json" },
      });

      if (!res.ok) {
        throw new Error(`Backend returned ${res.status}`);
      }

      const data = await res.json();
      if (data.status !== "ok") {
        throw new Error("Backend health check failed");
      }

      // Save base URL and redirect to login
      await saveConfig({ baseUrl });
      msgEl.textContent = "Connected! Redirecting to login...";
      msgEl.className = "msg ok";

      setTimeout(() => {
        window.location.href = "login.html";
      }, 500);
    } catch (error) {
      msgEl.textContent = `Connection failed: ${error instanceof Error ? error.message : String(error)}`;
      msgEl.className = "msg err";
      testBtn.disabled = false;
    }
  });
});
