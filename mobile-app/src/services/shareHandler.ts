/**
 * Handle incoming share intents (Android SEND / iOS Share Extension).
 * Parses the shared data and submits it to the CCC as a URL or file job.
 */

import ReceiveSharingIntent from "react-native-receive-sharing-intent";
import { submitUrlJob, submitFileJob } from "./api";

export interface ShareResult {
  success: boolean;
  jobId?: string;
  error?: string;
}

/** Check if a string looks like a URL. */
function isUrl(text: string): boolean {
  return /^https?:\/\//i.test(text.trim());
}

/**
 * Register the share intent listener.
 * Call once at app start-up (e.g. in App.tsx useEffect).
 */
export function registerShareListener(onResult: (r: ShareResult) => void): void {
  ReceiveSharingIntent.getReceivedFiles(
    async (files: any[]) => {
      for (const file of files) {
        try {
          // Shared text that looks like a URL → URL job.
          if (file.text && isUrl(file.text)) {
            const job = await submitUrlJob(file.text.trim());
            onResult({ success: true, jobId: job.id });
            continue;
          }

          // Shared file → file upload job.
          if (file.filePath || file.contentUri) {
            const uri = file.filePath || file.contentUri;
            const name = file.fileName || "shared_file";
            const job = await submitFileJob(uri, name);
            onResult({ success: true, jobId: job.id });
            continue;
          }

          // Shared plain text containing a URL.
          if (file.weblink && isUrl(file.weblink)) {
            const job = await submitUrlJob(file.weblink.trim());
            onResult({ success: true, jobId: job.id });
            continue;
          }

          onResult({ success: false, error: "Unsupported share content." });
        } catch (err: any) {
          onResult({ success: false, error: err.message });
        }
      }
    },
    (error: any) => {
      onResult({ success: false, error: String(error) });
    },
    "com.szuruboorucompanion" // Android package name
  );
}

/** Call on unmount to clear the listener. */
export function clearShareListener(): void {
  ReceiveSharingIntent.clearReceivedFiles();
}
