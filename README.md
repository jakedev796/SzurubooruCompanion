<p align="center">
  <img src="misc/styling/reimu.jpg" alt="Hakurei Reimu by kageharu" width="250" height="250" style="border-radius: 10px; object-fit: cover;"/>
</p>

_Artwork: Hakurei Reimu by [kageharu](https://twitter.com/kageharu) - [Source](https://danbooru.donmai.us/posts/5271521)_

# Szurubooru Companion

[![Status: WIP](https://img.shields.io/badge/status-WIP-orange)](https://github.com/jakedev796/SzurubooruCompanion) [![Python 3.11](https://img.shields.io/badge/python-3.11-blue)](https://github.com/jakedev796/SzurubooruCompanion) [![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ed?logo=docker&logoColor=white)](https://github.com/jakedev796/SzurubooruCompanion) [![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/jakedev796/SzurubooruCompanion/blob/main/LICENSE)

**A complete workflow for uploading media to [Szurubooru](https://github.com/rr-/szurubooru) from anywhere—browser or mobile—with automatic AI tagging, metadata extraction, and intelligent processing.**

Save media from Twitter, Pixiv, Danbooru, 4chan, and 100+ other sites. Share URLs from your phone, right-click images in Chrome, or tap the floating bubble. The CCC backend handles everything: downloading with gallery-dl/yt-dlp, AI tagging with WD14, and uploading to your Szurubooru instance.

> **Early Development Notice**
> This project is actively evolving. APIs and behavior may change. Built as a passion project for personal use—contributions and feedback welcome!

---

## ✨ Features

### **Multi-Platform Input**
- **Browser Extension** (Chrome, Firefox, Edge) — Right-click images or use the popup to send URLs
- **Mobile App** (Android) — Share from any app via system share sheet, floating bubble for instant clipboard capture, and built-in job status viewer
- **Web Dashboard** — Real-time job monitoring, queue status, and processing history

### **Intelligent Processing**
- **Automatic AI Tagging** — WD14 Tagger runs in-process (CPU or GPU), no separate container needed
- **Metadata Extraction** — gallery-dl and yt-dlp parse artist info, descriptions, ratings, and more
- **Smart Normalization** — Handles fxtwitter.com, fixupx.com, ddinstagram.com, and other redirect domains automatically
- **Site-Specific Handling** — Custom logic for Moeview infinite scrolls, 4chan boards, and special cases

### **Mobile-First Features**
- **Floating Bubble** — Optional overlay that sits on top of other apps; copy a URL anywhere, tap the bubble to queue it instantly
- **Visual Feedback** — Green glow on success, red pulse on failure—know the status without switching apps
- **Background Sync** — Optional folder monitoring for automated uploads from camera/downloads

### **Flexible Configuration**
- **Multi-User Support** — Configure multiple Szurubooru users; clients show a user selector for per-job assignment
- **Per-Site Cookies / Logins** — Environment-based cookie support for authenticated sites (Twitter, Sankaku, etc.)
- **Queue Management** — Monitor jobs in real-time, retry failures, and track upload history in the dashboard

### **Self-Hosted & Private**
- All processing happens on your infrastructure
- Clients never talk to Szurubooru directly—only to your CCC backend
- Easy reverse proxy setup with Nginx Proxy Manager or any standard proxy

---

## 🏛️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          INPUT SOURCES                          │
├─────────────────────┬──────────────────────┬────────────────────┤
│  Browser Extension  │    Mobile App        │   Web Dashboard    │
│  (Chrome/FF/Edge)   │    (Android)         │   (React + Vite)   │
│                     │                      │                    │
│  • Right-click      │  • Share sheet       │  • Queue monitor   │
│  • Popup submit     │  • Floating bubble   │  • Job history     │
│  • Context menu     │  • Job status viewer │  • Real-time logs  │
└──────────┬──────────┴──────────┬───────────┴──────────┬─────────┘
           │                     │                      │
           └─────────────────────┴──────────────────────┘
                                 ▼
              ┌─────────────────────────────────────┐
              │       CCC Backend (FastAPI)         │
              │   • Job queue (Redis + Postgres)    │
              │   • Background worker (sync/async)  │
              │   • WD14 Tagger (in-process)        │
              └──────────────┬──────────────────────┘
                             ▼
           ┌─────────────────────────────────────────┐
           │         DOWNLOAD & PROCESS              │
           ├──────────────────┬──────────────────────┤
           │   gallery-dl     │      yt-dlp          │
           │   • Metadata     │      • Videos        │
           │   • Multi-image  │      • Audio         │
           │   • Pagination   │      • Live streams  │
           └──────────────────┴──────────────────────┘
                             ▼
           ┌─────────────────────────────────────────┐
           │          AI TAGGING (WD14)              │
           │   • Character recognition               │
           │   • Object/scene detection              │
           │   • Style classification                │
           │   • Automatic threshold filtering       │
           └─────────────────┬───────────────────────┘
                             ▼
              ┌─────────────────────────────────────┐
              │       Szurubooru Instance           │
              │   • Upload media + metadata         │
              │   • Merge tags (AI + manual)        │
              │   • Multi-user attribution          │
              └─────────────────────────────────────┘
```

**Data Flow:** All clients send URLs to the CCC backend → Backend downloads, tags, and uploads → Szurubooru receives fully processed posts.

---

## 🚀 Quick Start

### Prerequisites
- Docker + Docker Compose
- Szurubooru instance (URL + API token)

### Setup

1. **Clone and configure:**
   ```bash
   git clone https://github.com/jakedev796/SzurubooruCompanion.git
   cd SzurubooruCompanion
   cp ccc/backend/.env.example ccc/backend/.env
   ```

2. **Edit `ccc/backend/.env`** with your Szurubooru credentials:
   ```env
   SZURU_URL=https://your-szurubooru.com
   SZURU_USERNAME=your-username
   SZURU_TOKEN=your-api-token
   ```

3. **Start the stack:**
   ```bash
   docker compose up -d
   ```

4. **Access services:**
   - **CCC Backend API:** `http://localhost:21425`
   - **CCC Dashboard:** `http://localhost:21430`
   - Configure reverse proxy (optional but recommended): [docs/reverse-proxy.md](docs/reverse-proxy.md)

---

## 📦 Components

### **CCC Backend**
FastAPI service that handles all processing. Includes background worker, job queue (Redis), database (Postgres), and WD14 tagger.
- **Port:** 21425
- **Config:** [ccc/backend/.env.example](ccc/backend/.env.example)
- **Tech:** Python, FastAPI, gallery-dl, yt-dlp, wdtagger

### **CCC Dashboard**
React web interface for monitoring the job queue and viewing processing history.
- **Port:** 21430
- **Features:** Real-time job status, queue overview, processing logs
- **Tech:** React, Vite, TailwindCSS

### **Browser Extension**
WXT-based extension for Chrome, Firefox, and Edge.
- **Install:** See [docs/browser-extension.md](docs/browser-extension.md)
- **Location:** Pre-built in [`builds/`](builds/)
- **Features:** Right-click context menu, popup submit, automatic URL detection

### **Mobile App**
Flutter Android app with share sheet integration, floating bubble overlay, and job monitoring.
- **Install:** See [docs/mobile-app.md](docs/mobile-app.md)
- **Location:** APK in [`builds/`](builds/)
- **Features:**
  - System share sheet integration
  - **Floating bubble overlay** — Tap to queue clipboard URLs from any app
  - Visual feedback (green glow = success, red pulse = failure)
  - Built-in job status viewer
  - Optional background folder sync

---

## ⚙️ Configuration

### Environment Variables
All backend configuration is done via `ccc/backend/.env`. See [ccc/backend/.env.example](ccc/backend/.env.example) for full options.

### Multi-User Support
Configure multiple Szurubooru users with comma-delimited credentials:

```env
SZURU_USERNAME=user1,user2,user3
SZURU_TOKEN=token1,token2,token3
```

The first user is the default. Clients (extension, mobile app, dashboard) will show a user selector when multiple users are configured.

### Site-Specific Configuration
Some sites require cookies or special handling. See [docs/sites.md](docs/sites.md) for:
- Confirmed working sites
- Cookie setup (Twitter, Sankaku, etc.)
- Special cases (Moeview, 4chan, etc.)

---

## 📚 Documentation

- **[Browser Extension Guide](docs/browser-extension.md)** — Build, install, and usage
- **[Mobile App Guide](docs/mobile-app.md)** — Build, install, floating bubble setup
- **[Reverse Proxy Setup](docs/reverse-proxy.md)** — Nginx Proxy Manager configuration
- **[Supported Sites](docs/sites.md)** — Confirmed sites and special configurations

---

## 🗂️ Project Structure

```
SzurubooruCompanion/
├── ccc/
│   ├── backend/            # FastAPI service + worker + wdtagger
│   └── frontend/           # React dashboard
├── browser-ext/            # WXT browser extension
├── mobile-app/             # Flutter Android app
├── builds/                 # Pre-built releases (extension, APK)
├── docs/                   # Detailed guides
└── docker-compose.yml      # Full stack orchestration
```

---

## 🛠️ Development

### Backend
```bash
cd ccc/backend
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
uvicorn main:app --reload
```

### Frontend
```bash
cd ccc/frontend
npm install
npm run dev
```

### Browser Extension
```bash
cd browser-ext
npm install
npm run dev          # Chrome
npm run dev:firefox  # Firefox
```

### Mobile App
```bash
cd mobile-app
flutter pub get
flutter run
```

---

## 🐛 Known Issues & TODO

- [ ] Finetune site extractors for edge cases
- [ ] Performance optimizations for large batch jobs
- [ ] Right-click individual images on Twitter/X (currently queues entire feed)
- [ ] iOS app (no current plans—contributions welcome)
- [ ] Cookie sync via extension (shelved—manual export works fine for now)

---

## 📜 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 🙏 Credits

- **WD14 Tagger:** [SmilingWolf/wd-tagger](https://huggingface.co/SmilingWolf/wd-tagger)
- **gallery-dl:** [mikf/gallery-dl](https://github.com/mikf/gallery-dl)
- **yt-dlp:** [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp)
- **Szurubooru:** [rr-/szurubooru](https://github.com/rr-/szurubooru)

Banner artwork: Hakurei Reimu by [kageharu](https://twitter.com/kageharu)
