/**
 * yande.re extractor for DOM-level media extraction.
 * 
 * Extracts tags and original image URLs from yande.re.
 */

import type { SiteExtractor, MediaInfo } from '../../../utils/types';
import { extractFilename, sanitizeTag, isVideoMedia } from '../../../utils/extractors/common';

/**
 * Check if a URL belongs to yande.re.
 */
export function isYandeUrl(url: string): boolean {
  return /yande\.re/.test(url);
}

/**
 * Extract tags by category from yande.re page.
 */
function extractYandeTags(): { tags: string[]; safety: 'safe' | 'sketchy' | 'unsafe' } {
  const tags: string[] = [];
  let safety: 'safe' | 'sketchy' | 'unsafe' = 'safe';
  
  // yande.re uses similar structure to Danbooru
  const extractCategory = (selector: string, category: string) => {
    document.querySelectorAll(selector).forEach(el => {
      const tagLink = el.querySelector('a[href*="/post?tags="], a[href*="/post/show/"]');
      if (tagLink) {
        const name = tagLink.textContent?.trim().replace(/ /g, '_');
        if (name && name.length >= 2) {
          tags.push(`${category}:${sanitizeTag(name)}`);
        }
      }
    });
  };
  
  // yande.re tag categories
  extractCategory('.tag-type-artist', 'artist');
  extractCategory('.tag-type-copyright', 'copyright');
  extractCategory('.tag-type-character', 'character');
  extractCategory('.tag-type-circle', 'circle'); // yande.re specific
  extractCategory('.tag-type-faults', 'faults'); // yande.re specific
  
  // General tags (no prefix)
  document.querySelectorAll('.tag-type-general, .tag-type-').forEach(el => {
    const tagLink = el.querySelector('a[href*="/post?tags="]');
    if (tagLink) {
      const name = tagLink.textContent?.trim().replace(/ /g, '_');
      if (name && name.length >= 2) {
        tags.push(sanitizeTag(name));
      }
    }
  });
  
  // Extract rating
  const ratingElement = document.querySelector('.tag-type-rating a, #stats li');
  if (ratingElement) {
    const ratingText = ratingElement.textContent?.toLowerCase() || '';
    if (ratingText.includes('explicit') || ratingText.includes('rating:e')) {
      safety = 'unsafe';
    } else if (ratingText.includes('questionable') || ratingText.includes('rating:q')) {
      safety = 'sketchy';
    }
  }
  
  // Also check stats section
  const statsSection = document.querySelector('#stats, .post-info, .sidebar');
  if (statsSection) {
    const statsText = statsSection.textContent?.toLowerCase() || '';
    if (statsText.includes('rating: e') || statsText.includes('rating:explicit')) {
      safety = 'unsafe';
    } else if (statsText.includes('rating: q') || statsText.includes('rating:questionable')) {
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
    a[href*="//yande.re/image"],
    a[href*="/jpeg/"],
    a[href*="/png/"],
    #highres,
    a[download]
  `);
  
  if (originalLink) {
    const href = originalLink.getAttribute('href');
    if (href) return href;
  }
  
  // Try to get from the main image element
  const mainImage = document.querySelector('#image, .post-image img, #main-image');
  if (mainImage) {
    const src = mainImage.getAttribute('src');
    if (src && !src.includes('sample.')) return src;
    
    // Check for data attributes
    const dataSrc = mainImage.getAttribute('data-original-url') ||
                    mainImage.getAttribute('data-file-url');
    if (dataSrc) return dataSrc;
  }
  
  // Try to find the "Original" text link
  const originalTextLink = Array.from(document.querySelectorAll('a')).find(
    a => a.textContent?.toLowerCase().includes('original') || 
         a.textContent?.toLowerCase().includes('highres')
  );
  if (originalTextLink) {
    const href = originalTextLink.getAttribute('href');
    if (href) return href;
  }
  
  return null;
}

/**
 * Get post ID from URL or page.
 */
function getPostId(): string | null {
  // From URL - yande.re uses /post/show/12345 format
  const urlMatch = window.location.pathname.match(/\/post\/show\/(\d+)/);
  if (urlMatch) return urlMatch[1];
  
  // From page data
  const postIdAttr = document.querySelector('[data-id]')?.getAttribute('data-id');
  if (postIdAttr) return postIdAttr;
  
  return null;
}

/**
 * yande.re site extractor implementation.
 */
export const yandeExtractor: SiteExtractor = {
  name: 'yande',
  
  matches(url: string): boolean {
    return isYandeUrl(url);
  },
  
  async extract(mediaElement: HTMLElement, mediaUrl: string): Promise<MediaInfo | null> {
    const pageUrl = window.location.href;
    
    // Get original URL
    const originalUrl = getOriginalUrl();
    const downloadUrl = originalUrl || mediaUrl;
    
    // Extract tags and safety
    const { tags, safety } = extractYandeTags();
    
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
      skipTagging: true, // yande.re posts already have good tags
      metadata: {
        postId,
        originalUrl,
      },
    };
  },
  
  findGrabbableMedia(): HTMLElement[] {
    const media: HTMLElement[] = [];
    
    // Main image on post page
    const mainImage = document.querySelector('#image, .post-image img, #main-image');
    if (mainImage) {
      media.push(mainImage as HTMLElement);
    }
    
    // Thumbnails on search/index pages
    const thumbnails = document.querySelectorAll('.thumb img, .preview img, .post-preview img');
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
    if (element.closest('.thumb, .preview, .post-preview')) {
      const img = element as HTMLImageElement;
      return img.complete && img.naturalWidth >= 50;
    }
    
    return false;
  },
};

export default yandeExtractor;
