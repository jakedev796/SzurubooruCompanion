# Changelog

All notable changes to Szurubooru Companion (CCC, browser extension, mobile app) are documented here. Unreleased notes go under [Unreleased] by component.

## [Unreleased]

### CCC - Frontend

### CCC - Backend

### Mobile App

### Browser Extension


## [1.0.5] - 2026-02-19

### Mobile App
- Fix first-launch UX: only start bubble/notification when backend is configured and user is authenticated; stop services when not configured so the app stays on SetupScreen instead of closing.
- Match frontend design for setup and login screens (hero image, quote, card layout). Add reimu.jpg asset; remove AppBar; add "Auth details are not stored in backups." note on login restore.
- Fix CompanionForegroundService build by hoisting backendUrl into scope for the catch block; only run health check when URL is not blank.
- Align status colors with frontend (pending=orange, stopped=slate, failed=red). Add AppColors.slate and update AppStatusColors.forStatus().

### CCC - Frontend
- Dashboard: add failed count to 30-day chart (secondary series/gradient). Refactor status colors (stopped=slate vs failed=red). Add Lucide icons to stat cards and status badges; reorder stats to Pending → Active → Completed → Merged → Stopped → Failed.
- Job list/detail: add status icons and reorder pill order; filter pills show icons.
- Source URLs on reload: include source_override in list API so SOURCE column stays populated after refresh. Add source_override to JobSummary type.

### CCC - Backend
- Fix chan.sankakucomplex.com handling: do not normalize to www.sankakucomplex.com (uses different post ID format).
- Note: gallery-dl may report "'invalid id'" errors for chan.sankakucomplex.com numeric post IDs due to API limitations.
- Stats: daily_uploads returns per-day failed count; by_status keeps completed and merged separate for dashboard cards.
- Jobs list: return source_override in job summary for list/dashboard. Add source_override to JobSummaryOut.


## [1.0.4] - 2026-02-18

### CCC - Backend
- Add Oxibooru compatibility — works as a drop-in replacement for Szurubooru.
- Fix missing `fetch_tag_categories` function (removed in refactor).
- Manual job retries now respect the global retry_delay setting.
- Fix automatic retries to properly respect retry_delay by keeping jobs in FAILED status during delay period.

### Docs
- Update README to mention Oxibooru support with links.

## [1.0.3] - 2026-02-18

### Mobile App

- Fix false "update available" after installing an update and restarting the app: pending update is validated against current version and cleared when launching install.

## [1.0.2] - 2026-02-18

### Mobile App

- Update dialog and notification: show changelog as plain text (markdown stripped).
- Update flow notifications use separate IDs from the persistent status notification so "Downloading" and "Update ready" are no longer replaced by it.

## [1.0.1] - 2026-02-18

### Mobile App

- Fix in-app update check when GitHub returns version.json as raw JSON string (parse via jsonDecode when response is not already a map).


## [1.0.0] - 2026-02-17

Initial release.

### CCC (Backend + Dashboard)

- FastAPI backend with JWT auth, user management, and encrypted per-user credentials.
- React dashboard: job queue, real-time monitoring, category mappings, global and user settings.
- Job queue (Redis + Postgres), background worker, WD14 tagger (in-process).
- gallery-dl and yt-dlp for downloads; site-specific handlers and metadata extraction.
- Single s6 image for production (Postgres + Redis + backend + frontend); dev compose for local development.

### Browser Extension

- Chrome, Firefox, and Edge (WXT: MV3 for Chrome/Edge, MV2 for Firefox).
- Right-click context menu: send link, image, or page URL to CCC.
- Popup: backend URL config, login, quick submit; multi-user selector when applicable.

### Mobile App (Android)

- Share sheet integration and floating bubble overlay for quick URL queueing.
- Visual feedback (success/failure), job status viewer, optional background folder sync.
- In-app updater: check for updates from GitHub Releases, download and install APK.
