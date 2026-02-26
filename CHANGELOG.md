# Changelog

All notable changes to Szurubooru Companion (CCC, browser extension, mobile app) are documented here. Unreleased notes go under [Unreleased] by component.

## [Unreleased]

### CCC - Frontend

### CCC - Backend

### Mobile App

### Browser Extension

## [1.2.1] - 2026-02-26

### Mobile App
- Validate and refresh credentials before folder sync, SSE, and share uploads; show a single "Login expired" notification instead of per-job or per-file errors
- Add ensureValidToken() and showCredentialsExpired() for consistent session handling; floating bubble and all services refresh token before work
- Proactive ensureValidToken before URL enqueue in UI; 401 shown as "Session expired. Please log in again."; file upload retries once on 401 after refresh; backend error detail (e.g. FastAPI detail) shown when API returns 4xx/5xx
- Floating bubble / SSE background service: periodic token revalidation every 12h, refresh and reconnect SSE so connection stays valid without opening the app; reconnect path sets _isRunning = false when credentials invalid to avoid reconnect spam


## [1.2.0] - 2026-02-24

### CCC - Frontend
- Jobs page: when a status filter is set, SSE updates that change a job's status remove it from the list if it no longer matches the filter; exclude tag_existing jobs from the main list when merging SSE updates (add/update/refetch)
- Dashboard activity and merged reports: exclude tag_existing jobs when merging SSE updates so the activity log and jobs list stay limited to URL/file jobs
- Tagger page: tag search with debounce (search Szurubooru tags, show post count); selected-tags list with remove (X); AND/OR match (all tags vs any tag)
- Jobs API and types: job_type filter, target_szuru_post_id and replace_original_tags for tag jobs; discoverTagJobs and abortAllTagJobs
- Standardize source column truncation: filenames now use the same 30-char limit with ellipsis as URLs
- Fix layout shifts in job tables: fixed column widths prevent reflow when status/actions change
- Merge details link into actions column as info icon button
- Use relative timestamps in job tables (e.g. "3m ago") with full date on hover
- Extract shared formatters (formatRelativeDate, formatDurationSeconds) to utils/format.ts

### CCC - Backend
- Worker: on startup, reset jobs stuck in downloading/tagging/uploading (e.g. after reboot) to pending so they are picked up again
- Tag-existing jobs: POST /api/tag-jobs/discover accepts tags[] and tag_operator (and/or); GET /api/tag-jobs/tag-search for tag autocomplete with usage count; discover scopes to current user's posts
- Szurubooru: search_posts, download_post_content (via contentUrl); worker downloads post content, runs WD14, updates post tags/safety (replace or merge)
- GET /api/jobs: exclude tag_existing jobs by default (dashboard/Jobs page); optional job_type filter to include them
- GET /api/stats: exclude tag_existing jobs from totals, status counts, 24h count, and daily uploads (dashboard and mobile)
- Fix jobtype enum: ensure TAG_EXISTING (name) is added for SQLAlchemy compatibility

### Mobile App
- Exclude tag_existing jobs from main job list when applying SSE updates (do not add on fetch; remove if refetch reveals tag job)


## [1.1.2] - 2026-02-22

### CCC - Frontend
- Dashboard summary cards: total jobs, average job time, jobs (24h)
- Job list and dashboard: Time column (duration); sortable list (created, completed, duration) with server-side pagination
- Refetch stats on completed/merged SSE so avg job time and time column update in real time

### CCC - Backend
- Migrations: use .sql files in app/migrations/sql/ with $$-aware statement splitting (no more inline SQL in __init__.py)
- Add average_job_duration_seconds and jobs_last_24h to GET /api/stats
- Fix average job time to use processing time only (started_at to updated_at); add started_at to jobs, set when worker claims job
- Add completed_at to jobs; backfill existing completed/merged jobs; average duration uses completed_at - started_at
- GET /api/jobs: sort param (created_at, completed_at, duration asc/desc), return completed_at and duration_seconds in list
- SSE job updates include completed_at and duration_seconds for real-time time display
- Fix paused/stopped jobs incorrectly entering the failure/retry workflow instead of staying in their paused/stopped state
- Reset started_at on job resume so duration reflects the resumed run, not time spent paused

### Mobile App
- Dashboard stats from API: total jobs, average job time, jobs (24h); reuse stats endpoint
- Job model and cards: completed_at, duration_seconds; show duration on job card when available
- JobUpdate from SSE includes completedAt/durationSeconds; job list time updates in real time


## [1.1.1] - 2026-02-22

### CCC - Frontend
- Add video confidence threshold setting to Global Settings page

### CCC - Backend
- Fix AI safety rating not persisting to the Job record after tagging (folder sync default was shown instead of AI result)
- Add separate video confidence threshold setting (default 0.45, higher than image threshold) for stricter per-frame tag filtering

### Mobile App
- Split overview stat cards into two rows (stages / outcomes) to prevent crowding
- Show full folder path in folder config screen instead of just "Tap to change folder"


## [1.1.0] - 2026-02-22

### CCC - Frontend
- Dashboard chart now shows completed, merged, and failed jobs as overlaid areas with distinct colors (green, purple, red)
- Fix daily chart status breakdown (failed/merged counts were always zero due to enum CASE mismatch)

