/**
 * Floating button manager for DOM-level media extraction.
 * 
 * Creates a floating button that appears when hovering over media elements.
 * Clicking the button extracts media info and submits a job.
 */

import type { MediaInfo } from '../../utils/types';

const BUTTON_ID = 'szuru-companion-grab-btn';
const HOVER_DELAY_MS = 200;
const HIDE_DELAY_MS = 100;

interface ButtonState {
  currentMedia: HTMLElement | null;
  hoverTimeout: ReturnType<typeof setTimeout> | null;
  isButtonHovered: boolean;
}

const state: ButtonState = {
  currentMedia: null,
  hoverTimeout: null,
  isButtonHovered: false,
};

/**
 * Create the SVG icon for the button.
 */
function createIcon(): string {
  return `
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
      <polyline points="17 8 12 3 7 8"/>
      <line x1="12" y1="3" x2="12" y2="15"/>
    </svg>
  `;
}

/**
 * Create or get the floating button element.
 */
function getOrCreateButton(): HTMLButtonElement {
  let button = document.getElementById(BUTTON_ID) as HTMLButtonElement;
  
  if (!button) {
    button = document.createElement('button');
    button.id = BUTTON_ID;
    button.innerHTML = createIcon();
    button.title = 'Send to Szurubooru';
    button.type = 'button';
    
    // Style the button
    Object.assign(button.style, {
      position: 'fixed',
      width: '32px',
      height: '32px',
      borderRadius: '50%',
      background: '#6366f1',
      color: 'white',
      border: '2px solid white',
      cursor: 'pointer',
      zIndex: '2147483647',
      boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
      display: 'none',
      alignItems: 'center',
      justifyContent: 'center',
      transition: 'transform 0.15s ease, opacity 0.15s ease, background 0.15s ease',
      opacity: '0',
      pointerEvents: 'auto',
      padding: '0',
      margin: '0',
      boxSizing: 'border-box',
    });
    
    // Add hover styles
    button.addEventListener('mouseenter', () => {
      button.style.background = '#4f46e5';
      button.style.transform = 'scale(1.1)';
      state.isButtonHovered = true;
      
      // Clear hide timeout
      if (state.hoverTimeout) {
        clearTimeout(state.hoverTimeout);
        state.hoverTimeout = null;
      }
    });
    
    button.addEventListener('mouseleave', () => {
      button.style.background = '#6366f1';
      button.style.transform = 'scale(1)';
      state.isButtonHovered = false;
      
      // Schedule hide
      scheduleHide();
    });
    
    // Add active style
    button.addEventListener('mousedown', () => {
      button.style.transform = 'scale(0.95)';
    });
    
    button.addEventListener('mouseup', () => {
      button.style.transform = 'scale(1.1)';
    });
    
    document.body.appendChild(button);
  }
  
  return button;
}

/**
 * Position the button relative to a media element.
 */
function positionButton(button: HTMLElement, media: HTMLElement): void {
  const rect = media.getBoundingClientRect();
  
  // Position at top-left of the media
  const top = Math.max(8, rect.top + 8);
  const left = Math.max(8, rect.left + 8);
  
  // Make sure button stays within viewport
  const maxLeft = window.innerWidth - 40;
  const maxTop = window.innerHeight - 40;
  
  button.style.top = `${Math.min(top, maxTop)}px`;
  button.style.left = `${Math.min(left, maxLeft)}px`;
  button.style.display = 'flex';
  
  // Trigger reflow for animation
  button.offsetHeight;
  button.style.opacity = '1';
}

/**
 * Schedule hiding the button.
 */
function scheduleHide(): void {
  if (state.hoverTimeout) {
    clearTimeout(state.hoverTimeout);
  }
  
  state.hoverTimeout = setTimeout(() => {
    if (!state.isButtonHovered) {
      hideButton();
    }
  }, HIDE_DELAY_MS);
}

/**
 * Hide the floating button.
 */
function hideButton(): void {
  const button = document.getElementById(BUTTON_ID);
  if (button) {
    button.style.opacity = '0';
    setTimeout(() => {
      if (button.style.opacity === '0') {
        button.style.display = 'none';
      }
    }, 150);
  }
  state.currentMedia = null;
}

/**
 * Show the floating button for a media element.
 */
function showButton(media: HTMLElement): void {
  const button = getOrCreateButton();
  positionButton(button, media);
  state.currentMedia = media;
}

/**
 * Check if an element is grabbable media.
 */
