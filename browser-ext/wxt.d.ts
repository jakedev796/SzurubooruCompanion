/**
 * Type declarations for WXT browser API.
 * WXT provides the `browser` global and `defineBackground`/`defineContentScript` functions at build time.
 */

import type { Browser } from 'webextension-polyfill';

declare global {
  const browser: Browser;
  
  // WXT helper functions
  function defineBackground(callback: () => void): void;
  function defineBackground(definition: { main(): void; persistent?: boolean; type?: 'module'; include?: string[]; exclude?: string[] }): void;
  
  interface ContentScriptContext {
    /** Isolated CSS styles from the content script */
    readonly isValid: boolean;
    /** Called when the content script is invalidated */
    onInvalidated: EventTarget;
  }
  
  interface ContentScriptDefinition {
    matches: string[];
    excludeMatches?: string[];
    includeGlobs?: string[];
    excludeGlobs?: string[];
    allFrames?: boolean;
    runAt?: 'document_start' | 'document_end' | 'document_idle';
    matchAboutBlank?: boolean;
    matchOriginAsFallback?: boolean;
    world?: 'ISOLATED' | 'MAIN';
    include?: string[];
    exclude?: string[];
    cssInjectionMode?: 'manifest' | 'manual' | 'ui';
    registration?: 'manifest' | 'runtime';
    main(ctx?: ContentScriptContext): void | Promise<void>;
  }
  
  function defineContentScript(definition: ContentScriptDefinition): void;
  function defineContentScript(callback: () => void): void;
}

export {};
