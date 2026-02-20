/**
 * Content script entry point.
 * 
 * Initializes site-specific extractors and the floating button.
 * Handles communication with the background script.
 */

import type { SiteExtractor, MediaInfo, ContentScriptMessage } from '../../utils/types';
import { getMediaUrl } from '../../utils/extractors/common';
import { initFloatingButton, showToast } from './floating-button';

// Import all extractors
import { misskeyExtractor } from './sites/misskey';
import { twitterExtractor } from './sites/twitter';
import { danbooruExtractor } from './sites/danbooru';
import { gelbooruExtractor } from './sites/gelbooru';
import { rule34Extractor } from './sites/rule34';
import { yandeExtractor } from './sites/yande';

/** All available extractors */
const extractors: SiteExtractor[] = [
  misskeyExtractor,
  twitterExtractor,
  danbooruExtractor,
  gelbooruExtractor,
  rule34Extractor,
  yandeExtractor,
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
 */
function getElementMediaUrl(element: HTMLElement): string | null {
  // First try the common utility
  const url = getMediaUrl(element);
  if (url && validateUrl(url)) return url;
  
  // Try background-image for divs
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
  
  // Get media URL
  const mediaUrl = getElementMediaUrl(mediaElement);
  if (!mediaUrl) {
    showToast('Could not find media URL', 'error');
    return;
  }
  
  console.log('[CCC] Extracting media from:', mediaElement.tagName, mediaUrl);
  
  try {
    // Extract media info using the site-specific extractor
    const mediaInfo = await activeExtractor.extract(mediaElement, mediaUrl);
    
    if (!mediaInfo) {
      showToast('Could not extract media info', 'error');
      return;
    }
    
    console.log('[CCC] Extracted media info:', mediaInfo);
    
    // Validate URL before submitting
    if (!validateUrl(mediaInfo.url)) {
      showToast('Invalid URL format', 'error');
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
  
  // Initialize floating button
  const cleanup = initFloatingButton(handleMediaGrab);
  
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
