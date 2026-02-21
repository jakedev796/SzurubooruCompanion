# syntax=docker/dockerfile:1
# Use BuildKit for cache mounts: DOCKER_BUILDKIT=1 or default in Docker 23+

FROM python:3.11-slim

WORKDIR /app

# System deps (gallery-dl, yt-dlp are pip-installable).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Python deps: cache pip downloads across builds.
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu \
    && pip install -r requirements.txt \
    && pip install gallery-dl yt-dlp

# Application code
COPY app/ ./app/

# Data directories
RUN mkdir -p /data/jobs

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

EXPOSE 21425

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "21425", "--no-access-log"]
