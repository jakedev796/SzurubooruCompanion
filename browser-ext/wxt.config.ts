import { defineConfig } from "wxt";

export default defineConfig({
  manifest: {
    name: "Szurubooru Companion",
    description: "Right-click to send media to the Szurubooru Companion CCC.",
    permissions: ["contextMenus", "storage", "activeTab"],
    host_permissions: ["<all_urls>"],
  },
});
