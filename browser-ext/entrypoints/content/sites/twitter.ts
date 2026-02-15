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
 * Extract tweet ID from Twitter DOM.
 */
function extractTweetId(element: HTMLElement): string | null {
  // Look for status links
  const tweetContainer = element.closest('article, [data-testid="tweet"], [role="article"]');
  
  if (tweetContainer) {
    // Find status links
    const statusLinks = tweetContainer.querySelectorAll('a[href*="/status/"]');
    for (const link of statusLinks) {
      const href = link.getAttribute('href');
      if (href) {
        const match = href.match(/\/status\/(\d+)/);
        if (match) {
          // Skip if this is just a mention link
          const parentText = link.textContent || '';
          if (!parentText.match(/^@\w+$/)) {
            return match[1];
          }
        }
      }
    }
    
    // Try data-tweet-id attribute
    const tweetId = tweetContainer.getAttribute('data-tweet-id');
    if (tweetId) return tweetId;
    
    // Try finding the time element's parent link
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
  }
  
  // Check if page URL itself is a tweet
  const pageUrl = window.location.href;
  const pageMatch = pageUrl.match(/\/status\/(\d+)/);
  if (pageMatch) {
    return pageMatch[1];
  }
  
  return null;
}

/**
 * Extract the ORIGINAL author's username from Twitter DOM.
 * This handles retweets by finding the original tweet's author,
 * not the person who retweeted it.
 */
function extractUsername(element: HTMLElement): string | null {
  const tweetContainer = element.closest('article, [data-testid="tweet"], [role="article"]');
  if (!tweetContainer) return null;
  
  // Check if this is a retweet - look for "Reposted" or similar indicators
  // Twitter shows "User reposted" above the original tweet
  const retweetHeader = tweetContainer.querySelector('[data-testid="socialContext"]');
  if (retweetHeader) {
    // This is a retweet, find the original author inside
    // The original tweet content is below the retweet header
    const originalContent = tweetContainer.querySelector('[data-testid="tweet"]') || tweetContainer;
    
    // Find the user link in the original content
    const userLinks = originalContent.querySelectorAll('a[href^="/"]');
    for (const link of userLinks) {
      const href = link.getAttribute('href') || '';
      const match = href.match(/^\/([a-zA-Z0-9_]+)(?:\/|$)/);
      if (match && !['status', 'i', 'home', 'explore', 'notifications', 'messages'].includes(match[1])) {
        // Verify this is the author link (usually has the avatar or display name)
        const parent = link.closest('[data-testid="User-Name"], [class*="user"]');
        if (parent) {
          return match[1];
        }
      }
    }
  }
  
  // Not a retweet, or fallback: find the first user link
  // Twitter's structure: the author's profile link appears before the tweet content
  const userLinks = tweetContainer.querySelectorAll('a[href^="/"]');
  
  // The author is typically the first user link that's not a status link
  for (const link of userLinks) {
    const href = link.getAttribute('href') || '';
    // Match /username pattern (not /status/, /i/, etc.)
    const match = href.match(/^\/([a-zA-Z0-9_]+)(?:\/|$)/);
    if (match && !['status', 'i', 'home', 'explore', 'notifications', 'messages'].includes(match[1])) {
      // Verify this is in the user name section (not a mention in the text)
      const parent = link.closest('[data-testid="User-Name"]');
      if (parent) {
        return match[1];
      }
    }
  }
  
  // Fallback: look for the first user link that's not in the tweet text
  for (const link of userLinks) {
    const href = link.getAttribute('href') || '';
    const match = href.match(/^\/([a-zA-Z0-9_]+)(?:\/|$)/);
    if (match && !['status', 'i', 'home', 'explore', 'notifications', 'messages'].includes(match[1])) {
      // Check if this link is NOT in the tweet text area
      const tweetText = link.closest('[data-testid="tweetText"]');
      if (!tweetText) {
        return match[1];
      }
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
 * Extract hashtags from tweet.
 */
function extractTwitterTags(element: HTMLElement): string[] {
  const tweetContainer = element.closest('article, [data-testid="tweet"], [role="article"]');
  if (!tweetContainer) return ['tagme'];
  
  // Look for hashtag links
  const hashtagLinks = tweetContainer.querySelectorAll('a[href*="/hashtag/"]');
  const tags: string[] = [];
  
  for (const link of hashtagLinks) {
    const href = link.getAttribute('href') || '';
    const match = href.match(/\/hashtag\/([a-zA-Z0-9_]+)/);
    if (match) {
      tags.push(match[1].toLowerCase());
    }
  }
  
  // Also extract from tweet text
  const tweetText = tweetContainer.querySelector('[data-testid="tweetText"]')?.textContent || '';
  const textTags = extractHashtags(tweetText);
  
  // Combine and dedupe
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
    const pageUrl = window.location.href;
    
    // Extract tweet ID
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
