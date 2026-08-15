/**
 * Read media bytes that only the client can reach.
 *
 * Two tiers, cheapest first:
 *   1. The background worker fetches the URL directly. Host permissions cover
 *      every origin, so this handles loopback servers and data: URLs.
 *   2. The bytes are read inside the tab and handed back. Needed for blob:
 *      URLs (scoped to the document that created them) and for anything that
 *      only loads with the page's own session.
 *
 * Tier 2 returns a data: URL rather than uploading from the page, so the CCC
 * access token never leaves the background worker. That costs base64 overhead
 * on the way back, hence the size ceiling.
 */

import { PAGE_FETCH_MAX_BYTES, type MediaFetchPlan } from "./url_reachability";

/**
 * Runs inside the target tab. Must be entirely self-contained: this function
 * is serialized and injected, so it cannot close over anything from here.
 */
async function readMediaInPage(
  url: string,
  maxBytes: number
): Promise<{ ok: true; dataUrl: string } | { ok: false; error: string }> {
  try {
    const res = await fetch(url, { credentials: "include" });
    if (!res.ok) {
      return { ok: false, error: `the page returned HTTP ${res.status}` };
    }

    const blob = await res.blob();
    if (blob.size === 0) {
      return { ok: false, error: "the media came back empty" };
    }
    if (blob.size > maxBytes) {
      const mb = (blob.size / (1024 * 1024)).toFixed(1);
      const capMb = Math.round(maxBytes / (1024 * 1024));
      return {
        ok: false,
        error: `it is ${mb} MB, over the ${capMb} MB limit for media read from a page`,
      };
    }

    const dataUrl = await new Promise<string>((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error ?? new Error("read failed"));
      reader.readAsDataURL(blob);
    });

    return { ok: true, dataUrl };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
}

/** Turn a data: URL back into a Blob. Safe in a service worker; FileReader is not. */
async function dataUrlToBlob(dataUrl: string): Promise<Blob> {
  const res = await fetch(dataUrl);
  return res.blob();
}

async function fetchInBackground(url: string): Promise<Blob> {
  const res = await fetch(url, { credentials: "include" });
  if (!res.ok) {
    throw new Error(`the server returned HTTP ${res.status}`);
  }
  return res.blob();
}

/** The scripting API is absent on some builds (notably Firefox MV2). */
function canInjectIntoPages(): boolean {
  return typeof browser !== "undefined" && !!browser.scripting?.executeScript;
}

async function fetchInPage(url: string, tabId: number): Promise<Blob> {
  let results;
  try {
    results = await browser.scripting.executeScript({
      target: { tabId },
      func: readMediaInPage,
      args: [url, PAGE_FETCH_MAX_BYTES],
    });
  } catch (err) {
    throw new Error(
      `this page does not allow the extension to read its media (${
        err instanceof Error ? err.message : String(err)
      })`
    );
  }

  const outcome = results?.[0]?.result as
    | { ok: true; dataUrl: string }
    | { ok: false; error: string }
    | undefined;

  if (!outcome) {
    throw new Error("the page did not return any media");
  }
  if (!outcome.ok) {
    throw new Error(outcome.error);
  }

  return dataUrlToBlob(outcome.dataUrl);
}

/**
 * Fetch the bytes for a URL the backend cannot reach.
 *
 * Falls back from the background worker to in-page reading, since a loopback
 * URL may still be gated behind the page's own session.
 */
export async function fetchMediaBlob(
  url: string,
  plan: MediaFetchPlan,
  tabId?: number
): Promise<Blob> {
  let blob: Blob | null = null;
  let backgroundError: unknown = null;

  if (plan.strategy === "extension") {
    try {
      blob = await fetchInBackground(url);
    } catch (err) {
      backgroundError = err;
    }
  }

  if (!blob) {
    if (tabId === undefined || !canInjectIntoPages()) {
      // No page tier available: report why the direct attempt failed, or say
      // plainly that this browser cannot read page-scoped media.
      if (backgroundError instanceof Error) throw backgroundError;
      throw new Error(
        tabId === undefined
          ? "it can only be read from the tab it came from"
          : "this browser build cannot read media out of a page"
      );
    }
    blob = await fetchInPage(url, tabId);
  }

  // Mirrors the backend's guard: hotlink-protection pages and plain links to
  // HTML come back as markup, and uploading that as media is never right.
  const contentType = blob.type.split(";")[0].trim().toLowerCase();
  if (contentType === "text/html" || contentType === "application/xhtml+xml") {
    throw new Error("that link is a web page, not a media file");
  }

  return blob;
}