### CCC - Backend
- Stats endpoint returns per-day completed and merged counts alongside failed for the daily uploads chart

### Mobile App
- Add app icon to app lock screen
- Fix vibration on update download progress by using a dedicated silent notification channel
- Show changelog dialog after an app update completes
- Skip previously synced files in folder sync when media deletion is off (filter by modification time)
- Add merged stat card to main screen to match the frontend dashboard


## [1.0.11]

### Mobile Feature: App lock

### Mobile App
- Fix app lock authentication: use FlutterFragmentActivity so system PIN/biometric prompt is shown; log auth failure codes for diagnosis
- Fix app lock loop: only require re-auth when app goes to background (resumed→paused), not when system auth dialog dismisses (avoids re-lock on every resumed)
- App lock is Android-only: gate and settings card hidden on Darwin/Windows; local_auth not used on non-Android
- Optional app lock (device PIN/pattern/password or fingerprint) for Android; off by default, configurable in Settings
- SSE reconnection uses exponential backoff (3s, 6s, 12s, … cap 60s) and single-schedule debounce to avoid hammering the server
- Persistent notification reflects connection status when app is closed: native foreground service updates notification when its SSE loop connects or disconnects
- Persistent notification now reflects connection status when app is in background (SseBackgroundService updates notification on connect/disconnect)
- Reconnect SSE when connection dies: SseBackgroundService listens for disconnect and reconnects; connection status card and app bar icon trigger reconnect when tapped; share flow reconnects if disconnected when bubble is used
- Add note to overlay permission dialog about unlocking restricted settings on sideloaded installs

## [1.0.10] - 2026-02-21

### CCC - Frontend
- Remove worker_concurrency and wd14_model from Global Settings UI; both are ENV-only and require a restart

### CCC - Backend
- Cache user config in Redis (5-minute TTL) to avoid a DB round-trip on every job; invalidate on credential update
- Install CPU-only PyTorch wheel in Dockerfiles via the PyTorch CPU index URL
- Add WD14_USE_PROCESS_POOL and WD14_NUM_WORKERS env settings; process pool now defaults to off (thread pool is correct for multi-worker setups)
- Wire up dead GlobalConfig settings: wd14_enabled, wd14_confidence_threshold, wd14_max_tags, gallery_dl_timeout, and ytdlp_timeout now actually apply per-job; dashboard changes take effect immediately without restart
- Move worker_concurrency from GlobalConfig (dashboard) to ENV (WORKER_CONCURRENCY); it requires a restart anyway so dashboard control added no value
- Remove wd14_enabled, wd14_confidence_threshold, wd14_max_tags from ENV; these are now live settings managed exclusively via Settings > Global Settings

## [1.0.9] - 2026-02-21

### CCC - Frontend

### CCC - Backend
- Reject job URLs for x.com/home, twitter.com/home and bare-domain URLs (e.g. gelbooru.com, misskey.art) with 400 and clear message
- Fix Gelbooru (and other sites with hotlink protection) returning HTML instead of images on direct download; validates Content-Type and falls back to gallery-dl
- Reject Reddit base or subreddit-only URLs (e.g. reddit.com, reddit.com/r/DIY); only post URLs containing /comments/ are allowed
- Reddit (and other sites): ensure downloaded filename has extension (from gallery-dl URL or Content-Type) so upload to Szurubooru does not fail with missing type

### Mobile App
- Job detail sheet: use sheet jobId for all actions (Start/Pause/Stop/Resume/Retry) so the correct job is targeted
- Update download notification: use stable tag + onlyAlertOnce so progress updates replace the same notification instead of creating new ones
- Persistent notification: add expandable action to toggle floating button (show "Disable Floating Button" when on, "Enable Floating Button" when off); settings reload on app resume so UI reflects notification toggle

### Browser Extension
- Fix Gelbooru extractor querySelector crash (remove invalid :contains selector)
- On Gelbooru list page, floating button submits post URL so backend fetches full-size image via gallery-dl
- Reject job URLs for x.com/home, twitter.com/home and bare-domain URLs before submit; same validation in content and context menu
- Remove "Send page URL to Szurubooru" context menu; only media (floating button, right-click image/video) and "Send link" allowed
- Danbooru and yande.re list pages: floating button on thumbnail submits post URL for full-size image (same as Gelbooru)
- Twitter/X: floating button extracts only the relevant tweet permalink and its media; for retweets, use original tweet URL and media
- Gelbooru, Danbooru, yande.re, Rule34: on list pages only submit the hovered thumbnail's single post URL; return null otherwise (no fall-through to page-level URL)
- Rule34: add list-page handling (submit post URL for thumbnails like Gelbooru)
- Never send thumbnail/sample media URLs: if detected, use post/source URL so backend resolves full media
- Floating button: resolve hover to actual img/video (works on wrappers e.g. Twitter video); use extractor isGrabbable; allow video without src (lazy load); reject feed URL as source
- Reddit: floating button on reddit.com; submit only post permalink (parent URL); reject subreddit-only URLs (e.g. r/DIY) in validation


## [1.0.8] - 2026-02-20

### CCC - Frontend
- Add Video Tagging settings section to Global Settings (toggle, scene threshold, max frames, min frame ratio)

### CCC - Backend
- Add video frame tagging: extract key frames via FFmpeg scene detection and tag with WD14


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
