/**
 * Background entrypoint – registers context menu items and handles clicks.
 */
import { submitJob, loadConfig } from "../utils/api";

export default defineBackground(() => {
  // Create context menus on install / startup.
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

  // Handle context menu clicks.
  browser.contextMenus.onClicked.addListener(async (info, _tab) => {
    let url: string | undefined;

    switch (info.menuItemId) {
      case "ccc-send-image":
        url = info.srcUrl;
        break;
      case "ccc-send-link":
        url = info.linkUrl;
        break;
      case "ccc-send-page":
        url = info.pageUrl;
        break;
    }

    if (!url) return;

    try {
      const job = await submitJob(url);
      console.log("[CCC] Job created:", job.id);

      // Try to show a notification (optional permission).
      if (browser.notifications) {
        browser.notifications.create({
          type: "basic",
          iconUrl: browser.runtime.getURL("icon/128.png"),
          title: "Szurubooru Companion",
          message: `Queued: ${url.slice(0, 80)}`,
        });
      }
    } catch (err: any) {
      console.error("[CCC] Failed to submit job:", err);
      if (browser.notifications) {
        browser.notifications.create({
          type: "basic",
          iconUrl: browser.runtime.getURL("icon/128.png"),
          title: "Szurubooru Companion – Error",
          message: err.message?.slice(0, 120) ?? "Unknown error",
        });
      }
    }
  });
});