export function isGrabbableMedia(element: HTMLElement): boolean {
  if (element.tagName === 'IMG') {
    const img = element as HTMLImageElement;
    const src = img.src;
    
    // Skip if not loaded or too small
    if (!img.complete || img.naturalWidth < 50 || img.naturalHeight < 50) {
      return false;
    }
    
    // Skip profile pictures, emojis, icons (common patterns)
    const skipPatterns = [
      /\/profile_images\//i,
      /\/avatar/i,
      /\/emoji\//i,
      /\/hashflags\//i,
      /\/badge/i,
      /\/icon/i,
      /_normal\./i,
      /_bigger\./i,
      /_mini\./i,
    ];
    
    for (const pattern of skipPatterns) {
      if (pattern.test(src)) {
        return false;
      }
    }
    
    return true;
  }
  
  if (element.tagName === 'VIDEO') {
    const video = element as HTMLVideoElement;
    return video.readyState >= 1; // HAVE_METADATA
  }
  
  return false;
}

/**
 * Initialize floating button functionality.
 * 
 * @param onGrab - Callback when the button is clicked with the media element
 */
export function initFloatingButton(
  onGrab: (media: HTMLElement) => void
): () => void {
  const button = getOrCreateButton();
  
  // Button click handler
  const handleButtonClick = (e: MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    
    if (state.currentMedia) {
      // Visual feedback
      button.style.background = '#22c55e';
      setTimeout(() => {
        button.style.background = '#6366f1';
      }, 200);
      
      onGrab(state.currentMedia);
    }
  };
  
  button.addEventListener('click', handleButtonClick);
  
  // Global mouseover for media detection
  const handleMouseOver = (e: MouseEvent) => {
    const target = e.target as HTMLElement;
    
    if (!isGrabbableMedia(target)) {
      return;
    }
    
    // Clear any existing timeout
    if (state.hoverTimeout) {
      clearTimeout(state.hoverTimeout);
      state.hoverTimeout = null;
    }
    
    // Delay showing button
    state.hoverTimeout = setTimeout(() => {
      showButton(target);
    }, HOVER_DELAY_MS);
  };
  
  // Hide button when mouse leaves media
  const handleMouseOut = (e: MouseEvent) => {
    const target = e.target as HTMLElement;
    
    if (state.currentMedia === target) {
      scheduleHide();
    }
  };
  
  // Handle scroll (reposition button)
  const handleScroll = () => {
    if (state.currentMedia && !state.isButtonHovered) {
      const button = document.getElementById(BUTTON_ID);
      if (button && button.style.display !== 'none') {
        positionButton(button, state.currentMedia);
      }
    }
  };
  
  document.addEventListener('mouseover', handleMouseOver);
  document.addEventListener('mouseout', handleMouseOut);
  window.addEventListener('scroll', handleScroll, { passive: true });
  
  // Return cleanup function
  return () => {
    button.removeEventListener('click', handleButtonClick);
    document.removeEventListener('mouseover', handleMouseOver);
    document.removeEventListener('mouseout', handleMouseOut);
    window.removeEventListener('scroll', handleScroll);
    
    if (state.hoverTimeout) {
      clearTimeout(state.hoverTimeout);
    }
    
    button.remove();
  };
}

/**
 * Show a toast notification on the page.
 */
export function showToast(message: string, type: 'success' | 'error' | 'info'): void {
  const id = 'ccc-toast-' + Date.now();
  const el = document.createElement('div');
  el.id = id;
  el.textContent = message;
  
  const colors = {
    success: '#22c55e',
    error: '#ef4444',
    info: '#3b82f6',
  };
  
  el.style.cssText = [
    'position:fixed',
    'bottom:24px',
    'right:24px',
    'max-width:320px',
    'padding:12px 16px',
    'border-radius:8px',
    'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
    'font-size:14px',
    'font-weight:500',
    'box-shadow:0 4px 12px rgba(0,0,0,0.25)',
    'z-index:2147483647',
    'pointer-events:none',
    `background:${colors[type]}`,
    'color:#fff',
  ].join(';');
  
  const style = document.createElement('style');
  style.textContent = '@keyframes ccc-toast-in{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}';
  document.head.appendChild(style);
  document.body.appendChild(el);
  el.style.animation = 'ccc-toast-in 0.2s ease';
  
  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transition = 'opacity 0.2s ease';
    setTimeout(() => {
      el.remove();
      style.remove();
    }, 200);
  }, 4000);
}

export default initFloatingButton;
