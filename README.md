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

## Features

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

### **User Management & Security**
- **Database-Backed User System** — Create and manage users through the dashboard with JWT authentication
- **Per-User Credentials** — Each user configures their own Szurubooru and site credentials (Twitter, Sankaku, etc.)
- **Encrypted Storage** — All credentials encrypted in database using Fernet
- **Role-Based Access** — Admin and user roles with granular permissions
- **Category Mappings** — Map WD14 tag categories to your Szurubooru instance's custom categories

### **Queue Management**
- **Real-Time Monitoring** — Track job status, view processing logs, and manage queue in the dashboard
- **User-Specific Jobs** — Jobs are attributed to the user who submitted them
- **Retry & Control** — Pause, resume, stop, or retry failed jobs with visual feedback

### **Self-Hosted & Private**
- All processing happens on your infrastructure
- Clients never talk to Szurubooru directly—only to your CCC backend
- Easy reverse proxy setup with Nginx Proxy Manager or any standard proxy

---

## Architecture

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

## Quick Start

### Prerequisites
- Docker (and Docker Compose if using compose)
- Szurubooru instance (URL + API token)

### Setup

1. **Clone and configure:**
   ```bash
   git clone https://github.com/jakedev796/SzurubooruCompanion.git
   cd SzurubooruCompanion
   cp ccc/backend/.env.example ccc/backend/.env
   ```

2. **Edit `ccc/backend/.env`** with admin credentials and encryption key:
   ```env
   # Admin account (required)
   ADMIN_USER=admin
   ADMIN_PASSWORD=your-secure-password

   # Encryption key for credentials (required - generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
   ENCRYPTION_KEY=your-generated-encryption-key
   ```

   > **Note:** Szurubooru credentials are configured per-user through the dashboard. The browser extension and mobile app use **JWT login** (username/password) to authenticate with the CCC backend; no API key is used.

3. **Start CCC (single s6 image from GHCR):**
   ```bash
   docker compose up -d
   ```
   Or without compose:
   ```bash
   docker run -d --name szurubooru-companion \
     -p 21425:21425 \
     --env-file ccc/backend/.env \
     -v szurubooru-companion-data:/data \
     -v szurubooru-companion-config:/config \
     ghcr.io/jakedev796/szuruboorucompanion:latest
   ```

4. **Access:**
   - **CCC API and Dashboard:** `http://localhost:21425` (login with admin credentials)
   - Configure reverse proxy (optional but recommended): [docs/reverse-proxy.md](docs/reverse-proxy.md)

5. **Configure through dashboard:**
   - Login with your admin credentials
   - Navigate to Settings → My Profile
   - Enter your Szurubooru URL, username, and API token
   - Configure site credentials if needed (Settings → Site Credentials)

**Development:** For local development with separate backend, frontend, Postgres, and Redis, use the dev compose:
`docker compose -f docker-compose.dev.yml up -d`. Backend at 21425, dashboard at 21430.

---

## Components

### **CCC Backend**
FastAPI service that handles all processing. Includes background worker, job queue (Redis), database (Postgres), and WD14 tagger.
- **Port:** 21425
- **Config:** [ccc/backend/.env.example](ccc/backend/.env.example)
- **Tech:** Python, FastAPI, gallery-dl, yt-dlp, wdtagger

### **CCC Dashboard**
React web interface with user management, settings, and job monitoring.
- **Port:** 21430 (dev compose) / served with backend at 21425 (s6 single image)
- **Features:**
  - User authentication with JWT tokens
  - User management (admin only) — Create, edit, deactivate users
  - Personal settings — Configure Szurubooru credentials and site authentication
  - Global settings (admin only) — WD14 tagger, worker concurrency, timeouts
  - Category mappings — Map internal tag categories to Szurubooru categories
  - Real-time job monitoring and queue management
- **Tech:** React, Vite

