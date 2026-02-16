import { defineConfig } from "wxt";

export default defineConfig({
  outDir: "../builds/browser-ext",
  manifest: {
    name: "Szurubooru Companion",
    description: "Right-click to send media to the Szurubooru Companion CCC.",
    permissions: ["contextMenus", "storage", "activeTab", "notifications", "scripting"],
    host_permissions: ["<all_urls>"],
    icons: {
      "16": "icon/16.png",
      "32": "icon/32.png",
      "128": "icon/128.png",
      "192": "icon/192.png",
    },
    action: {
      default_icon: {
        "16": "icon/16.png",
        "32": "icon/32.png",
      },
    },
  },
  // Content scripts for supported sites
  contentScripts: [
    {
      matches: [
        "*://*.twitter.com/*",
        "*://*.x.com/*",
        "*://*.misskey.io/*",
        "*://*.misskey.art/*",
        "*://*.misskey.net/*",
        "*://*.misskey.design/*",
        "*://*.misskey.xyz/*",
        "*://*.mi.0px.io/*",
        "*://*.misskey.pizza/*",
        "*://*.misskey.cloud/*",
        "*://danbooru.donmai.us/*",
        "*://safebooru.org/*",
        "*://*.gelbooru.com/*",
        "*://rule34.xxx/*",
        "*://yande.re/*",
      ],
      runAt: "document_idle",
    },
  ],
});
