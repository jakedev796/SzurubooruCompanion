# Browser Extension

WXT-based extension for Chrome, Firefox, and Edge. Provides right-click context menus and popup interface for sending URLs to the CCC backend.

---

## Installation

### Official releases (GitHub)

Download the latest [chrome-mv3.zip](https://github.com/jakedev796/SzurubooruCompanion/releases) or [firefox-mv2.zip](https://github.com/jakedev796/SzurubooruCompanion/releases), unzip, then load the unpacked folder in your browser.

**Chrome / Edge:**
1. Unzip `chrome-mv3.zip` to a folder
2. Navigate to `chrome://extensions`
3. Enable "Developer mode" (toggle in top-right)
4. Click "Load unpacked" and select the unzipped folder

**Firefox:**
1. Unzip `firefox-mv2.zip` to a folder
2. Navigate to `about:debugging#/runtime/this-firefox`
3. Click "Load Temporary Add-on"
4. Select any file inside the unzipped folder (e.g. `manifest.json`)

### Local builds

If you [build from source](#building-from-source), output is in `browser-ext/.output/chrome-mv3/` and `browser-ext/.output/firefox-mv2/`. You can load those folders directly, or copy them into `builds/` for local use (that directory is not used for distribution).

### Configuration

After loading the extension:
1. Click the extension icon in your browser toolbar
2. Enter your CCC backend URL (e.g., `https://ccc.example.com` or `http://localhost:21425`)
3. Log in with your dashboard username and password (JWT authentication; no API key is used)
4. If the backend has multiple Szurubooru users configured, a user selector will appear

---

## Usage

### Context Menu (Right-click)

**Send Link to Szurubooru:**
- Right-click any link → "Send link to Szurubooru"
- Queues the link URL directly

**Send Image to Szurubooru:**
- Right-click any image → "Send image to Szurubooru"
- Queues the image source URL

**Send Page to Szurubooru:**
- Right-click anywhere → "Send page URL to Szurubooru"
- Queues the current page URL

### Popup Interface

Click the extension icon to open the popup:
- View backend connection status
- Change selected Szurubooru user (if multiple users configured)
- Quick submit current page URL

---

## Building from Source

**Prerequisites:**
- Node.js 18+ and npm

**Build commands:**

```bash
cd browser-ext
npm install

# Chrome/Edge (Manifest V3)
npm run build
# Output: .output/chrome-mv3/

# Firefox (Manifest V2)
npm run build:firefox
# Output: .output/firefox-mv2/
```

**Development mode:**

```bash
# Chrome with hot reload
npm run dev

# Firefox with hot reload
npm run dev:firefox
```

Load the `.output/` folder in your browser using the same steps as in [Installation](#installation) (Load unpacked / Load Temporary Add-on).

---

## Supported Sites

The extension works with any URL. Site compatibility depends on the CCC backend's support via gallery-dl and yt-dlp. See [docs/sites.md](sites.md) for confirmed working sites and special configurations.

---

## Troubleshooting

**Extension doesn't appear after loading:**
- Ensure you selected the correct build folder (chrome-mv3 for Chrome/Edge, firefox-mv2 for Firefox)
- Check browser console for errors
- Try reloading the extension

**"Failed to queue" error:**
- Verify the backend URL is correct and accessible
- Check that the CCC backend is running
- Ensure you are logged in (username/password); re-login if your session expired

**Context menu items not appearing:**
- Reload the extension
- Check that the extension has permission to access the current site
- Some browser internal pages (chrome://, about://) don't support extensions
