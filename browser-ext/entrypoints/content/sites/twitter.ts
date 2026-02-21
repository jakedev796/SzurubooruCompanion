/**
 * Twitter/X extractor for DOM-level media extraction.
 * 
 * Extracts tweet URLs and upgrades image URLs to original quality.
 */

import type { SiteExtractor, MediaInfo } from '../../../utils/types';
import { extractFilename, extractHashtags, isVideoMedia } from '../../../utils/extractors/common';

/**
 * Check if a URL belongs to Twitter/X.
 */
export function isTwitterUrl(url: string): boolean {
  return /twitter\.com|x\.com/.test(url);
}

/**
 * Find the innermost tweet container that contains the given element.
 * For retweets, this returns the original tweet's block (the one that has the media),
 * not the outer retweet wrapper.
 */
function getTweetContainerForMedia(element: HTMLElement): HTMLElement | null {
  const candidates = document.querySelectorAll('article, [data-testid="tweet"], [role="article"]');
  let innermost: HTMLElement | null = null;
  for (const node of candidates) {
    const el = node as HTMLElement;
    if (!el.contains(element)) continue;
    // Prefer the smallest container that contains the media and has no nested tweet container with the media
    const nested = el.querySelector('article, [data-testid="tweet"], [role="article"]');
    if (nested && nested !== el && (nested as HTMLElement).contains(element)) continue;
    innermost = el;
    break;
  }
  return innermost;
}

/**
 * Extract tweet ID from the tweet container that contains the media.
 * For retweets, uses the original tweet's status ID.
 */
function extractTweetId(element: HTMLElement): string | null {
  const tweetContainer = getTweetContainerForMedia(element);
  if (tweetContainer) {
    // Prefer the time link (canonical status link for this tweet)
    const timeElement = tweetContainer.querySelector('time');
    if (timeElement) {
      const parentLink = timeElement.closest('a[href*="/status/"]');
      if (parentLink) {
        const href = parentLink.getAttribute('href');
        if (href) {
          const match = href.match(/\/status\/(\d+)/);
          if (match) return match[1];
        }
      }
    }
    const statusLinks = tweetContainer.querySelectorAll('a[href*="/status/"]');
    for (const link of statusLinks) {
      const href = link.getAttribute('href');
      if (href) {
        const match = href.match(/\/status\/(\d+)/);
        if (match) {
          const parentText = link.textContent || '';
          if (!parentText.match(/^@\w+$/)) return match[1];
        }
      }
    }
    const tweetId = tweetContainer.getAttribute('data-tweet-id');
    if (tweetId) return tweetId;
  }
  const pageUrl = window.location.href;
  const pageMatch = pageUrl.match(/\/status\/(\d+)/);
  if (pageMatch) return pageMatch[1];
  return null;
}

/**
 * Extract the tweet author's username from the container that contains the media.
 * getTweetContainerForMedia already gives us the original tweet for retweets.
 */
function extractUsername(element: HTMLElement): string | null {
  const tweetContainer = getTweetContainerForMedia(element);
  if (!tweetContainer) return null;

  const userLinks = tweetContainer.querySelectorAll('a[href^="/"]');
  for (const link of userLinks) {
    const href = link.getAttribute('href') || '';
    const match = href.match(/^\/([a-zA-Z0-9_]+)(?:\/|$)/);
    if (match && !['status', 'i', 'home', 'explore', 'notifications', 'messages'].includes(match[1])) {
      const parent = link.closest('[data-testid="User-Name"]');
      if (parent) return match[1];
    }
  }
  for (const link of userLinks) {
    const href = link.getAttribute('href') || '';
    const match = href.match(/^\/([a-zA-Z0-9_]+)(?:\/|$)/);
    if (match && !['status', 'i', 'home', 'explore', 'notifications', 'messages'].includes(match[1])) {
      if (!link.closest('[data-testid="tweetText"]')) return match[1];
    }
  }
  return null;
}

/**
 * Upgrade Twitter image URL to original quality.
 */
function upgradeImageUrl(url: string): string {
  if (!url.includes('twimg.com')) {
    return url;
  }
  
  try {
    const urlObj = new URL(url);
    const nameParam = urlObj.searchParams.get('name');
    
    // If already orig or no name param, try to set orig
    if (!nameParam || ['small', 'medium', 'large', 'thumb'].includes(nameParam)) {
      urlObj.searchParams.set('name', 'orig');
      return urlObj.toString();
    }
  } catch {
    // Invalid URL, return as-is
  }
  
  return url;
}

/**
 * Extract hashtags from the tweet that contains the media.
 */
function extractTwitterTags(element: HTMLElement): string[] {
  const tweetContainer = getTweetContainerForMedia(element);
  if (!tweetContainer) return ['tagme'];

  const hashtagLinks = tweetContainer.querySelectorAll('a[href*="/hashtag/"]');
  const tags: string[] = [];
  for (const link of hashtagLinks) {
    const href = link.getAttribute('href') || '';
    const match = href.match(/\/hashtag\/([a-zA-Z0-9_]+)/);
    if (match) tags.push(match[1].toLowerCase());
  }
  const tweetText = tweetContainer.querySelector('[data-testid="tweetText"]')?.textContent || '';
  const textTags = extractHashtags(tweetText);
  const allTags = [...new Set([...tags, ...textTags])];
  return allTags.length > 0 ? allTags : ['tagme'];
}

