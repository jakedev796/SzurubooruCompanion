# Browser Extension

WXT-based extension for Chrome, Firefox, and Edge. Lets you send URLs and media to the CCC backend from supported sites.

## Install

Pre-built unpacked extensions are in the repo root [`builds/`](../builds/) folder. Or build from source (see below).

**Chrome / Edge:** go to `chrome://extensions`, enable Developer Mode, click "Load unpacked", and select the Chrome build folder (e.g. `builds/chrome-mv3/` or the path shown after building).

**Firefox:** go to `about:debugging#/runtime/this-firefox`, click "Load Temporary Add-on", and select any file inside the Firefox build folder (e.g. `builds/firefox-mv2/` or the path shown after building).

After loading, open the extension popup to set your CCC URL and API key. If the backend has multiple Szurubooru users configured, a user selector will appear in the popup.

## Build from source (developers)

**Prerequisites:** Node.js, npm.

```bash
cd browser-ext
npm install
```

**Build outputs:**

| Command | Output | Location |
|---------|--------|----------|
| `npm run build` | Unpacked Chrome extension | `.output/chrome-mv3/` |
| `npm run build:firefox` | Unpacked Firefox extension | `.output/firefox-mv2/` |

Load the corresponding `.output/...` folder in your browser as described above.