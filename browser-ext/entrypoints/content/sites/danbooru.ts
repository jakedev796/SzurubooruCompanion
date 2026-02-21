/**
 * Danbooru/Safebooru extractor for DOM-level media extraction.
 * 
 * Extracts tags by category and original image URLs.
 */

import type { SiteExtractor, MediaInfo } from '../../../utils/types';
import { extractFilename, sanitizeTag, isVideoMedia } from '../../../utils/extractors/common';

/**
 * Check if a URL belongs to Danbooru or Safebooru.
 */
export function isDanbooruUrl(url: string): boolean {
  return /danbooru\.donmai\.us|safebooru\.org/.test(url);
}

/**
 * Extract tags by category from Danbooru page.
 */
function extractDanbooruTags(): { tags: string[]; safety: 'safe' | 'sketchy' | 'unsafe' } {
  const tags: string[] = [];
  let safety: 'safe' | 'sketchy' | 'unsafe' = 'safe';
  
  // Extract tags by category
  const extractCategory = (selector: string, category: string) => {
    document.querySelectorAll(selector).forEach(el => {
      // Find the tag name link
      const tagLink = el.querySelector('a.search-tag, a[href*="/posts?tags="]');
      if (tagLink) {
        const name = tagLink.textContent?.trim().replace(/ /g, '_');
        if (name && name.length >= 2) {
          tags.push(`${category}:${sanitizeTag(name)}`);
        }
      }
    });
  };
  
  // Danbooru tag categories
  extractCategory('.tag-type-artist', 'artist');
  extractCategory('.tag-type-copyright', 'copyright');
  extractCategory('.tag-type-character', 'character');
  extractCategory('.tag-type-meta', 'meta');
  
  // General tags (no prefix)
  document.querySelectorAll('.tag-type-general').forEach(el => {
    const tagLink = el.querySelector('a.search-tag, a[href*="/posts?tags="]');
    if (tagLink) {
      const name = tagLink.textContent?.trim().replace(/ /g, '_');
      if (name && name.length >= 2) {
        tags.push(sanitizeTag(name));
      }
    }
  });
  
  // Extract rating
  const ratingElement = document.querySelector('.tag-type-rating a, [data-tag-category="rating"] a');
  if (ratingElement) {
    const ratingText = ratingElement.textContent?.toLowerCase() || '';
    if (ratingText.includes('explicit') || ratingText.includes('questionable')) {
      safety = ratingText.includes('explicit') ? 'unsafe' : 'sketchy';
    }
  }
  
  // Also check for rating in post data
  const postSection = document.querySelector('#post-information, .post-info');
  if (postSection) {
    const ratingText = postSection.textContent?.toLowerCase() || '';
    if (ratingText.includes('rating: e') || ratingText.includes('rating:explicit')) {
      safety = 'unsafe';
    } else if (ratingText.includes('rating: q') || ratingText.includes('rating:questionable')) {
      safety = 'sketchy';
    }
  }
  
  return { tags, safety };
}

/**
 * Get the original/full size image URL.
 */
function getOriginalUrl(): string | null {
  // Try to find the original image link
  const originalLink = document.querySelector(`
    a[href*="//img"],
    a[href*="/original/"],
    a[href*="cdn.donmai.us"],
    #image-download-link,
    a[download]
  `);
  
  if (originalLink) {
    const href = originalLink.getAttribute('href');
    if (href) return href;
  }
  
  // Try to get from the image element itself
  const mainImage = document.querySelector('#image, .post-image img, [data-original-url]');
  if (mainImage) {
    const src = mainImage.getAttribute('src') || 
                mainImage.getAttribute('data-original-url') ||
                mainImage.getAttribute('data-file-url');
    if (src) return src;
  }
  
  // Try to extract from page data
  const postInfoScript = document.querySelector('script[data-post-id]');
  if (postInfoScript) {
    const text = postInfoScript.textContent || '';
    const match = text.match(/"file_url"\s*:\s*"([^"]+)"/);
    if (match) return match[1].replace(/\\\//g, '/');
  }
  
  return null;
}

