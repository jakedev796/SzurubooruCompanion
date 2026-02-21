/**
 * Background entrypoint – registers context menu items and handles clicks.
 * Context menu: "Send to Szurubooru" on image/video, "Send link to Szurubooru" on links.
 * Polls job status and shows a toast + notification when the job finishes or fails.
 * Also handles messages from content scripts for DOM-level media extraction (floating button).
 */
import { fetchJob, submitJob, getNotificationsEnabled, getDefaultSafety } from "../utils/api";
import { isRejectedJobUrl } from "../utils/job_url_validation";
import type { MediaInfo, ContentScriptMessage, BackgroundScriptResponse } from "../utils/types";

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
  const notificationsEnabled = await getNotificationsEnabled();
  if (notificationsEnabled && browser.notifications) {
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
    if (job.status === "paused" || job.status === "stopped") {
      await showToastAndNotification(
        `Job was ${job.status}.`,
        "Szurubooru Companion",
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
      "Job is still processing. Check the SzuruCompanion Dashboard.",
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

/**
 * Handle SUBMIT_JOB message from content scripts.
 */
async function handleSubmitJob(
  mediaInfo: MediaInfo,
  tabId?: number
): Promise<BackgroundScriptResponse> {
  try {
    if (isRejectedJobUrl(mediaInfo.url)) {
      return {
        success: false,
        error: "Use a direct link to a post or media, not a feed or homepage",
      };
    }
    const defaultSafety = await getDefaultSafety();
    const job = await submitJob(mediaInfo.url, {
      source: mediaInfo.source,
      tags: mediaInfo.tags,
      safety: mediaInfo.safety ?? defaultSafety,
    });
    
    console.log("[CCC] Job created from content script:", job.id, mediaInfo);
    
    const notificationsEnabled = await getNotificationsEnabled();
    if (notificationsEnabled && browser.notifications) {
      browser.notifications.create({
        type: "basic",
        iconUrl: browser.runtime.getURL("icon/128.png"),
        title: "Szurubooru Companion",
        message: `Queued. You'll be notified when it finishes.`,
      });
    }

    // Start polling
    pollUntilDone(job.id, tabId, Date.now());
    
    return { success: true, jobId: job.id };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[CCC] Failed to submit job from content script:", err);
    
    await showToastAndNotification(
      message.slice(0, 200),
      "Szurubooru Companion – Error",
      "error",
      tabId
    );
    
    return { success: false, error: message };
  }
}

export default defineBackground(() => {
  // Create context menus on install
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
  });

  // Handle context menu clicks
  browser.contextMenus.onClicked.addListener(async (info, tab) => {
    let url: string | undefined;

    switch (info.menuItemId) {
      case "ccc-send-image":
        url = tab?.url ?? info.srcUrl;
        break;
      case "ccc-send-link":
        url = info.linkUrl;
        break;
    }

    if (!url) return;
    if (isRejectedJobUrl(url)) {
      await showToastAndNotification(
        "Use a direct link to a post or media, not a feed or homepage",
        "Szurubooru Companion – Error",
        "error",
        tab?.id
      );
      return;
    }

    const tabId = tab?.id;

    try {
      const defaultSafety = await getDefaultSafety();
      const job = await submitJob(url, { safety: defaultSafety });
      console.log("[CCC] Job created:", job.id);

      const notificationsEnabled = await getNotificationsEnabled();
      if (notificationsEnabled && browser.notifications) {
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

  // Handle messages from content scripts
  browser.runtime.onMessage.addListener(
    (message: ContentScriptMessage, sender, sendResponse) => {
      if (message.action === "SUBMIT_JOB") {
        // Handle async response
        handleSubmitJob(message.payload, sender.tab?.id)
          .then(sendResponse)
          .catch((err) => {
            sendResponse({ success: false, error: err.message });
          });
        return true; // Keep channel open for async response
      }
      
      return false;
    }
  );
});
