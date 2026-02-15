# Pull Request: Major Integration - Flutter App, Backend Enhancements, Browser Extension

## Summary

This PR represents a major integration effort across the entire Szurubooru Companion codebase, adding a complete Flutter mobile application, significant backend enhancements, and an improved browser extension with content script support.

## New Features

### Backend (ccc/backend/)

- **Two-Phase Media Extraction**: Enhanced downloader.py with better error handling and retry logic
- **Duplicate Handling**: Merge logic in processor.py that handles duplicate posts intelligently
- **Multi-File Post Support**: Posts with multiple files now create relations via `related_post_ids`
- **Job Control API**: Full CRUD operations for jobs (start/pause/stop/delete/resume)
- **Tags Support**: File upload endpoint now accepts tags parameter
- **SSE Events**: Real-time job updates via Server-Sent Events endpoint (`/api/events`)
- **Stats Endpoint**: Hardened against enum errors with proper validation
- **Database Migration**: Added `related_post_ids` column and `PAUSED`/`STOPPED` status enum values
- **gallery-dl Integration**: Config.json with environment variable support for credentials
- **Twitter Cookie Support**: Authenticated Twitter downloads via cookie file
- **Misskey Configurations**: Pre-configured Misskey instance support

### Frontend (ccc/frontend/)

- **SSE Integration**: `useJobUpdates` hook for real-time job status updates
- **Clickable Post Hyperlinks**: Direct links to Szurubooru posts
- **Multi-Source URL Display**: Shows all source URLs for each job
- **Job Control UI**: Buttons for pause/resume, stop, and delete operations
- **Related Posts Display**: Shows related posts with clickable links

### Flutter App (flutter_app/)

- **Complete Android Application**: Full Flutter app for mobile usage
- **Backend Client**: Aligned with all new API endpoints
- **Job Model**: Complete model with all fields including `related_post_ids`
- **SAF URI Handling**: Storage Access Framework file handling with `saf_stream` package
- **Background Tasks**: Workmanager integration with single `callbackDispatcher` definition
- **Notification Service**: Extracted modular notification handling
- **Folder Scanner**: Batch upload from selected folders
- **Scheduled Folder Upload**: Periodic background scanning and uploading
- **Share Receiver**: Direct share-to-app functionality from other apps

### Browser Extension (browser-ext/)

- **Floating Button Overlay**: Media detection with floating action button on supported sites
- **DOM Extraction**: Misskey and Twitter content extraction from page DOM
- **Site-Specific Extractors**: 
  - Danbooru
  - Gelbooru
  - Yande.re
  - Misskey
  - Twitter
- **Content Script Architecture**: Modular site support with easy extensibility

### Docker

- **gallery-dl Config Mount**: Volume mount for configuration
- **Twitter Cookies Support**: Cookie file volume mount option

## Bug Fixes

- Fixed stats endpoint enum validation errors
- Fixed browser extension TypeScript build errors
- Fixed Flutter workmanager callback dispatcher conflicts
- Fixed duplicate post handling in processor

## Files Modified

### Modified Files (22)
- `.gitignore` - Added Flutter and build artifact exclusions
- `README.md` - Updated documentation
- `browser-ext/entrypoints/background.ts` - Enhanced background script
- `browser-ext/package.json` - Updated dependencies
- `browser-ext/tsconfig.json` - TypeScript configuration fixes
- `browser-ext/utils/api.ts` - API improvements
- `browser-ext/wxt.config.ts` - WXT configuration updates
- `ccc/backend/.env.example` - Added new environment variables
- `ccc/backend/app/api/jobs.py` - Job control endpoints
- `ccc/backend/app/api/stats.py` - Stats endpoint hardening
- `ccc/backend/app/database.py` - Schema updates for relations and status
- `ccc/backend/app/main.py` - New route registrations
- `ccc/backend/app/migrations/__init__.py` - Database migrations
- `ccc/backend/app/services/downloader.py` - Two-phase extraction
- `ccc/backend/app/services/szurubooru.py` - Multi-file post support
- `ccc/backend/app/workers/processor.py` - Duplicate handling and relations
- `ccc/backend/requirements.txt` - New dependencies
- `ccc/frontend/src/api.js` - API client updates
- `ccc/frontend/src/index.css` - UI styling
- `ccc/frontend/src/pages/JobDetail.jsx` - Job control UI
- `ccc/frontend/src/pages/JobList.jsx` - Job list enhancements
- `docker-compose.yml` - Volume mounts and configuration

