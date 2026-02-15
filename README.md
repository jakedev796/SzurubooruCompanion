<p align="center">
  <img src="misc/styling/reimu.jpg" alt="Hakurei Reimu by kageharu" width="125" height="125" style="border-radius: 10px; object-fit: cover;"/>
</p>

_Artwork: Hakurei Reimu by [kageharu](https://twitter.com/kageharu) - [Source](https://danbooru.donmai.us/posts/5271521)_

# Szurubooru Companion

[![Status: WIP](https://img.shields.io/badge/status-WIP-orange)](https://github.com/jakedev796/SzurubooruCompanion) [![Python 3.11](https://img.shields.io/badge/python-3.11-blue)](https://github.com/jakedev796/SzurubooruCompanion) [![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ed?logo=docker&logoColor=white)](https://github.com/jakedev796/SzurubooruCompanion) [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/jakedev796/SzurubooruCompanion/blob/main/LICENSE)

A multi-component workflow for uploading media to [Szurubooru](https://github.com/rr-/szurubooru) from various sources (browser, mobile) with automatic AI tagging via WD14 Tagger and metadata parsing via gallery-dl / yt-dlp.

---

> **Disclaimer — Early work in progress**  
> This project is in early development. APIs and behaviour may change. Use at your own risk.

---

## TODO

- Finetune browser extension for popular sites
- Get mobile app working
- Further enhancements to performance

## Architecture

```
Clients (Browser Ext, Mobile App)
        |
        v
   CCC Backend  -->  gallery-dl / yt-dlp  (download)
        |             wdtagger (in-process AI tagging)
        v
   Szurubooru   (upload)
```

All media flows through the **CCC** backend. Clients never talk to Szurubooru directly. Use your existing reverse proxy (e.g. Nginx Proxy Manager) to expose services publicly.

## Repository Layout

```
SzurubooruCompanion/
  docker-compose.yml    Root-level compose for the full stack
  ccc/
    backend/            Python (FastAPI) - API + background worker (includes wdtagger)
    frontend/            React + Vite dashboard
  browser-ext/          WXT browser extension (Chrome, Firefox, Edge)
  mobile-app/           Release builds only (APK and iOS package in folder root)
```

## Quick Start

```bash
cp ccc/backend/.env.example ccc/backend/.env
# Edit ccc/backend/.env with your Szurubooru URL, token, etc.
docker compose up -d
```

This starts:

- **ccc-backend** on port 21425 (API + worker; AI tagging via wdtagger in-process)
- **ccc-frontend** on port 21430 (dashboard)
- **postgres** (job database, internal only)
- **redis** (queue/cache, internal only)

Point your Nginx Proxy Manager (or other reverse proxy) at these ports as needed (more information at the bottom of README).

### Browser Extension

```bash
cd browser-ext
npm install
```

**Build outputs:**

| Command | Output | Location |
|---------|--------|----------|
| `npm run build` | Unpacked Chrome extension | `.output/chrome-mv3/` |
| `npm run build:firefox` | Unpacked Firefox extension | `.output/firefox-mv2/` |


**Loading in Chrome:** go to `chrome://extensions`, enable Developer Mode, click "Load unpacked", and point it at `browser-ext/.output/chrome-mv3/`.

**Loading in Firefox:** go to `about:debugging#/runtime/this-firefox`, click "Load Temporary Add-on", and select any file inside `browser-ext/.output/firefox-mv2/`.

Open the extension popup to configure your CCC URL and API key.

### Mobile App | Currently a WIP

The `mobile-app/` folder in this repo contains **release builds only**: the Android APK and (when built) the iOS package are placed at the root of `mobile-app/`. Development sources (React Native project, `android/`, `ios/`, etc.) are not tracked in the repo.

**Install (end users):**

- **Android:** Sideload the APK from `mobile-app/` (e.g. copy to device and open, or use `adb install`).
- **iOS:** Install the package from `mobile-app/` via your preferred method (e.g. TestFlight, direct install).

After installing, open the app and set the CCC URL in Settings. Use the system share sheet to send URLs or media to the app.

## Ports

| Service | Port | Description |
|---------|------|-------------|
| ccc-backend | 21425 | FastAPI REST API + background worker + wdtagger |
| ccc-frontend | 21430 | React dashboard |
| postgres | internal | PostgreSQL |
| redis | internal | Redis |

## Configuration

All backend configuration is done via environment variables (see `ccc/backend/.env.example`):

| Variable | Description |
|----------|-------------|
| `SZURU_URL` | Szurubooru server URL |
| `SZURU_USERNAME` | Szurubooru username |
| `SZURU_TOKEN` | Szurubooru API token |
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection string |
| `WD14_ENABLED` | Enable/disable in-process AI tagging |
| `WD14_MODEL` | Hugging Face model repo (default: SmilingWolf/wd-swinv2-tagger-v3) |
| `GALLERY_DL_SANKAKU_USERNAME` | Sankaku (sankaku.app / sankakucomplex.com) login username; used when job URL is Sankaku |
| `GALLERY_DL_SANKAKU_PASSWORD` | Sankaku login password |
| `API_KEY` | Optional API key for client auth |

## Confirmed sites

The following sites have been confirmed working.
- An asterisk (\*) indicates caveats (see sections below).
- Double asterisk (\**) indicates no tag extraction is available (see sections below).

| Site |
|------|
| Sankaku\* |
| Yande.re |
| X / Twitter |
| Danbooru |
| Moeview\* |
| 4chan\** |

In addition, any site [supported by gallery-dl](https://github.com/mikf/gallery-dl) may work; the list above is only what has been explicitly tested.

## Sites requiring extra configuration

Some sources need additional backend configuration (env vars) for gallery-dl to succeed. Without them, jobs from these sites may fail with "Unsupported URL" or similar.

| Site | Domains | Required configuration |
|------|---------|------------------------|
| **Sankaku** | sankaku.app, chan.sankakucomplex.com, idol.sankakucomplex.com, www.sankakucomplex.com | Set `GALLERY_DL_SANKAKU_USERNAME` and `GALLERY_DL_SANKAKU_PASSWORD` in `ccc/backend/.env`. Login is required for the extractor to work. |
| **Twitter / X** | twitter.com, x.com | **Cookies required for reliable access.** Username/password alone is often insufficient due to Twitter's API restrictions and rate limits. See [Twitter Cookie Setup](#twitter-cookie-setup) below. |

### Twitter Cookie Setup

Twitter authentication in gallery-dl works best with browser cookies. Due to Twitter's API restrictions, username/password authentication alone is often unreliable. Follow these steps to export and configure Twitter cookies:

1. **Install a browser extension** to export cookies:
   - Chrome: "Get cookies.txt LOCALLY" or "EditThisCookie"
   - Firefox: "Get cookies.txt" or "Cookie Quick Manager"

2. **Export cookies** while logged into Twitter:
   - Navigate to [twitter.com](https://twitter.com) and ensure you're logged in
   - Open the cookie extension and export cookies in **Netscape format**
   - Save the exported cookies to `local-dev/twitter-cookies.txt` in this project

3. **Restart the Docker container** after updating cookies:
   ```bash
   docker compose restart ccc-backend
   ```

**Important notes:**
- Cookies expire and need periodic refresh (typically every few weeks)
- If Twitter downloads start failing with authentication errors, refresh your cookies
- The `local-dev/` directory is in `.gitignore` to prevent accidentally committing cookies

## Sites requiring special handling

Some sites are aggregators or viewers that display content from other sources. gallery-dl may not support the aggregator URL; you need to send the **underlying source link** to CCC instead of the page you are on.

| Site | What to do |
|------|------------|
| **Moeview / moebooru** (moeview.app, etc.) | Do not "Send page URL to Szurubooru" from the Moeview page. Use the **source** link (e.g. in the top-right: "Source: yande.re" or similar). Right-click that source link and choose "Send link to Szurubooru" so CCC receives the actual booru URL (e.g. yande.re) that gallery-dl supports. |
| **4chan** | Do not send the thread page URL. Either have the **specific media open in a tab by itself** (e.g. the image/video URL) and use "Send page URL to Szurubooru", or right-click the **link to the media** (the image or video link on the thread) and choose "Send link to Szurubooru". Same idea as Moeview: CCC must receive the direct media URL, not the thread. **No tag extraction available for obvious reasons.** |

## WD14 Tagger

WD14 runs in-process in the CCC backend using the `wdtagger` library. No separate tagger container is required. The backend uses CPU by default; if the host has a CUDA-capable GPU and PyTorch sees it, the tagger will use it automatically.

## Dashboard behind a reverse proxy

The dashboard (frontend) uses relative `/api` URLs. If you expose the app via a single host (e.g. `https://ccc.example.com`), you **must** route `/api` to the backend and `/` to the frontend; otherwise the dashboard will get HTML instead of JSON and show: "API returned HTML instead of JSON".

**Nginx Proxy Manager:** add a proxy host for your domain, then add two **Custom locations**:

- Path: `/api` -> Forward to: `ccc-backend:21425` (or `http://host-ip:21425` if NPM is not in Docker).
- Path: `/` (or leave default) -> Forward to: `ccc-frontend:21430`.

Alternatively, build the frontend with the API on a separate URL: set `VITE_API_BASE=https://api.ccc.example.com` (or `http://host:21425` for same-machine access) when running `npm run build` in `ccc/frontend`, then the dashboard will call that URL instead of relative `/api`.