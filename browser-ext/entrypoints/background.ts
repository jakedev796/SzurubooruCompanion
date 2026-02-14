/**
 * Background entrypoint – registers context menu items and handles clicks.
 * Always sends the page URL when available so gallery-dl can resolve and download.
 * Polls job status and shows a toast + notification when the job finishes or fails.
 */
import { fetchJob, submitJob } from "../utils/api";

const POLL_INTERVAL_MS = 3000;
const POLL_TIMEOUT_MS = 10 * 60 * 1000;

/** Show in-page toast (injected into active tab). Must be a plain function for scripting. */
function showPageToast(message: string, type: "success" | "error"): void {
  const id = "ccc-toast-" + Date.now();
  const el = document.createElement("div");
  el.id = id;
  el.textContent = message;
  el.style.cssText = [
    "position:fixed",
    "bottom:24px",
    "right:24px",
    "max-width:320px",
    "padding:12px 16px",
    "border-radius:8px",
    "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif",
    "font-size:14px",
    "font-weight:500",
    "box-shadow:0 4px 12px rgba(0,0,0,0.25)",
    "z-index:2147483647",
    "pointer-events:none",
    type === "success" ? "background:#22c55e" : "background:#ef4444",
    "color:#fff",
  ].join(";");
  const style = document.createElement("style");
  style.textContent =
    "@keyframes ccc-toast-in{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}";
  document.head.appendChild(style);
  document.body.appendChild(el);
  el.style.animation = "ccc-toast-in 0.2s ease";
  setTimeout(() => {
    el.style.opacity = "0";
    el.style.transition = "opacity 0.2s ease";
    setTimeout(() => {
      el.remove();
      style.remove();
    }, 200);
  }, 4000);
}

async function showToastAndNotification(
  message: string,
  title: string,
  type: "success" | "error",
  tabId?: number
): Promise<void> {
  if (browser.notifications) {
    browser.notifications.create({
      type: "basic",
      iconUrl: browser.runtime.getURL("icon/128.png"),
      title,
      message: message.slice(0, 200),
    });
  }
  if (browser.scripting && tabId) {
    try {
      await browser.scripting.executeScript({
        target: { tabId },
        func: showPageToast,
        args: [message, type],
      });
    } catch {
      // Tab may be closed or not injectable (e.g. chrome://); ignore.
    }
  }
}

async function pollUntilDone(
  jobId: string,
  tabId: number | undefined,
  startTime: number
): Promise<void> {
  try {
    const job = await fetchJob(jobId);
    if (job.status === "completed") {
      const msg = job.szuru_post_id
        ? `Uploaded to Szurubooru (post #${job.szuru_post_id})`
        : "Upload complete.";
      await showToastAndNotification(
        msg,
        "Szurubooru Companion",
        "success",
        tabId
      );
      return;
    }
    if (job.status === "failed") {
      const msg = job.error_message?.slice(0, 200) || "Upload failed.";
      await showToastAndNotification(
        msg,
        "Szurubooru Companion – Failed",
        "error",
        tabId
      );
      return;
    }
  } catch (err) {
    console.error("[CCC] Poll error:", err);
    if (Date.now() - startTime > POLL_TIMEOUT_MS) {
      await showToastAndNotification(
        "Job status check timed out.",
        "Szurubooru Companion",
        "error",
        tabId
      );
      return;
    }
  }
  if (Date.now() - startTime > POLL_TIMEOUT_MS) {
    await showToastAndNotification(
      "Job is still processing. Check the CCC dashboard.",
      "Szurubooru Companion",
      "error",
      tabId
    );
    return;
  }
  setTimeout(
    () => pollUntilDone(jobId, tabId, startTime),
    POLL_INTERVAL_MS
  );
}

export default defineBackground(() => {
  browser.runtime.onInstalled.addListener(() => {
    browser.contextMenus.create({
      id: "ccc-send-image",
      title: "Send to Szurubooru",
      contexts: ["image", "video"],
    });

    browser.contextMenus.create({
      id: "ccc-send-link",
      title: "Send link to Szurubooru",
      contexts: ["link"],
    });

    browser.contextMenus.create({
      id: "ccc-send-page",
      title: "Send page URL to Szurubooru",
      contexts: ["page"],
    });
  });

  browser.contextMenus.onClicked.addListener(async (info, tab) => {
    let url: string | undefined;

    switch (info.menuItemId) {
      case "ccc-send-image":
        url = tab?.url ?? info.srcUrl;
        break;
      case "ccc-send-link":
        url = info.linkUrl;
        break;
      case "ccc-send-page":
        url = info.pageUrl ?? tab?.url;
        break;
    }

    if (!url) return;

    const tabId = tab?.id;

    try {
      const job = await submitJob(url);
      console.log("[CCC] Job created:", job.id);

      if (browser.notifications) {
        browser.notifications.create({
          type: "basic",
          iconUrl: browser.runtime.getURL("icon/128.png"),
          title: "Szurubooru Companion",
          message: `Queued. You'll be notified when it finishes.`,
        });
      }

      pollUntilDone(job.id, tabId, Date.now());
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error("[CCC] Failed to submit job:", err);
      await showToastAndNotification(
        message.slice(0, 200),
        "Szurubooru Companion – Error",
        "error",
        tabId
      );
    }
  });
});