### New Files (87)
- `config.json` - gallery-dl configuration
- `browser-ext/bun.lock` - Package lock file
- `browser-ext/entrypoints/content/` - Content scripts directory
- `browser-ext/utils/extractors/` - Extractor utilities
- `browser-ext/utils/types.ts` - TypeScript type definitions
- `browser-ext/wxt.d.ts` - WXT type declarations
- `ccc/backend/app/api/config.py` - Config endpoint
- `ccc/backend/app/api/events.py` - SSE events endpoint
- `ccc/frontend/src/hooks/useJobUpdates.js` - SSE hook
- `flutter_app/` - Complete Flutter application (60+ files)

## Testing Instructions

### Backend Testing

1. Start the backend services:
   ```bash
   cd ccc/backend
   cp .env.example .env
   # Edit .env with your configuration
   docker-compose up -d
   ```

2. Test the new endpoints:
   - `GET /api/events` - SSE stream for job updates
   - `POST /api/jobs/{id}/pause` - Pause a job
   - `POST /api/jobs/{id}/resume` - Resume a job
   - `POST /api/jobs/{id}/stop` - Stop a job
   - `DELETE /api/jobs/{id}` - Delete a job

### Frontend Testing

1. Start the frontend:
   ```bash
   cd ccc/frontend
   npm install
   npm run dev
   ```

2. Verify:
   - Real-time job updates appear without refresh
   - Job control buttons work (pause, resume, stop, delete)
   - Related posts display correctly
   - Source URLs are clickable

### Flutter App Testing

1. Build and run:
   ```bash
   cd flutter_app
   flutter pub get
   flutter run
   ```

2. Verify:
   - App connects to backend
   - Jobs display correctly
   - Share-to-app works from gallery/browser
   - Folder picker and scanner work
   - Background uploads function

### Browser Extension Testing

1. Build the extension:
   ```bash
   cd browser-ext
   bun install
   bun run build
   ```

2. Load in browser (Chrome/Firefox):
   - Navigate to extensions page
   - Load unpacked from `.output/chrome-mv3/`

3. Test on supported sites:
   - Danbooru, Gelbooru, Yande.re
   - Twitter/X
   - Misskey instances

## Breaking Changes

### Database Migration Required

The database schema has changed. Run migrations before deploying:

```python
# The migration runs automatically on startup, but for manual migration:
from app.migrations import run_migrations
run_migrations()
```

New columns:
- `jobs.related_post_ids` (JSON list of related post IDs)

New enum values:
- `JobStatus.PAUSED`
- `JobStatus.STOPPED`

### Environment Variables

New environment variables in `.env`:
- `TWITTER_USERNAME` / `TWITTER_PASSWORD` - Twitter authentication
- `MISSKEY_USERNAME` / `MISSKEY_PASSWORD` - Misskey authentication
- `SANKAKU_USERNAME` / `SANKAKU_PASSWORD` - Sankaku authentication
- `DANBOORU_API_KEY` / `DANBOORU_USER_ID` - Danbooru API
- `GELBOORU_API_KEY` / `GELBOORU_USER_ID` - Gelbooru API
- `REDDIT_CLIENT_ID` / `REDDIT_CLIENT_SECRET` / `REDDIT_USERNAME` - Reddit API

### Docker Volume Mounts

New optional volume mounts:
- `./config.json:/app/config/config.json` - gallery-dl configuration
- `./local-dev/twitter-cookies.txt:/app/config/twitter-cookies.txt` - Twitter cookies

## Migration Steps

1. **Pull and build**:
   ```bash
   git checkout feature/flutter-backend-integration
   docker-compose build
   ```

2. **Update environment**:
   ```bash
   cp ccc/backend/.env.example ccc/backend/.env
   # Edit .env with your credentials
   ```

3. **Optional: Setup gallery-dl config**:
   ```bash
   # Copy config.json to project root
   # Export Twitter cookies to local-dev/twitter-cookies.txt if needed
   ```

4. **Start services**:
   ```bash
   docker-compose up -d
   ```

5. **Verify migration**:
   - Check logs for migration success
   - Test API endpoints
   - Test frontend UI

## Notes for Reviewers

- The Flutter app is Android-only currently (iOS support planned)
- The workmanager_patch directory contains a patched version of the workmanager package for background task support
- The `old-extension/` and `plans/` directories are intentionally excluded from this PR
- All sensitive credentials use environment variables - no secrets in code

## Commit Details

- **Branch**: `feature/flutter-backend-integration`
- **Commit**: `20a0b74`
- **Files Changed**: 109 files
- **Insertions**: 14,470+
- **Deletions**: 158
