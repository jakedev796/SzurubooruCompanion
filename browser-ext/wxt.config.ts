import { defineConfig } from "wxt";

export default defineConfig({
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
});
