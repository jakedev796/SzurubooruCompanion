# Szurubooru Companion

A multi-component workflow for uploading media to [Szurubooru](https://github.com/rr-/szurubooru) from various sources (browser, mobile) with automatic AI tagging via WD14 Tagger and metadata parsing via gallery-dl / yt-dlp.

## Architecture

```
Clients (Browser Ext, Mobile App)
        |
        v
   CCC Backend  -->  gallery-dl / yt-dlp  (download)
        |
        v
   WD14 Tagger  (AI tagging, CPU by default)
        |
        v
   Szurubooru   (upload)
```

All media flows through the **CCC (Command & Control Center)** backend. Clients never talk to Szurubooru directly. Use your existing reverse proxy (e.g. Nginx Proxy Manager) to expose services publicly.

## Repository Layout

```
SzurubooruCompanion/
  docker-compose.yml    Root-level compose for the full stack
  ccc/
    backend/            Python (FastAPI) - API + background worker
    frontend/            React + Vite dashboard
    wd14-tagger/        Dockerfile for the WD14 tagger sidecar
  browser-ext/          WXT browser extension (Chrome, Firefox, Edge)
  mobile-app/           Release builds only (APK and iOS package in folder root)
  reference/             Prior implementation (reference only)
```

## Quick Start

```bash
cp ccc/backend/.env.example ccc/backend/.env
# Edit ccc/backend/.env with your Szurubooru URL, token, etc.
docker compose up -d
```

This starts:

- **ccc-backend** on port 21425 (API + worker)
- **ccc-frontend** on port 21430 (dashboard)
- **wd14-tagger** on port 21435 (AI tagging, CPU)
- **postgres** (job database, internal only)
- **redis** (queue/cache, internal only)

Point your Nginx Proxy Manager (or other reverse proxy) at these ports as needed.

### Dashboard behind a reverse proxy

The dashboard (frontend) uses relative `/api` URLs. If you expose the app via a single host (e.g. `https://ccc.example.com`), you **must** route `/api` to the backend and `/` to the frontend; otherwise the dashboard will get HTML instead of JSON and show: "API returned HTML instead of JSON".

**Nginx Proxy Manager:** add a proxy host for your domain, then add two **Custom locations**:

- Path: `/api` -> Forward to: `ccc-backend:21425` (or `http://host-ip:21425` if NPM is not in Docker).
- Path: `/` (or leave default) -> Forward to: `ccc-frontend:21430`.

Alternatively, build the frontend with the API on a separate URL: set `VITE_API_BASE=https://api.ccc.example.com` (or `http://host:21425` for same-machine access) when running `npm run build` in `ccc/frontend`, then the dashboard will call that URL instead of relative `/api`.

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
| `npm run zip` | Chrome `.zip` for store upload | `.output/` |
| `npm run zip:firefox` | Firefox `.zip` for store upload | `.output/` |

**Loading in Chrome:** go to `chrome://extensions`, enable Developer Mode, click "Load unpacked", and point it at `browser-ext/.output/chrome-mv3/`.

**Loading in Firefox:** go to `about:debugging#/runtime/this-firefox`, click "Load Temporary Add-on", and select any file inside `browser-ext/.output/firefox-mv2/`.

Open the extension popup to configure your CCC URL and API key.

### Mobile App

The `mobile-app/` folder in this repo contains **release builds only**: the Android APK and (when built) the iOS package are placed at the root of `mobile-app/`. Development sources (React Native project, `android/`, `ios/`, etc.) are not tracked in the repo.

**Install (end users):**

- **Android:** Sideload the APK from `mobile-app/` (e.g. copy to device and open, or use `adb install`).
- **iOS:** Install the package from `mobile-app/` via your preferred method (e.g. TestFlight, direct install).

After installing, open the app and set the CCC URL in Settings. Use the system share sheet to send URLs or media to the app.

## Ports

| Service | Port | Description |
|---------|------|-------------|
| ccc-backend | 21425 | FastAPI REST API + background worker |
| ccc-frontend | 21430 | React dashboard (static file server) |
| wd14-tagger | 21435 | WD14 Tagger API (CPU) |
| postgres | internal | PostgreSQL (not exposed to host by default) |
| redis | internal | Redis (not exposed to host by default) |

## Configuration

All backend configuration is done via environment variables (see `ccc/backend/.env.example`):

| Variable | Description |
|----------|-------------|
| `SZURU_URL` | Szurubooru server URL |
| `SZURU_USERNAME` | Szurubooru username |
| `SZURU_TOKEN` | Szurubooru API token |
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection string |
| `WD14_TAGGER_URL` | WD14 Tagger API URL |
| `WD14_ENABLED` | Enable/disable AI tagging |
| `API_KEY` | Optional API key for client auth |

## WD14 Tagger

The WD14 tagger runs on CPU by default as a companion container. For GPU acceleration, use `ccc/wd14-tagger/Dockerfile.gpu` instead and uncomment the NVIDIA deploy block in `docker-compose.yml`.

## API

### Create job (URL)

```
POST /api/jobs
{ "url": "https://example.com/image.jpg" }
```

### Create job (file upload)

```
POST /api/jobs/upload
Content-Type: multipart/form-data
file=@image.jpg
```

### List jobs

```
GET /api/jobs?status=completed&offset=0&limit=50
```

### Get stats

```
GET /api/stats
```
