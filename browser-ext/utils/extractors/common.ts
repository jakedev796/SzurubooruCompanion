/**
 * Common utilities for site-specific extractors.
 */

/**
 * Extract filename from a URL.
 * Tries to get the last path segment, falling back to a timestamp-based name.
 */
export function extractFilename(url: string): string {
  try {
    const urlObj = new URL(url);
    const pathname = urlObj.pathname;
    const segments = pathname.split('/').filter(Boolean);
    
    if (segments.length > 0) {
      const lastSegment = segments[segments.length - 1];
      // Remove query parameters and hash
      const cleanName = lastSegment.split('?')[0].split('#')[0];
      if (cleanName && cleanName.length > 0) {
        return cleanName;
      }
    }
  } catch {
    // Invalid URL, fall through
  }
  
  // Fallback to timestamp-based name
  return `media_${Date.now()}`;
}

/**
 * Sanitize a tag for Szurubooru compatibility.
 * - Converts to lowercase
 * - Replaces spaces with underscores
 * - Removes invalid characters
 * - Trims whitespace
 */
export function sanitizeTag(tag: string): string {
  return tag
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
    .replace(/[^\w\-_:]/g, '')
    .slice(0, 64); // Szurubooru tag length limit
}

/**
 * Extract hashtags from text content.
 * Returns an array of sanitized tags.
 */
export function extractHashtags(text: string): string[] {
  const hashtags: string[] = [];
  const matches = text.matchAll(/#(\w+)/g);
  
  for (const match of matches) {
    const tag = sanitizeTag(match[1]);
    if (tag.length >= 2) {
      hashtags.push(tag);
    }
  }
  
  return [...new Set(hashtags)]; // Remove duplicates
}

/**
 * Check if a URL is a valid media URL.
 */
export function isValidMediaUrl(url: string): boolean {
  try {
    const urlObj = new URL(url);
    // Check protocol
    if (!['http:', 'https:'].includes(urlObj.protocol)) {
      return false;
    }
    // Check for common media extensions or known CDN patterns
    const mediaPatterns = [
      /\.(jpg|jpeg|png|gif|webp|mp4|webm|gifv|mov)$/i,
      /\/media\//i,
      /\/img\//i,
      /\/image\//i,
      /twimg\.com/i,
      /cdn/i,
      /media\.misskey\./i,
    ];
    
    return mediaPatterns.some(pattern => pattern.test(url));
  } catch {
    return false;
  }
}

/**
 * Check if an element is a visible media element.
 */
export function isMediaElement(element: HTMLElement): element is HTMLImageElement | HTMLVideoElement {
  if (element.tagName === 'IMG') {
    const img = element as HTMLImageElement;
    // Check if image has loaded and has dimensions
    return img.complete && img.naturalWidth > 0 && img.naturalHeight > 0;
  }
  
  if (element.tagName === 'VIDEO') {
    const video = element as HTMLVideoElement;
    return video.readyState >= 1; // HAVE_METADATA
  }
  
  return false;
}

/**
 * Get the media URL from an element.
 */
export function getMediaUrl(element: HTMLElement): string | null {
  if (element.tagName === 'IMG') {
    return (element as HTMLImageElement).src;
  }
  
  if (element.tagName === 'VIDEO') {
    const video = element as HTMLVideoElement;
    // Try currentSrc first, then poster, then first source
    return video.currentSrc || video.poster || 
           video.querySelector('source')?.src || null;
  }
  
  return null;
}

/**
 * Determine if media is a video based on URL or element type.
 */
export function isVideoMedia(element: HTMLElement, url: string): boolean {
  if (element.tagName === 'VIDEO') {
    return true;
  }
  
  const videoExtensions = ['.mp4', '.webm', '.mov', '.gifv'];
  const lowerUrl = url.toLowerCase();
  
  return videoExtensions.some(ext => lowerUrl.includes(ext)) ||
         url.startsWith('blob:');
}

/**
 * Wait for an element to appear in the DOM.
 */
export function waitForElement(
  selector: string,
  timeout = 5000
): Promise<Element | null> {
  return new Promise((resolve) => {
    const element = document.querySelector(selector);
    if (element) {
      resolve(element);
      return;
    }
    
    const observer = new MutationObserver(() => {
      const el = document.querySelector(selector);
      if (el) {
        observer.disconnect();
        resolve(el);
      }
    });
    
    observer.observe(document.body, {
      childList: true,
      subtree: true,
    });
    
    setTimeout(() => {
      observer.disconnect();
      resolve(null);
    }, timeout);
  });
}

/**
 * Debounce a function.
 */
export function debounce<T extends (...args: unknown[]) => unknown>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  
  return (...args: Parameters<T>) => {
    if (timeoutId) {
      clearTimeout(timeoutId);
    }
    timeoutId = setTimeout(() => {
      fn(...args);
      timeoutId = null;
    }, delay);
  };
}
