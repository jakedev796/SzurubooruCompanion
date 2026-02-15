/**
 * Misskey extractor for DOM-level media extraction.
 * 
 * Extracts note URLs from Misskey instances so gallery-dl can properly
 * process them instead of failing on user profile URLs.
 */

import type { SiteExtractor, MediaInfo } from '../../../utils/types';
import { extractFilename, extractHashtags, isVideoMedia } from '../../../utils/extractors/common';

/** Known Misskey instance domains */
export const MISSKEY_DOMAINS = [
  'misskey.io',
  'misskey.art',
  'misskey.net',
  'misskey.design',
  'misskey.xyz',
  'mi.0px.io',
  'misskey.pizza',
  'misskey.cloud',
  'misskey.st',
  'misskey.id',
];

/**
 * Check if a URL belongs to a Misskey instance.
 */
export function isMisskeyUrl(url: string): boolean {
  try {
    const hostname = new URL(url).hostname;
    return MISSKEY_DOMAINS.some(d => hostname === d || hostname.endsWith('.' + d));
  } catch {
    return false;
  }
}

/**
 * Extract note ID from various Misskey DOM structures.
 */
function extractNoteId(element: HTMLElement): string | null {
  // Try data-note-id attribute
  const noteElement = element.closest('[data-note-id]');
  if (noteElement) {
    const noteId = noteElement.getAttribute('data-note-id');
    if (noteId) return noteId;
  }
  
  // Try data-id attribute on article elements
  const articleElement = element.closest('article[data-id]');
  if (articleElement) {
    const noteId = articleElement.getAttribute('data-id');
    if (noteId) return noteId;
  }
  
  // Look for note links within the element
  const noteLink = element.closest('a[href*="/notes/"]') || 
                   element.querySelector('a[href*="/notes/"]');
  if (noteLink) {
    const href = noteLink.getAttribute('href');
    if (href) {
      const match = href.match(/\/notes\/([a-zA-Z0-9]+)/);
      if (match) return match[1];
    }
  }
  
  // Look for note links in parent elements
  const parent = element.closest('article, [class*="note"], [class*="post"]');
  if (parent) {
    const links = parent.querySelectorAll('a[href*="/notes/"]');
    for (const link of links) {
      const href = link.getAttribute('href');
      if (href) {
        const match = href.match(/\/notes\/([a-zA-Z0-9]+)/);
        if (match) return match[1];
      }
    }
  }
  
  return null;
}

/**
 * Extract the ORIGINAL author's username and host from Misskey DOM.
 * This handles renotes (boosts) by finding the original note's author,
 * not the person who renoted it.
 */
function extractUserInfo(element: HTMLElement): { username: string; host: string } | null {
  const noteElement = element.closest('article, [class*="note"], [class*="post"]');
  if (!noteElement) return null;
  
  // Check if this is a renote - look for renote container
  // Misskey wraps renote content in a nested structure
  const renoteContainer = noteElement.querySelector('[class*="renote"], [class*="quote"]');
  
  // If this is a renote, we need to find the original author inside the renote container
  const searchContainer = renoteContainer || noteElement;
  
  // Strategy 1: Look for the author avatar/name section (usually the first user link in the note)
  // Misskey typically has the author info at the top of the note
  const authorSection = searchContainer.querySelector(`
    [class*="avatar"] + [class*="name"],
    [class*="header"] [class*="name"],
    [class*="user"] [class*="name"],
    header a[href*="/@"]
  `);
  
  if (authorSection) {
    // Try to get username from the text
    const text = authorSection.textContent?.trim() || '';
    const federatedMatch = text.match(/@([a-zA-Z0-9_-]+)@([a-zA-Z0-9.-]+)/);
    if (federatedMatch) {
      return { username: federatedMatch[1], host: federatedMatch[2] };
    }
    const localMatch = text.match(/@([a-zA-Z0-9_-]+)/);
    if (localMatch) {
      return { username: localMatch[1], host: '' };
    }
  }
  
  // Strategy 2: Look for the first user link in the note header area
  const headerArea = searchContainer.querySelector('[class*="header"], header, [class*="top"]');
  if (headerArea) {
    const userLink = headerArea.querySelector('a[href*="/@"]');
    if (userLink) {
      const href = userLink.getAttribute('href') || '';
      const match = href.match(/\/@([a-zA-Z0-9_-]+)(?:@([a-zA-Z0-9.-]+))?/);
      if (match) {
        return { username: match[1], host: match[2] || '' };
      }
    }
  }
  
  // Strategy 3: Look for avatar link (usually links to user profile)
  const avatarLink = searchContainer.querySelector('a[href*="/@"]:has(img[class*="avatar"]), a[href*="/@"] img[class*="avatar"]');
  if (avatarLink) {
    const link = avatarLink.closest('a[href*="/@"]');
    if (link) {
      const href = link.getAttribute('href') || '';
      const match = href.match(/\/@([a-zA-Z0-9_-]+)(?:@([a-zA-Z0-9.-]+))?/);
      if (match) {
        return { username: match[1], host: match[2] || '' };
      }
    }
  }
  
  // Strategy 4: Find the first user link in the note (original author is usually first)
  const userLinks = searchContainer.querySelectorAll('a[href*="/@"]');
  for (const link of userLinks) {
    const href = link.getAttribute('href') || '';
    // Skip if this looks like a mention in the text (not the author)
    const parent = link.closest('[class*="text"], [class*="content"]');
    if (parent) continue;
    
    const match = href.match(/\/@([a-zA-Z0-9_-]+)(?:@([a-zA-Z0-9.-]+))?/);
    if (match) {
      return { username: match[1], host: match[2] || '' };
    }
  }
  
  // Strategy 5: Look for display name + username pattern
  const nameElements = searchContainer.querySelectorAll('[class*="userName"], [class*="username"], [class*="display-name"]');
  for (const nameEl of nameElements) {
    const text = nameEl.textContent?.trim() || '';
    const federatedMatch = text.match(/@([a-zA-Z0-9_-]+)@([a-zA-Z0-9.-]+)/);
    if (federatedMatch) {
      return { username: federatedMatch[1], host: federatedMatch[2] };
    }
    const localMatch = text.match(/@([a-zA-Z0-9_-]+)/);
    if (localMatch) {
      return { username: localMatch[1], host: '' };
    }
  }
  
  return null;
}

