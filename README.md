<p align="center">
  <img src="misc/styling/reimu.jpg" alt="Hakurei Reimu by kageharu" width="250" height="250" style="border-radius: 10px; object-fit: cover;"/>
</p>

_Artwork: Hakurei Reimu by [kageharu](https://twitter.com/kageharu) - [Source](https://danbooru.donmai.us/posts/5271521)_

# Szurubooru Companion

[![Status: WIP](https://img.shields.io/badge/status-WIP-orange)](https://github.com/jakedev796/SzurubooruCompanion) [![Python 3.11](https://img.shields.io/badge/python-3.11-blue)](https://github.com/jakedev796/SzurubooruCompanion) [![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ed?logo=docker&logoColor=white)](https://github.com/jakedev796/SzurubooruCompanion) [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/jakedev796/SzurubooruCompanion/blob/main/LICENSE)

A multi-component workflow for uploading media to [Szurubooru](https://github.com/rr-/szurubooru) from various sources (browser, mobile) with automatic AI tagging via WD14 Tagger and metadata parsing via gallery-dl / yt-dlp.

---

> **Disclaimer — Early work in progress**  
> This project is in early development. APIs and behaviour may change. Use at your own risk.  
> It was started as a passion project for my friend and me, so expect some bugs and rough edges. We welcome issues and contributions.

**Releases:** Current release builds (browser extension and mobile app) are in [`builds/`](builds/).

---

## TODO

- Finetune browser extension / ccc for popular sites
- Further enhancements to performance
- **Cookie sync (shelved):** Browser extension could capture cookies for sites (e.g. Twitter) and send them to CCC; CCC stores/updates them in Postgres and reads when needed instead of env. Would remove manual cookie export/paste.
- Allow right click individual images on TWT/X so it grabs the post and not the entire feed/profile

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
  mobile-app/           Flutter app (Android only; no iOS plans at this time)
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

Point your reverse proxy at these ports as needed; see [docs/reverse-proxy.md](docs/reverse-proxy.md) for setup.

### Browser Extension

**Install:** Pre-built builds are in [`builds/`](builds/). For build and load instructions, see [docs/browser-extension.md](docs/browser-extension.md).

### Mobile App (Flutter)

**Install:** Release APKs are in [`builds/`](builds/). For build and developer instructions, see [docs/mobile-app.md](docs/mobile-app.md).

## Ports

| Service | Port | Description |
|---------|------|-------------|
| ccc-backend | 21425 | FastAPI REST API + background worker + wdtagger |
| ccc-frontend | 21430 | React dashboard |
| postgres | internal | PostgreSQL |
| redis | internal | Redis |

## Configuration

All backend configuration is done via environment variables (see [ccc/backend/.env.example](ccc/backend/.env.example)).

### Multi-user support

To upload as different Szurubooru users, provide comma-delimited credentials. The first user is the default:

```env
SZURU_USERNAME=user1,user2
SZURU_TOKEN=token1,token2
```

Clients (browser extension, mobile app, dashboard) will show a user selector when multiple users are configured. Each job records which user it uploads as.

## Sites

Confirmed sites, extra configuration (Sankaku, Twitter, etc., via env vars), and special handling (Moeview, 4chan) are documented in [docs/sites.md](docs/sites.md).

## WD14 Tagger

WD14 runs in-process in the CCC backend using the `wdtagger` library. No separate tagger container is required. The backend uses CPU by default; if the host has a CUDA-capable GPU and PyTorch sees it, the tagger will use it automatically.

## Reverse proxy

Route `/api` to the backend and `/` to the frontend when exposing via a single host. See [docs/reverse-proxy.md](docs/reverse-proxy.md) for Nginx Proxy Manager and alternate setup.