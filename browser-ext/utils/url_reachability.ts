/**
 * Decide who can actually read the bytes behind a media URL.
 *
 * The backend downloads job URLs from its own network namespace (usually a
 * container, often on another machine entirely). A URL like
 * http://localhost:8080/img.png means "this browser's machine" to us and
 * "this container" to the backend, so handing it over as a URL job can only
 * ever fail. Same story for blob:/data: URLs, which exist nowhere but here.
 *
 * When the client is the only party that can read the bytes, the extension
 * fetches them and uploads them through the chunked upload API instead of
 * sending a URL. See utils/upload.ts.
 */

/** Largest response we will pull through the page-injection path (see upload.ts). */
export const PAGE_FETCH_MAX_BYTES = 32 * 1024 * 1024;

export type MediaFetchPlan =
  /** Normal path: hand the URL to the backend and let it download. */
  | { strategy: 'backend' }
  /** The extension's background worker can fetch the bytes itself. */
  | { strategy: 'extension'; reason: string }
  /** Only the page that created the URL can read it; inject and fetch there. */
  | { strategy: 'page'; reason: string }
  /** Nobody can read it from here; tell the user why. */
  | { strategy: 'unsupported'; reason: string };

/** blob:/filesystem: URLs are scoped to the document that minted them. */
const PAGE_SCOPED_SCHEMES = ['blob:', 'filesystem:'];

/** Strip the brackets the URL parser keeps on IPv6 literals ("[::1]" -> "::1"). */
function bareHost(host: string): string {
  return host.toLowerCase().replace(/^\[/, '').replace(/\]$/, '');
}

/**
 * Hosts that resolve to the *client's* own machine, so the backend either
 * cannot reach them or would reach itself instead.
 */
export function isLoopbackHost(host: string): boolean {
  const h = bareHost(host);
  if (!h) return false;
  if (h === 'localhost' || h.endsWith('.localhost')) return true;
  if (/^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(h)) return true;
  if (h === '::1' || h === '0:0:0:0:0:0:0:1') return true;
  if (h.startsWith('::ffff:127.')) return true;
  // "unspecified" addresses resolve to the local host in a browser address bar.
  if (h === '0.0.0.0' || h === '::') return true;
  return false;
}

/**
 * Work out how to get at a URL's bytes.
 *
 * Only loopback hosts are treated as client-only for now. Private/LAN ranges
 * (RFC1918, link-local, .local, single-label hosts) are deliberately left on
 * the backend path: a self-hosted booru at 192.168.1.10 may well be reachable
 * from the backend, and its *post pages* need gallery-dl to resolve full-size
 * media — fetching those bytes here would upload the HTML page instead. That
 * case is handled server-side, where the backend knows what it can reach.
 */
export function planMediaFetch(url: string | null | undefined): MediaFetchPlan {
  if (!url || !url.trim()) {
    return { strategy: 'unsupported', reason: 'no URL was found for this media' };
  }

  let parsed: URL;
  try {
    parsed = new URL(url.trim());
  } catch {
    return { strategy: 'unsupported', reason: 'the URL could not be parsed' };
  }

  const scheme = parsed.protocol.toLowerCase();

  if (PAGE_SCOPED_SCHEMES.includes(scheme)) {
    return {
      strategy: 'page',
      reason: `${scheme.replace(':', '')} URLs only exist inside the page that created them`,
    };
  }

  // data: URLs carry their own bytes, and the background worker can read them.
  if (scheme === 'data:') {
    return { strategy: 'extension', reason: 'the media is embedded in the page as a data: URL' };
  }

  if (scheme === 'file:') {
    return {
      strategy: 'unsupported',
      reason: 'local file:// URLs cannot be read by the extension; upload the file from the dashboard or mobile app instead',
    };
  }

  if (scheme !== 'http:' && scheme !== 'https:') {
    return { strategy: 'unsupported', reason: `${scheme.replace(':', '')} URLs are not supported` };
  }

  if (isLoopbackHost(parsed.hostname)) {
    return {
      strategy: 'extension',
      reason: `${parsed.hostname} points at this computer, which the backend cannot reach`,
    };
  }

  return { strategy: 'backend' };
}

/** True when the backend can be expected to download this URL itself. */
export function isBackendFetchable(url: string | null | undefined): boolean {
  return planMediaFetch(url).strategy === 'backend';
}