/**
 * Extract hashtags from Misskey note.
 */
function extractMisskeyTags(element: HTMLElement): string[] {
  const noteElement = element.closest('article, [class*="note"], [class*="post"]');
  if (!noteElement) return ['tagme'];
  
  // Look for hashtag links
  const hashtagLinks = noteElement.querySelectorAll('a[href*="/tags/"], a[href*="/tag/"]');
  const tags: string[] = [];
  
  for (const link of hashtagLinks) {
    const href = link.getAttribute('href') || '';
    const match = href.match(/\/tags?\/([a-zA-Z0-9_]+)/);
    if (match) {
      tags.push(match[1].toLowerCase());
    }
  }
  
  // Also extract from text content
  const textContent = noteElement.textContent || '';
  const textTags = extractHashtags(textContent);
  
  // Combine and dedupe
  const allTags = [...new Set([...tags, ...textTags])];
  
  return allTags.length > 0 ? allTags : ['tagme'];
}

/**
 * Misskey site extractor implementation.
 */
export const misskeyExtractor: SiteExtractor = {
  name: 'misskey',
  
  matches(url: string): boolean {
    return isMisskeyUrl(url);
  },
  
  async extract(mediaElement: HTMLElement, mediaUrl: string): Promise<MediaInfo | null> {
    const pageUrl = window.location.href;
    const currentHost = new URL(pageUrl).hostname;
    
    // Extract note ID
    const noteId = extractNoteId(mediaElement);
    if (!noteId) {
      console.log('[CCC] Misskey: Could not find note ID');
      return null;
    }
    
    // Build note URL (this is what gallery-dl needs!)
    const noteUrl = `https://${currentHost}/notes/${noteId}`;
    
    // Extract user info (original author, not renote author)
    const userInfo = extractUserInfo(mediaElement);
    
    // Build user URL
    let userUrl: string | null = null;
    if (userInfo) {
      userUrl = userInfo.host
        ? `https://${currentHost}/@${userInfo.username}@${userInfo.host}`
        : `https://${currentHost}/@${userInfo.username}`;
    }
    
    // Extract tags
    const tags = extractMisskeyTags(mediaElement);
    
    // Add artist tag from username
    if (userInfo?.username) {
      // Add artist tag at the beginning
      tags.unshift(`artist:${userInfo.username.toLowerCase()}`);
    }
    
    // Build sources array - prioritize note URL
    const secondarySources: string[] = [];
    if (userUrl && userUrl !== noteUrl) {
      secondarySources.push(userUrl);
    }
    
    // Determine media type
    const isVideo = isVideoMedia(mediaElement, mediaUrl);
    
    return {
      url: mediaUrl,
      source: noteUrl,
      secondarySources: secondarySources.length > 0 ? secondarySources : undefined,
      tags,
      safety: 'safe',
      type: isVideo ? 'video' : 'image',
      filename: extractFilename(mediaUrl),
      metadata: {
        noteId,
        instance: currentHost,
        username: userInfo?.username,
        userHost: userInfo?.host,
      },
    };
  },
  
  findGrabbableMedia(): HTMLElement[] {
    const media: HTMLElement[] = [];
    
    // Find all images in note containers
    const noteImages = document.querySelectorAll(`
      article img,
      [data-note-id] img,
      [class*="note"] img,
      [class*="post"] img
    `);
    
    noteImages.forEach(img => {
      if (this.isGrabbable(img as HTMLElement)) {
        media.push(img as HTMLElement);
      }
    });
    
    // Find all videos in note containers
    const noteVideos = document.querySelectorAll(`
      article video,
      [data-note-id] video,
      [class*="note"] video,
      [class*="post"] video
    `);
    
    noteVideos.forEach(video => {
      media.push(video as HTMLElement);
    });
    
    return media;
  },
  
  isGrabbable(element: HTMLElement): boolean {
    if (element.tagName !== 'IMG' && element.tagName !== 'VIDEO') {
      return false;
    }
    
    // Check if element is in a note container
    const noteContainer = element.closest(`
      article,
      [data-note-id],
      [class*="note"],
      [class*="post"]
    `);
    
    if (!noteContainer) {
      return false;
    }
    
    // For images, check if loaded and has reasonable size
    if (element.tagName === 'IMG') {
      const img = element as HTMLImageElement;
      if (!img.complete || img.naturalWidth < 50 || img.naturalHeight < 50) {
        return false;
      }
      
      // Skip profile pictures and icons
      const src = img.src;
      if (src.includes('/avatar') || src.includes('/icon')) {
        return false;
      }
    }
    
    return true;
  },
};

export default misskeyExtractor;
