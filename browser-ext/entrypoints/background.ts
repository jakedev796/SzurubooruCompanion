/**
 * Background entrypoint – registers context menu items and handles clicks.
 * Context menu: "Send to Szurubooru" on image/video, "Send link to Szurubooru" on links.
 * Polls job status and shows a toast + notification when the job finishes or fails.
 * Also handles messages from content scripts for DOM-level media extraction (floating button).
 */
import {
  fetchJob,
  submitJob,
  getNotificationsEnabled,
  getDefaultSafety,
  type SafetyRating,
} from "../utils/api";
import { isRejectedJobUrl } from "../utils/job_url_validation";
import { fetchMediaBlob } from "../utils/media_bytes";
import { deriveUploadFilename, uploadBlobAsJob } from "../utils/upload";
import { planMediaFetch } from "../utils/url_reachability";
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

/** Everything needed to turn one right-click or button press into a job. */
interface SubmitTarget {
  /** Where the media itself lives – the URL we would read bytes from. */
  mediaUrl: string;
  /** URL handed to the backend when it can download itself (often a post page). */
  jobUrl: string;
  source?: string;
  tags?: string[];
  safety?: SafetyRating;
  filename?: string;
}

/**
 * Submit one piece of media, uploading the bytes ourselves when the backend
 * has no way to fetch the URL (loopback servers, blob:/data: URLs).
 */
async function submitMedia(
  target: SubmitTarget,
  tabId?: number
): Promise<{ id: string; status: string }> {
  const plan = planMediaFetch(target.mediaUrl);

  if (plan.strategy === "backend") {
    if (isRejectedJobUrl(target.jobUrl)) {
      throw new Error("Use a direct link to a post or media, not a feed or homepage");
    }
    return submitJob(target.jobUrl, {
      source: target.source,
      tags: target.tags,
      safety: target.safety,
    });
  }

  if (plan.strategy === "unsupported") {
    throw new Error(`Can't send this media: ${plan.reason}.`);
  }

  console.log(`[CCC] Uploading bytes instead of a URL – ${plan.reason}`);

  let blob: Blob;
  try {
    blob = await fetchMediaBlob(target.mediaUrl, plan, tabId);
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    throw new Error(`Couldn't read this media: ${detail}.`);
  }

  const filename = deriveUploadFilename(target.mediaUrl, blob.type, target.filename);
  return uploadBlobAsJob(blob, filename, {
    source: target.source,
    tags: target.tags,
    safety: target.safety,
  });
}

/**
 * Handle SUBMIT_JOB message from content scripts.
 */
async function handleSubmitJob(
  mediaInfo: MediaInfo,
  tabId?: number
): Promise<BackgroundScriptResponse> {
  try {
    // Checked here as well as inside submitMedia so the content script can
    // render this one itself without a duplicate toast from the error path.
    if (isRejectedJobUrl(mediaInfo.url)) {
      return {
        success: false,
        error: "Use a direct link to a post or media, not a feed or homepage",
      };
    }
    const defaultSafety = await getDefaultSafety();
    const job = await submitMedia(
      {
        mediaUrl: mediaInfo.url,
        jobUrl: mediaInfo.url,
        source: mediaInfo.source,
        tags: mediaInfo.tags,
        safety: mediaInfo.safety ?? defaultSafety,
        filename: mediaInfo.filename,
      },
      tabId
    );
    
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
    let target: SubmitTarget | undefined;

    switch (info.menuItemId) {
      case "ccc-send-image": {
        const pageUrl = tab?.url;
        // The page URL is preferred so the backend can resolve full-size media
        // with gallery-dl. When the page lives somewhere only this browser can
        // reach, take the media element instead and upload its bytes.
        if (pageUrl && planMediaFetch(pageUrl).strategy === "backend") {
          target = { mediaUrl: pageUrl, jobUrl: pageUrl };
        } else if (info.srcUrl) {
          target = { mediaUrl: info.srcUrl, jobUrl: info.srcUrl, source: pageUrl };
        } else if (pageUrl) {
          target = { mediaUrl: pageUrl, jobUrl: pageUrl };
        }
        break;
      }
      case "ccc-send-link":
        if (info.linkUrl) {
          target = { mediaUrl: info.linkUrl, jobUrl: info.linkUrl };
        }
        break;
    }

    if (!target) return;

    const tabId = tab?.id;

    try {
      const defaultSafety = await getDefaultSafety();
      const job = await submitMedia({ ...target, safety: defaultSafety }, tabId);
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
