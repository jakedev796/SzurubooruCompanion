/**
 * Reddit extractor for DOM-level media extraction.
 *
 * Submits the post permalink (parent URL) so the backend fetches media via gallery-dl.
 * Only post URLs (/r/.../comments/...) are allowed; subreddit-only URLs are rejected.
 */

import type { SiteExtractor, MediaInfo } from '../../../utils/types';
import { extractFilename, isVideoMedia } from '../../../utils/extractors/common';

export function isRedditUrl(url: string): boolean {
  return /reddit\.com/.test(url);
}

/**
 * Get the post permalink from the container that holds the media.
 * Returns full URL (e.g. https://www.reddit.com/r/Subreddit/comments/Id/...).
 */
function getPostUrlFromMedia(element: HTMLElement): string | null {
  const container = element.closest(
    'article, shreddit-post, [data-testid="post-container"], [data-post-id], [id^="t3_"]'
  );
  if (!container) return null;

  const link = container.querySelector('a[href*="/comments/"]') as HTMLAnchorElement | null;
  if (!link?.href) return null;

  const href = link.href;
  if (!/\/r\/[^/]+\/comments\/[^/]+/.test(href)) return null;

  try {
    const u = new URL(href);
    if (!u.pathname.includes('/comments/')) return null;
    return href;
  } catch {
    return null;
  }
}

/**
 * Reddit site extractor: submit only the post URL (parent of the media).
 */
export const redditExtractor: SiteExtractor = {
  name: 'reddit',

  matches(url: string): boolean {
    return isRedditUrl(url);
  },

  async extract(mediaElement: HTMLElement, mediaUrl: string): Promise<MediaInfo | null> {
    const postUrl = getPostUrlFromMedia(mediaElement);
    if (!postUrl) {
      console.log('[CCC] Reddit: Could not find post permalink for media');
      return null;
    }

    const isVideo = isVideoMedia(mediaElement, mediaUrl);

    return {
      url: postUrl,
      source: postUrl,
      tags: ['tagme'],
      safety: 'safe',
      type: isVideo ? 'video' : 'image',
      filename: extractFilename(postUrl),
      skipTagging: false,
      metadata: {},
    };
  },

  findGrabbableMedia(): HTMLElement[] {
    const media: HTMLElement[] = [];
    const containers = document.querySelectorAll(
      'article, shreddit-post, [data-testid="post-container"]'
    );

    containers.forEach((container) => {
      const postLink = container.querySelector('a[href*="/comments/"]');
      if (!postLink) return;

      const imgs = container.querySelectorAll('img');
      imgs.forEach((img) => {
        if (this.isGrabbable(img as HTMLElement)) media.push(img as HTMLElement);
      });
      const videos = container.querySelectorAll('video');
      videos.forEach((video) => {
        if (this.isGrabbable(video as HTMLElement)) media.push(video as HTMLElement);
      });
    });

    return media;
  },

  isGrabbable(element: HTMLElement): boolean {
    if (element.tagName !== 'IMG' && element.tagName !== 'VIDEO') return false;

    if (!getPostUrlFromMedia(element)) return false;

    if (element.tagName === 'IMG') {
      const img = element as HTMLImageElement;
      if (img.src?.includes('/avatar') || img.src?.includes('/emoji')) return false;
      if (!img.complete || img.naturalWidth < 50 || img.naturalHeight < 50) return false;
    }

    if (element.tagName === 'VIDEO') {
      const video = element as HTMLVideoElement;
      const inContainer = !!video.closest('article, shreddit-post, [data-testid="post-container"]');
      if (inContainer) return video.readyState >= 0;
      return !!(video.src || video.currentSrc) && video.readyState >= 1;
    }

    return true;
  },
};

export default redditExtractor;
