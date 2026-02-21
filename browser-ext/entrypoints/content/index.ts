/**
 * Content script entry point.
 * 
 * Initializes site-specific extractors and the floating button.
 * Handles communication with the background script.
 */

import type { SiteExtractor, MediaInfo, ContentScriptMessage } from '../../utils/types';
import { getMediaUrl, isThumbnailOrSampleMediaUrl } from '../../utils/extractors/common';
import { isRejectedJobUrl } from '../../utils/job_url_validation';
import { initFloatingButton, isGrabbableMedia, showToast } from './floating-button';

// Import all extractors
import { misskeyExtractor } from './sites/misskey';
import { twitterExtractor } from './sites/twitter';
import { danbooruExtractor } from './sites/danbooru';
import { gelbooruExtractor } from './sites/gelbooru';
import { rule34Extractor } from './sites/rule34';
import { yandeExtractor } from './sites/yande';
import { redditExtractor } from './sites/reddit';

/** All available extractors */
const extractors: SiteExtractor[] = [
  misskeyExtractor,
  twitterExtractor,
  danbooruExtractor,
  gelbooruExtractor,
  rule34Extractor,
  yandeExtractor,
  redditExtractor,
];

/** Current active extractor for this page */
let activeExtractor: SiteExtractor | null = null;

/**
 * Find the appropriate extractor for the current page.
 */
function findExtractor(): SiteExtractor | null {
  const url = window.location.href;
  
  for (const extractor of extractors) {
    if (extractor.matches(url)) {
      return extractor;
    }
  }
  
  return null;
}

/**
 * Validate URL format.
 * Returns true if URL is valid (has http/https scheme and host), false otherwise.
 */
function validateUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  
  try {
    const urlObj = new URL(url);
    // Check for valid scheme (http/https) and host
    return (urlObj.protocol === 'http:' || urlObj.protocol === 'https:') && 
           urlObj.hostname.length > 0;
  } catch {
    return false;
  }
}

/**
 * Get the media URL from an element.
 * For VIDEO with no src yet (lazy-loaded), returns '' so the extractor can run and provide the post/tweet URL.
 */
function getElementMediaUrl(element: HTMLElement): string | null {
  const url = getMediaUrl(element);
  if (url && validateUrl(url)) return url;

  if (element.tagName === 'VIDEO') {
    return '';
  }

  if (element.tagName !== 'IMG' && element.tagName !== 'VIDEO') {
    const bgImage = window.getComputedStyle(element).backgroundImage;
    const match = bgImage.match(/url\(['"]?([^'")]+)['"]?\)/);
    if (match && validateUrl(match[1])) return match[1];
  }

  return null;
}

/**
 * Handle media grab from floating button click.
 */
async function handleMediaGrab(mediaElement: HTMLElement): Promise<void> {
  if (!activeExtractor) {
    showToast('No extractor available for this page', 'error');
    return;
  }
  
  const mediaUrl = getElementMediaUrl(mediaElement);
  if (mediaUrl === null && mediaElement.tagName !== 'VIDEO') {
    showToast('Could not find media URL', 'error');
    return;
  }

  const urlForExtract = mediaUrl ?? '';
  const urlForLog = urlForExtract || '(video – extractor will provide URL)';
  console.log('[CCC] Extracting media from:', mediaElement.tagName, urlForLog);

  try {
    const mediaInfo = await activeExtractor.extract(mediaElement, urlForExtract);
    
    if (!mediaInfo) {
      showToast('Could not extract media info', 'error');
      return;
    }

    // Never send thumbnail/sample URLs; use post/source URL so backend resolves full media
    if (isThumbnailOrSampleMediaUrl(mediaInfo.url) && mediaInfo.source && !isThumbnailOrSampleMediaUrl(mediaInfo.source)) {
      mediaInfo.url = mediaInfo.source;
    }

    console.log('[CCC] Extracted media info:', mediaInfo);

    if (!validateUrl(mediaInfo.url)) {
      showToast('Invalid URL format', 'error');
      return;
    }
    if (isRejectedJobUrl(mediaInfo.url)) {
      showToast('Use a direct link to a post or media, not a feed or homepage', 'error');
      return;
    }
    if (mediaInfo.source && isRejectedJobUrl(mediaInfo.source)) {
      showToast('Use a direct link to a post or media, not a feed or homepage', 'error');
      return;
    }

    // Send to background script
    const message: ContentScriptMessage = {
      action: 'SUBMIT_JOB',
      payload: mediaInfo,
    };
    
    // Use the global browser API (provided by WXT)
    const response = await browser.runtime.sendMessage(message);
    
    if (response && (response as any).success) {
      showToast(`Job queued: ${(response as any).jobId}`, 'success');
    } else {
      showToast((response as any)?.error || 'Failed to submit job', 'error');
    }
  } catch (error) {
    console.error('[CCC] Error extracting media:', error);
    showToast(
      error instanceof Error ? error.message : 'Unknown error',
      'error'
    );
  }
}

