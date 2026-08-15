/**
 * Chunked byte upload from the extension.
 *
 * Used when the backend cannot fetch a URL itself (see utils/url_reachability.ts):
 * the extension reads the bytes and pushes them through the same three-step
 * upload API the mobile app uses.
 *
 *   1. POST /api/jobs/upload/init             -> session_id, chunk_size, total_chunks
 *   2. POST /api/jobs/upload/chunk/{id}/{n}   -> one chunk at a time
 *   3. POST /api/jobs/upload/complete/{id}    -> reassemble + create the job
 *
 * Individual chunks are retried; an unrecoverable failure aborts the session
 * server-side so its disk space is released without waiting out the 24h TTL.
 */

import { authFetch } from "./api";
import type { SafetyRating } from "./api";

const CHUNK_ATTEMPTS = 3;

export interface UploadJobOptions {
  source?: string;
  tags?: string[];
  safety?: SafetyRating;
  skipTagging?: boolean;
}

/**
 * MIME -> extension, mirroring the backend's COMMON_MIME_TYPES map
 * (ccc/backend/app/utils/mime.py). The backend guesses a file's type from its
 * name, so an extension-less upload has to be named before it is sent.
 */
const MIME_EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/gif": "gif",
  "image/webp": "webp",
  "image/avif": "avif",
  "image/heic": "heic",
  "image/heif": "heif",
  "image/bmp": "bmp",
  "image/tiff": "tiff",
  "image/svg+xml": "svg",
  "video/mp4": "mp4",
  "video/webm": "webm",
  "video/x-matroska": "mkv",
  "video/x-msvideo": "avi",
  "video/quicktime": "mov",
  "video/x-ms-wmv": "wmv",
  "video/x-flv": "flv",
  "audio/mpeg": "mp3",
  "audio/wav": "wav",
  "audio/ogg": "ogg",
  "audio/mp4": "m4a",
};

/** Map a Content-Type to a file extension, ignoring parameters like "; charset=". */
export function extensionForMime(mimeType: string | undefined): string | null {
  if (!mimeType) return null;
  const base = mimeType.split(";")[0].trim().toLowerCase();
  return MIME_EXTENSIONS[base] ?? null;
}

/**
 * Build a filename for an uploaded blob.
 *
 * blob:/data: URLs have no meaningful path, so those fall back to a timestamp.
 * An extension is appended only when the name has none – we never second-guess
 * a name the page already gave us.
 */
export function deriveUploadFilename(
  url: string,
  mimeType: string | undefined,
  suggested?: string
): string {
  let base = (suggested ?? "").trim();

  if (!base) {
    try {
      const parsed = new URL(url);
      if (parsed.protocol === "http:" || parsed.protocol === "https:") {
        const last = parsed.pathname.split("/").filter(Boolean).pop() ?? "";
        base = decodeURIComponent(last);
      }
    } catch {
      // Fall through to the timestamp fallback.
    }
  }

  // Collapse anything that would turn into a path or upset a filesystem.
  base = base.replace(/[\\/:*?"<>|]+/g, "_").trim();
  if (!base) {
    base = `media_${Date.now()}`;
  }
  if (base.length > 128) {
    base = base.slice(0, 128);
  }

  if (!/\.[a-z0-9]{2,5}$/i.test(base)) {
    const ext = extensionForMime(mimeType);
    if (ext) base = `${base}.${ext}`;
  }

  return base;
}

async function responseError(res: Response): Promise<string> {
  try {
    const text = await res.text();
    return text ? `${res.status}: ${text.slice(0, 300)}` : `${res.status}`;
  } catch {
    return `${res.status}`;
  }
}

function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Best-effort session cleanup; failures here must not mask the real error. */
async function abortSession(sessionId: string): Promise<void> {
  try {
    await authFetch(`/api/jobs/upload/${sessionId}`, (headers) => ({
      method: "DELETE",
      headers,
    }));
  } catch (err) {
    console.warn("[CCC] Failed to abort upload session", sessionId, err);
  }
}

async function sendChunk(
  sessionId: string,
  index: number,
  slice: Blob,
  totalChunks: number
): Promise<void> {
  let lastError: unknown = null;

  for (let attempt = 0; attempt < CHUNK_ATTEMPTS; attempt++) {
    try {
      const res = await authFetch(
        `/api/jobs/upload/chunk/${sessionId}/${index}`,
        (headers) => {
          // Fresh FormData per attempt – see the note on authFetch.
          const form = new FormData();
          form.append("chunk", slice, `chunk_${index}`);
          return { method: "POST", headers, body: form };
        },
        null
      );
      if (res.ok) return;
      lastError = new Error(await responseError(res));
    } catch (err) {
      lastError = err;
    }

    if (attempt < CHUNK_ATTEMPTS - 1) {
      await delay(1000 * 2 ** attempt);
    }
  }

  throw new Error(
    `Upload failed on chunk ${index + 1} of ${totalChunks}: ${errorMessage(lastError)}`
  );
}

/**
 * Upload a blob as a new CCC job. Returns the created job.
 */
export async function uploadBlobAsJob(
  blob: Blob,
  filename: string,
  opts: UploadJobOptions = {}
): Promise<{ id: string; status: string }> {
  if (blob.size === 0) {
    throw new Error("The media came back empty (0 bytes).");
  }

  const initBody: Record<string, unknown> = {
    filename,
    total_size: blob.size,
  };
  if (opts.safety) initBody.safety = opts.safety;
  if (opts.skipTagging !== undefined) initBody.skip_tagging = opts.skipTagging;
  if (opts.tags?.length) initBody.tags = opts.tags.join(",");
  if (opts.source) initBody.source = opts.source;

  const initRes = await authFetch("/api/jobs/upload/init", (headers) => ({
    method: "POST",
    headers,
    body: JSON.stringify(initBody),
  }));

  if (!initRes.ok) {
    throw new Error(`Could not start upload (${await responseError(initRes)})`);
  }

  let init: { session_id: string; chunk_size: number; total_chunks: number };
  try {
    init = await initRes.json();
  } catch (err) {
    // The session exists server-side even though we cannot address it; it will
    // be reclaimed by the 24h TTL sweep.
    throw new Error(`Upload session response could not be read: ${errorMessage(err)}`);
  }

  console.log(
    `[CCC] Uploading ${filename} (${blob.size} bytes) in ${init.total_chunks} chunk(s)`
  );

  try {
    for (let i = 0; i < init.total_chunks; i++) {
      const start = i * init.chunk_size;
      const end = Math.min(start + init.chunk_size, blob.size);
      await sendChunk(init.session_id, i, blob.slice(start, end), init.total_chunks);
    }

    const completeRes = await authFetch(
      `/api/jobs/upload/complete/${init.session_id}`,
      (headers) => ({ method: "POST", headers })
    );

    if (!completeRes.ok) {
      throw new Error(`Could not finish upload (${await responseError(completeRes)})`);
    }

    return (await completeRes.json()) as { id: string; status: string };
  } catch (err) {
    await abortSession(init.session_id);
    throw err;
  }
}