### **Browser Extension**
WXT-based extension for Chrome, Firefox, and Edge.
- **Install:** See [docs/browser-extension.md](docs/browser-extension.md)
- **Location:** [GitHub Releases](https://github.com/jakedev796/SzurubooruCompanion/releases) (chrome-mv3.zip, firefox-mv2.zip)
- **Features:** Right-click context menu, popup submit, automatic URL detection

### **Mobile App**
Flutter Android app with share sheet integration, floating bubble overlay, and job monitoring.
- **Install:** See [docs/mobile-app.md](docs/mobile-app.md)
- **Location:** APK from [GitHub Releases](https://github.com/jakedev796/SzurubooruCompanion/releases); in-app updater checks for updates.
- **Features:**
  - System share sheet integration
  - **Floating bubble overlay** — Tap to queue clipboard URLs from any app
  - Visual feedback (green glow = success, red pulse = failure)
  - Built-in job status viewer
  - Optional background folder sync

---

## Configuration

### Initial Setup

1. **Generate encryption key:**
   ```bash
   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
   ```

2. **Configure environment variables** in `ccc/backend/.env`:
   ```env
   ADMIN_USER=admin
   ADMIN_PASSWORD=your-secure-password
   ENCRYPTION_KEY=<key-from-step-1>
   ```

3. **Start the stack:**
   ```bash
   docker compose up -d
   ```

4. **Login to dashboard** at `http://localhost:21430` with your admin credentials

### Dashboard Configuration

After logging in, configure settings through the dashboard:

#### **My Profile** (Settings → My Profile)
- Szurubooru URL, username, and API token
- Test connection to verify credentials
- Fetch and map tag categories from your Szurubooru instance

#### **Site Credentials** (Settings → Site Credentials)
Configure authentication for sites that require login credentials (Twitter, Sankaku, Danbooru, Reddit, etc.). All credentials are encrypted in the database and never stored in plain text.

#### **Global Settings** (Settings → Global Settings - Admin only)
- **WD14 Tagger:** Enable/disable, model selection, confidence threshold, max tags
- **Worker Settings:** Concurrency, timeouts, retry configuration
- Container restart required for WD14 changes to take effect

#### **User Management** (Settings → Users - Admin only)
- Create new users with username, password, and role (admin/user)
- Edit users: Reset password, promote/demote admin, activate/deactivate
- Each user configures their own Szurubooru and site credentials

#### **Category Mappings** (Settings → My Profile)
Map internal tag categories to your Szurubooru instance's custom categories:
- **general** → Default category for general tags
- **artist** → Artist/creator tags
- **character** → Character name tags
- **copyright** → Series/franchise tags
- **meta** → Meta information tags

Fetch categories directly from Szurubooru using "Fetch Tag Categories" button.

### Environment Variables Reference
See [ccc/backend/.env.example](ccc/backend/.env.example) for all available options. .

### Site-Specific Configuration
Some sites require cookies or special handling. See [docs/sites.md](docs/sites.md) for:
- Confirmed working sites
- Cookie/authentication setup
- Special cases (Moeview, 4chan, etc.)

---

## Documentation

- **[Browser Extension Guide](docs/browser-extension.md)** — Build, install, and usage
- **[Mobile App Guide](docs/mobile-app.md)** — Build, install, floating bubble setup
- **[Reverse Proxy Setup](docs/reverse-proxy.md)** — Nginx Proxy Manager configuration
- **[Supported Sites](docs/sites.md)** — Confirmed sites and special configurations

---

## Project Structure

```
SzurubooruCompanion/
├── ccc/
│   ├── backend/            # FastAPI service + worker + wdtagger
│   └── frontend/           # React dashboard
├── browser-ext/            # WXT browser extension
├── mobile-app/             # Flutter Android app
├── builds/                 # Local use only (only for local dev); distribution via GitHub Releases
├── docs/                   # Detailed guides
├── VERSION                 # Single version for releases (versionName+versionCode)
├── CHANGELOG.md            # Changelog for all components
├── docker-compose.yml      # Production: s6 image from GHCR
└── docker-compose.dev.yml  # Development: backend, frontend, postgres, redis
```

---

## Development

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

## Known Issues & TODO

### In Progress
- [ ] Finetune site extractors for edge cases
- [ ] Performance optimizations for large batch jobs
- [ ] Right-click individual images on Twitter/X (currently queues entire feed)

### Future Enhancements
- [ ] Password reset via email
- [ ] Two-factor authentication (2FA)
- [ ] Session management (revoke tokens)
- [ ] Encryption key rotation tool
- [ ] Per-user WD14 settings
- [ ] Audit log viewer in dashboard
- [ ] iOS app (no current plans—contributions welcome)

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Credits

- **WD14 Tagger:** [SmilingWolf/wd-tagger](https://huggingface.co/SmilingWolf/wd-tagger)
- **gallery-dl:** [mikf/gallery-dl](https://github.com/mikf/gallery-dl)
- **yt-dlp:** [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp)
- **Szurubooru:** [rr-/szurubooru](https://github.com/rr-/szurubooru)

Banner artwork: Hakurei Reimu by [kageharu](https://twitter.com/kageharu)