/**
 * Check if media is a video (Twitter videos need yt-dlp).
 */
function isTwitterVideo(element: HTMLElement, url: string): boolean {
  // Check element type
  if (element.tagName === 'VIDEO') {
    return true;
  }
  
  // Check for blob URLs (Twitter uses these for videos)
  if (url.startsWith('blob:')) {
    return true;
  }
  
  // Check URL patterns
  if (url.includes('video.twimg.com') || url.includes('.mp4') || url.includes('.webm')) {
    return true;
  }
  
  // Check for video player container
  const videoContainer = element.closest('[data-testid="videoPlayer"], [data-testid="previewInterstitial"]');
  if (videoContainer) {
    return true;
  }
  
  return false;
}

/**
 * Twitter/X site extractor implementation.
 */
export const twitterExtractor: SiteExtractor = {
  name: 'twitter',
  
  matches(url: string): boolean {
    return isTwitterUrl(url);
  },
  
  async extract(mediaElement: HTMLElement, mediaUrl: string): Promise<MediaInfo | null> {
    // Extract tweet ID (from innermost tweet container; for retweets, the original tweet)
    const tweetId = extractTweetId(mediaElement);
    if (!tweetId) {
      console.log('[CCC] Twitter: Could not find tweet ID');
      return null;
    }
    
    // Extract username (original author, not retweeter)
    const username = extractUsername(mediaElement);
    
    // Build tweet URL
    const tweetUrl = username
      ? `https://x.com/${username}/status/${tweetId}`
      : `https://x.com/i/status/${tweetId}`;
    
    // Check if video
    const isVideo = isTwitterVideo(mediaElement, mediaUrl);
    
    // For images, upgrade to original quality
    let bestUrl = mediaUrl;
    if (!isVideo && mediaUrl.includes('twimg.com')) {
      bestUrl = upgradeImageUrl(mediaUrl);
    }
    
    // Extract tags
    const tags = extractTwitterTags(mediaElement);
    
    // Add artist tag from username
    if (username) {
      // Add artist tag at the beginning
      tags.unshift(`artist:${username.toLowerCase()}`);
    }
    
    // For videos, we need to use the tweet URL for yt-dlp
    const downloadUrl = isVideo ? tweetUrl : bestUrl;
    
    return {
      url: downloadUrl,
      source: tweetUrl,
      tags,
      safety: 'safe',
      type: isVideo ? 'video' : 'image',
      filename: extractFilename(bestUrl),
      metadata: {
        tweetId,
        username,
        originalUrl: mediaUrl,
        upgradedUrl: bestUrl !== mediaUrl ? bestUrl : undefined,
      },
    };
  },
  
  findGrabbableMedia(): HTMLElement[] {
    const media: HTMLElement[] = [];
    
    // Find all images in tweets
    const tweetImages = document.querySelectorAll(`
      article img,
      [data-testid="tweet"] img,
      [data-testid="tweetPhoto"] img
    `);
    
    tweetImages.forEach(img => {
      if (this.isGrabbable(img as HTMLElement)) {
        media.push(img as HTMLElement);
      }
    });
    
    // Find all videos
    const tweetVideos = document.querySelectorAll(`
      article video,
      [data-testid="videoPlayer"] video,
      [data-testid="previewInterstitial"] video
    `);
    
    tweetVideos.forEach(video => {
      media.push(video as HTMLElement);
    });
    
    return media;
  },
  
  isGrabbable(element: HTMLElement): boolean {
    if (element.tagName !== 'IMG' && element.tagName !== 'VIDEO') {
      return false;
    }
    
    // Check if element is in a tweet container
    const tweetContainer = element.closest(`
      article,
      [data-testid="tweet"],
      [data-testid="tweetPhoto"],
      [data-testid="videoPlayer"],
      [role="article"]
    `);
    
    if (!tweetContainer) {
      return false;
    }
    
    // For images, filter out profile pictures and icons
    if (element.tagName === 'IMG') {
      const img = element as HTMLImageElement;
      const src = img.src;
      
      // Skip profile pictures
      if (src.includes('/profile_images/')) {
        // Only skip small variants
        if (src.includes('_normal.') || src.includes('_bigger.') || 
            src.includes('_mini.') || src.includes('_200x200.')) {
          return false;
        }
      }
      
      // Skip emoji
      if (src.includes('/emoji/') || src.includes('/hashflags/')) {
        return false;
      }
      
      // Skip verification badges and icons
      if (src.includes('/badge') || src.includes('/icon')) {
        return false;
      }
      
      // Check minimum size
      if (!img.complete || img.naturalWidth < 50 || img.naturalHeight < 50) {
        return false;
      }
    }
    
    return true;
  },
};

export default twitterExtractor;