/**
 * Get post ID from URL or page.
 */
function getPostId(): string | null {
  // From URL
  const urlMatch = window.location.pathname.match(/\/posts\/(\d+)/);
  if (urlMatch) return urlMatch[1];
  
  // From page data
  const postIdAttr = document.querySelector('[data-post-id]')?.getAttribute('data-post-id');
  if (postIdAttr) return postIdAttr;
  
  return null;
}

/**
 * Get the post view URL from a thumbnail element (list page).
 */
function getPostUrlFromThumbnail(mediaElement: HTMLElement): string | null {
  const link = mediaElement.closest('a[href*="/posts/"]');
  if (!link) return null;
  const href = (link as HTMLAnchorElement).href;
  if (!href) return null;
  const pathMatch = href.match(/\/posts\/(\d+)/);
  if (!pathMatch) return null;
  return href;
}

function isListPage(): boolean {
  const pathname = window.location.pathname || '';
  if (pathname === '/posts' || pathname.startsWith('/posts?')) return true;
  if (pathname === '/post' || pathname.startsWith('/post?')) return true;
  return false;
}

function isThumbnailElement(element: HTMLElement): boolean {
  return element.closest('.post-preview, .post-thumbnail') !== null;
}

/**
 * Danbooru site extractor implementation.
 */
export const danbooruExtractor: SiteExtractor = {
  name: 'danbooru',
  
  matches(url: string): boolean {
    return isDanbooruUrl(url);
  },
  
  async extract(mediaElement: HTMLElement, mediaUrl: string): Promise<MediaInfo | null> {
    const pageUrl = window.location.href;

    // List page: only the hovered thumbnail's post URL; never use document-level data
    if (isListPage()) {
      if (isThumbnailElement(mediaElement)) {
        const postUrl = getPostUrlFromThumbnail(mediaElement);
        if (postUrl) {
          return {
            url: postUrl,
            source: postUrl,
            tags: ['tagme'],
            safety: 'safe',
            type: 'image',
            filename: extractFilename(postUrl),
            skipTagging: false,
            metadata: {},
          };
        }
      }
      return null;
    }

    // Post view page: DOM extraction (single post)
    const originalUrl = getOriginalUrl();
    const downloadUrl = originalUrl || mediaUrl;
    
    // Extract tags and safety
    const { tags, safety } = extractDanbooruTags();
    
    // Get post ID
    const postId = getPostId();
    
    // Determine media type
    const isVideo = isVideoMedia(mediaElement, downloadUrl);
    
    return {
      url: downloadUrl,
      source: pageUrl,
      tags: tags.length > 0 ? tags : ['tagme'],
      safety,
      type: isVideo ? 'video' : 'image',
      filename: extractFilename(downloadUrl),
      skipTagging: true, // Danbooru posts already have good tags
      metadata: {
        postId,
        originalUrl,
      },
    };
  },
  
  findGrabbableMedia(): HTMLElement[] {
    const media: HTMLElement[] = [];
    
    // Main image on post page
    const mainImage = document.querySelector('#image, .post-image img');
    if (mainImage) {
      media.push(mainImage as HTMLElement);
    }
    
    // Thumbnails on search/index pages
    const thumbnails = document.querySelectorAll('.post-preview img, .post-thumbnail img');
    thumbnails.forEach(img => {
      if (this.isGrabbable(img as HTMLElement)) {
        media.push(img as HTMLElement);
      }
    });
    
    return media;
  },
  
  isGrabbable(element: HTMLElement): boolean {
    if (element.tagName !== 'IMG' && element.tagName !== 'VIDEO') {
      return false;
    }
    
    // Check if it's a main post image
    if (element.id === 'image' || element.closest('.post-image')) {
      return true;
    }
    
    // Check if it's a thumbnail
    if (element.closest('.post-preview, .post-thumbnail')) {
      const img = element as HTMLImageElement;
      return img.complete && img.naturalWidth >= 50;
    }
    
    return false;
  },
};

export default danbooruExtractor;
