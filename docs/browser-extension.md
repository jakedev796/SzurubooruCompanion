# Browser Extension

WXT-based extension for Chrome, Firefox, and Edge. Provides right-click context menus and popup interface for sending URLs to the CCC backend.

---

## Installation

### Pre-built Extension

Pre-built unpacked extensions are available in [`builds/`](../builds/).

**Chrome / Edge:**
1. Navigate to `chrome://extensions`
2. Enable "Developer mode" (toggle in top-right)
3. Click "Load unpacked"
4. Select the Chrome build folder: `builds/chrome-mv3/`

**Firefox:**
1. Navigate to `about:debugging#/runtime/this-firefox`
2. Click "Load Temporary Add-on"
3. Select any file inside the Firefox build folder: `builds/firefox-mv2/`

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

Load the `.output/` folder in your browser following the installation instructions above.

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
