# SzurubooruCompanion

A companion tool for Szurubooru image boards. Monorepo with four components: CCC backend (FastAPI), CCC frontend (React/Vite), browser extension (WXT), and mobile app (Flutter).

## Project Structure

```
ccc/backend/       # Python FastAPI API + background worker
ccc/frontend/      # React 19 + TypeScript + Vite dashboard
browser-ext/       # WXT browser extension (Chrome MV3, Firefox MV2)
mobile-app/        # Flutter Android app
docs/              # Documentation
s6-rc.d/           # s6-overlay service definitions
```

## Build & Run

### Docker (preferred)

```bash
docker compose up -d                              # Production (single s6 image)
docker compose -f docker-compose.dev.yml up -d    # Development (separate services)
```

### Manual

```bash
# Backend
cd ccc/backend && pip install -r requirements.txt
uvicorn app.main:app --reload

# Frontend
cd ccc/frontend && npm install && npm run dev

# Browser extension
cd browser-ext && npm install && npm run dev          # Chrome
cd browser-ext && npm install && npm run dev:firefox   # Firefox

# Mobile
cd mobile-app && flutter pub get && flutter run
```

## Tech Stack

- **Backend**: Python 3.11, FastAPI, SQLAlchemy 2.0 (async), PostgreSQL, Redis, gallery-dl, yt-dlp, WD14 tagger
- **Frontend**: React 19, TypeScript 5.7, Vite 6.1, React Router 7
- **Extension**: WXT 0.19, TypeScript, webextension-polyfill
- **Mobile**: Flutter/Dart, Provider state management
- **Infra**: Docker, s6-overlay, Nginx (optional reverse proxy)

## Ports

- Backend API: 21425
- Frontend dev: 21430
- PostgreSQL: 5432
- Redis: 6379

## Code Guidelines

- Always follow separation of concerns (SoC) best practices.
- Blend into the existing code — follow the patterns, naming, and style already established in each component.
- Follow the established architecture unless it is flawed, in which case suggest improvements before changing.
- Keep comments high-level. Do not over-comment; the code should be mostly self-documenting. Only add comments where the logic isn't self-evident.
- Do not use emojis in the codebase. Use terminal coloring (ANSI codes, logging levels) to make things stand out where needed (exceptions, errors, etc). Exception: emojis are fine in documentation for illustrating UI designs.
- All timestamps stored in the database must be UTC. Convert to the user's timezone on the frontend at display time. Never store local time in the database.
- Never add yourself as a co-auth on repos.

## Code Conventions

- **Commits**: Conventional commits (`type: description`) — types: `fix:`, `feat:`, `chore:`, `docs:`
- **Python**: Type hints, async/await, Pydantic models, 4-space indent
- **TypeScript/React**: Strict mode, functional components with hooks, camelCase variables, PascalCase components
- **Dart**: Flutter lint rules, Provider pattern, snake_case variables, PascalCase classes

## Architecture Notes

- Backend uses modular routers in `ccc/backend/app/api/`
- Services layer in `ccc/backend/app/services/` (auth, downloader, tagger, encryption, szurubooru)
- Redis-backed job queue with background worker in `ccc/backend/app/workers/`
- JWT authentication; per-user encrypted credential storage (Fernet)
- WD14 tagger runs in-process (no separate container)
- Single VERSION file at root (`<versionName>+<versionCode>`) used by all components

## CI/CD

- **dev.yml**: Builds Docker image on push to main / PRs, pushes to GHCR with `dev` tag
- **release.yml**: Triggered by `v*` tags, supports scoped releases (`-ccc`, `-ext`, `-mobile`), creates GitHub Release with changelog

## Adding a New Gallery-DL Extractor

Sites use a **registry + overrides** pattern:

1. **Registry** (`ccc/backend/app/sites/site_registry.py`): Add auth site to `AUTH_SITES` or no-auth site to `NO_AUTH_SITES` (in `no_auth_list.py`) + `NO_AUTH_TAG_OPTIONS` if gallery-dl supports tags.
2. **Override** (only if needed): Create `ccc/backend/app/sites/overrides/<sitename>.py` for custom logic (normalize_url, gallery_dl_options, build_search_url, parse_browse_item, etc.) and register in `overrides/__init__.py`.
3. **Browser extension** (optional, for DOM extraction): Add `SiteExtractor` in `browser-ext/entrypoints/content/sites/<sitename>.ts`, register in `index.ts` and `wxt.config.ts`.

The backend injects credentials via `-o` flags from the database at runtime. No config file is used.

## Changelog

When making updates, append entries to `CHANGELOG.md` under `[Unreleased]`, sectioned by component:

- **CCC - Frontend**
- **CCC - Backend**
- **Mobile App**
- **Browser Extension**

One short line per change. Only add under the component you changed. Use `##` only for version headers (e.g. `## [1.0.5] - 2026-02-19`) — this is how the release workflow parses version boundaries.
