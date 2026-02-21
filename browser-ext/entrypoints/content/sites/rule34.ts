/**
 * Rule34.xxx extractor for DOM-level media extraction.
 *
 * Rule34.xxx is Gelbooru-based; tag and image structure are similar.
 */

import type { SiteExtractor, MediaInfo } from '../../../utils/types';
import { extractFilename, sanitizeTag, isVideoMedia } from '../../../utils/extractors/common';

/**
 * Check if a URL belongs to Rule34.xxx.
 */
export function isRule34Url(url: string): boolean {
  return /rule34\.xxx/.test(url);
}

/**
 * Extract tags by category from Rule34 page.
 */
function extractRule34Tags(): { tags: string[]; safety: 'safe' | 'sketchy' | 'unsafe' } {
  const tags: string[] = [];
  let safety: 'safe' | 'sketchy' | 'unsafe' = 'unsafe';

  const tagContainers = document.querySelectorAll('.tag-type');

  tagContainers.forEach((container) => {
    const classList = container.className;
    const tagLink = container.querySelector('a[href*="index.php?page=post&s=list&tags="]');

    if (!tagLink) return;

    const tagName = tagLink.textContent?.trim().replace(/ /g, '_');
    if (!tagName || tagName.length < 2) return;

    if (classList.includes('tag-type-artist')) {
      tags.push(`artist:${sanitizeTag(tagName)}`);
    } else if (classList.includes('tag-type-copyright')) {
      tags.push(`copyright:${sanitizeTag(tagName)}`);
    } else if (classList.includes('tag-type-character')) {
      tags.push(`character:${sanitizeTag(tagName)}`);
    } else if (classList.includes('tag-type-metadata')) {
      tags.push(`meta:${sanitizeTag(tagName)}`);
    } else {
      tags.push(sanitizeTag(tagName));
    }
  });

  const statsSection = document.querySelector('#stats, .post-info');
  if (statsSection) {
    const statsText = statsSection.textContent?.toLowerCase() || '';
    if (statsText.includes('rating: safe')) {
      safety = 'safe';
    } else if (statsText.includes('rating: questionable') || statsText.includes('rating:questionable')) {
      safety = 'sketchy';
    }
  }

  return { tags, safety };
}

/**
 * Get the original/full size image URL.
 */
function getOriginalUrl(): string | null {
  const originalLink = document.querySelector(
    `a[href*="//img"], a[href*="/images/"], #image-link, a[download], .original-file-notice a`
  );

  if (originalLink) {
    const href = originalLink.getAttribute('href');
    if (href && !href.includes('sample.')) return href;
  }

  const mainImage = document.querySelector('#image, .post-image img, #main-image');
  if (mainImage) {
    const src = mainImage.getAttribute('src');
    if (src && !src.includes('sample.')) return src;

    const dataSrc =
      mainImage.getAttribute('data-original-url') || mainImage.getAttribute('data-file-url');
    if (dataSrc) return dataSrc;
  }

  const originalTextLink = Array.from(document.querySelectorAll('a')).find((a) =>
    a.textContent?.toLowerCase().includes('original')
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
  const urlParams = new URLSearchParams(window.location.search);
  const postId = urlParams.get('id');
  if (postId) return postId;

  const postIdAttr = document.querySelector('[data-id]')?.getAttribute('data-id');
  if (postIdAttr) return postIdAttr;

  return null;
}

function getPostUrlFromThumbnail(mediaElement: HTMLElement): string | null {
  const link = mediaElement.closest('a[href*="page=post"]');
  if (!link) return null;
  const href = (link as HTMLAnchorElement).href;
  if (!href || (!href.includes('s=view') && !href.includes('id='))) return null;
  return href;
}

function isListPage(): boolean {
  return window.location.href.includes('page=post') && window.location.href.includes('s=list');
}

function isThumbnailElement(element: HTMLElement): boolean {
  return element.closest('.thumb, .thumbnail, .post-preview') !== null;
}

/**
 * Rule34.xxx site extractor implementation.
 */
export const rule34Extractor: SiteExtractor = {
  name: 'rule34',

  matches(url: string): boolean {
    return isRule34Url(url);
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

    const { tags, safety } = extractRule34Tags();
    const postId = getPostId();
    const isVideo = isVideoMedia(mediaElement, downloadUrl);

    return {
      url: downloadUrl,
      source: pageUrl,
      tags: tags.length > 0 ? tags : ['tagme'],
      safety,
      type: isVideo ? 'video' : 'image',
      filename: extractFilename(downloadUrl),
      skipTagging: true,
      metadata: {
        postId,
        originalUrl,
      },
    };
  },

  findGrabbableMedia(): HTMLElement[] {
    const media: HTMLElement[] = [];

    const mainImage = document.querySelector('#image, .post-image img, #main-image');
    if (mainImage) {
      media.push(mainImage as HTMLElement);
    }

    const thumbnails = document.querySelectorAll('.thumb img, .thumbnail img, .post-preview img');
    thumbnails.forEach((img) => {
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

    if (element.id === 'image' || element.closest('.post-image')) {
      return true;
    }

    if (element.closest('.thumb, .thumbnail, .post-preview')) {
      const img = element as HTMLImageElement;
      return img.complete && img.naturalWidth >= 50;
    }

    return false;
  },
};

export default rule34Extractor;
