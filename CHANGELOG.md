# Changelog

All notable changes to Szurubooru Companion (CCC, browser extension, mobile app) are documented here. Unreleased notes go under [Unreleased] by component.

## [Unreleased]

### CCC - Frontend

### CCC - Backend

### Mobile App

### Browser Extension


## [1.0.7] - 2026-02-19

### Mobile App
- Add sort selector (Newest/Top/Random) to Discover filter sheet
- Sort option saved with presets
- Yandere random sort greyed out when only Yandere selected; warning shown in multi-site mode
- Filter sheet preserves unsaved changes on dismiss (no longer resets to preset values)
- Show loading spinner when swiped through current batch while next page loads
- Differentiate "No results found" vs "No more results" messaging
- Re-added full post search to initial load


## [1.0.6] - 2026-02-19

### Major App Feature: Discover

### CCC - Backend
- Add Discover feature: browse booru sites (Danbooru, Gelbooru, Sankaku, Rule34, Yandere) with tag/rating filters via gallery-dl
- Add image proxy endpoint with SSRF-safe domain allowlist for booru thumbnails/previews
- Track seen items per user to prevent re-showing swiped content
- Support filter presets (save/load/delete/update) for quick access to frequent searches
- Swipe-right creates a job automatically (download, tag, upload pipeline)
- Redis caching for browse results (5-minute TTL)
- Add endpoint to toggle default preset per user

### Mobile App
- Add Discover tab: Tinder-style card swiping UI for browsing booru content
- Swipe right to like (creates upload job), swipe left to skip
- Filter sheet with multi-site selection, tag search, exclude tags, rating filter, and saved presets
- Card stack with drag gestures, rotation, and LIKE/SKIP indicators
- Automatic prefetch when running low on cards
- Comma-separated tag input with automatic underscore normalization for booru compatibility
- Default preset support: star a preset to auto-load it on startup
- Clickable post IDs link to source booru page


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