/**
 * Set up MutationObserver for dynamic content.
 */
function setupMutationObserver(): void {
  const observer = new MutationObserver((mutations) => {
    // Check if any new media elements were added
    for (const mutation of mutations) {
      if (mutation.type === 'childList') {
        for (const node of mutation.addedNodes) {
          if (node instanceof HTMLElement) {
            // Check if it's a media element or contains one
            const mediaElements = node.querySelectorAll('img, video');
            if (mediaElements.length > 0 || node.tagName === 'IMG' || node.tagName === 'VIDEO') {
              // The floating button will handle these via event delegation
              // Just log for debugging
              console.log('[CCC] New media elements detected');
              break;
            }
          }
        }
      }
    }
  });
  
  observer.observe(document.body, {
    childList: true,
    subtree: true,
  });
}

/**
 * Initialize the content script.
 */
function init(): void {
  console.log('[CCC] Content script initializing on:', window.location.href);
  
  // Find the appropriate extractor
  activeExtractor = findExtractor();
  
  if (!activeExtractor) {
    console.log('[CCC] No extractor found for this page');
    return;
  }
  
  console.log('[CCC] Using extractor:', activeExtractor.name);
  
  const cleanup = initFloatingButton(
    handleMediaGrab,
    (el) => activeExtractor?.isGrabbable(el) ?? isGrabbableMedia(el)
  );
  
  // Set up mutation observer for dynamic content
  setupMutationObserver();
  
  // Log found media for debugging
  const grabbableMedia = activeExtractor.findGrabbableMedia();
  console.log(`[CCC] Found ${grabbableMedia.length} grabbable media elements`);
  
  // Handle page unload
  window.addEventListener('beforeunload', () => {
    cleanup();
  });
}

export default defineContentScript({
  matches: [
    '*://*.twitter.com/*',
    '*://*.x.com/*',
    '*://*.misskey.io/*',
    '*://*.misskey.art/*',
    '*://*.misskey.net/*',
    '*://*.misskey.design/*',
    '*://*.misskey.xyz/*',
    '*://*.mi.0px.io/*',
    '*://*.misskey.pizza/*',
    '*://*.misskey.cloud/*',
    '*://danbooru.donmai.us/*',
    '*://safebooru.org/*',
    '*://*.gelbooru.com/*',
    '*://rule34.xxx/*',
    '*://yande.re/*',
    '*://reddit.com/*',
    '*://*.reddit.com/*',
  ],
  runAt: 'document_idle',
  
  main() {
    // Listen for messages from background script
    browser.runtime.onMessage.addListener((message: ContentScriptMessage, sender, sendResponse) => {
      if (message.action === 'GET_PAGE_INFO') {
        sendResponse({
          url: window.location.href,
          title: document.title,
        });
        return true;
      }
      
      return false;
    });
    
    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', init);
    } else {
      init();
    }
  },
});

export { activeExtractor, extractors };
