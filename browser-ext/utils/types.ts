/**
 * Type definitions for DOM-level media extraction.
 */

/**
 * Represents extracted media information from a web page.
 */
export interface MediaInfo {
  /** Direct media URL to download */
  url: string;
  /** Source URL - the note/tweet/post page */
  source?: string;
  /** Secondary sources - user profile, etc. */
  secondarySources?: string[];
  /** Tags extracted from the page */
  tags?: string[];
  /** Safety rating */
  safety?: 'safe' | 'sketchy' | 'unsafe';
  /** Media type */
  type: 'image' | 'video';
  /** Suggested filename */
  filename?: string;
  /** Skip automatic tagging */
  skipTagging?: boolean;
  /** Site-specific metadata */
  metadata?: Record<string, unknown>;
}

/**
 * Site-specific extractor interface.
 */
export interface SiteExtractor {
  /** Unique identifier for this extractor */
  name: string;
  /** Check if this extractor matches the current page */
  matches(url: string): boolean;
  /** Extract media info from a media element */
  extract(mediaElement: HTMLElement, mediaUrl: string): Promise<MediaInfo | null>;
  /** Find all grabbable media on the page */
  findGrabbableMedia(): HTMLElement[];
  /** Check if an element is grabbable */
  isGrabbable(element: HTMLElement): boolean;
}

/**
 * Message types for communication between content script and background script.
 */
export type ContentScriptMessage = 
  | { action: 'SUBMIT_JOB'; payload: MediaInfo }
  | { action: 'GET_PAGE_INFO' }
  | { action: 'PAGE_INFO'; payload: { url: string; title: string } };

/**
 * Response types from background script.
 */
export type BackgroundScriptResponse = 
  | { success: true; jobId: string }
  | { success: false; error: string };
