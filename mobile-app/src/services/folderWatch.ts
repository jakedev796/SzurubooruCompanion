/**
 * Folder-watch service.
 * Periodically scans configured directories for new media files
 * and uploads them to the CCC as file jobs (no URL parsing).
 */

import RNFS from "react-native-fs";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { submitFileJob } from "./api";

const WATCHED_FOLDERS_KEY = "ccc_watched_folders";
const PROCESSED_FILES_KEY = "ccc_processed_files";

const MEDIA_EXTENSIONS = new Set([
  ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp",
  ".mp4", ".webm", ".mkv", ".avi", ".mov",
]);

export async function getWatchedFolders(): Promise<string[]> {
  try {
    const raw = await AsyncStorage.getItem(WATCHED_FOLDERS_KEY);
    if (raw) return JSON.parse(raw);
  } catch {}
  return [];
}

export async function setWatchedFolders(folders: string[]): Promise<void> {
  await AsyncStorage.setItem(WATCHED_FOLDERS_KEY, JSON.stringify(folders));
}

async function getProcessedFiles(): Promise<Set<string>> {
  try {
    const raw = await AsyncStorage.getItem(PROCESSED_FILES_KEY);
    if (raw) return new Set(JSON.parse(raw));
  } catch {}
  return new Set();
}

async function markProcessed(filePath: string): Promise<void> {
  const processed = await getProcessedFiles();
  processed.add(filePath);
  await AsyncStorage.setItem(PROCESSED_FILES_KEY, JSON.stringify([...processed]));
}

/**
 * Scan all watched folders for new media files and upload them.
 * Returns the number of files uploaded.
 */
export async function scanAndUpload(): Promise<number> {
  const folders = await getWatchedFolders();
  if (folders.length === 0) return 0;

  const processed = await getProcessedFiles();
  let uploaded = 0;

  for (const folder of folders) {
    try {
      const exists = await RNFS.exists(folder);
      if (!exists) continue;

      const items = await RNFS.readDir(folder);
      for (const item of items) {
        if (!item.isFile()) continue;

        const ext = item.name.substring(item.name.lastIndexOf(".")).toLowerCase();
        if (!MEDIA_EXTENSIONS.has(ext)) continue;
        if (processed.has(item.path)) continue;

        try {
          await submitFileJob(item.path, item.name);
          await markProcessed(item.path);
          uploaded++;
        } catch (err) {
          console.warn("[FolderWatch] Failed to upload", item.name, err);
        }
      }
    } catch (err) {
      console.warn("[FolderWatch] Error scanning", folder, err);
    }
  }

  return uploaded;
}
