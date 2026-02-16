# syntax=docker/dockerfile:1
# Single fat container: PostgreSQL + Redis + Backend + Frontend via s6-overlay.
# Build:  docker build -t szurubooru-companion .
# Run:    docker run -d -p 21425:21425 -v data:/data -v config:/config \
#           -e SZURU_URL=... -e SZURU_USERNAME=... -e SZURU_TOKEN=... \
#           szurubooru-companion

# ── Stage 1: Build frontend ──────────────────────────────────────────
FROM node:20-alpine AS frontend-build
WORKDIR /build
COPY ccc/frontend/package.json ccc/frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY ccc/frontend/ .
# Empty VITE_API_BASE → getBase() returns "/api" (same-origin)
ENV VITE_API_BASE=""
RUN npm run build

# ── Stage 2: Final image ─────────────────────────────────────────────
FROM python:3.11-slim

ARG S6_OVERLAY_VERSION=3.2.0.2

# System packages: PostgreSQL, Redis, ffmpeg, xz (needed to extract s6-overlay)
RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql \
        postgresql-client \
        redis-server \
        ffmpeg \
        xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/lib/postgresql/*/bin/* /usr/local/bin/

# s6-overlay (must come after xz-utils install)
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp/
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp/
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
 && tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz \
 && rm /tmp/s6-overlay-*.tar.xz

# Python deps
WORKDIR /app
COPY ccc/backend/requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu \
 && pip install -r requirements.txt \
 && pip install gallery-dl yt-dlp

# Application code
COPY ccc/backend/app/ ./app/

# Frontend static files
COPY --from=frontend-build /build/dist /app/frontend

# Default gallery-dl config (copied to /config on first run if missing)
COPY config.json /defaults/config.json

# Data directories
RUN mkdir -p /data/jobs /data/postgres /data/wd14-models /config /run/postgresql \
 && chown -R postgres:postgres /data/postgres /run/postgresql

# s6-overlay service definitions
COPY s6-rc.d/ /etc/s6-overlay/s6-rc.d/

# Environment defaults for embedded services
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    DATABASE_URL=postgresql+asyncpg://ccc:ccc@localhost:5432/ccc \
    REDIS_URL=redis://localhost:6379/0 \
    STATIC_FILES_DIR=/app/frontend \
    JOB_DATA_DIR=/data/jobs \
    HF_HOME=/data/wd14-models \
    GALLERY_DL_CONFIG_FILE=/config/config.json

EXPOSE 21425

VOLUME ["/data", "/config"]

ENTRYPOINT ["/init"]
