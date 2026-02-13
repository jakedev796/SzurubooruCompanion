FROM python:3.11-slim

WORKDIR /app

# System deps (gallery-dl, yt-dlp are pip-installable).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir gallery-dl yt-dlp

# Application code
COPY app/ ./app/

# Data directories
RUN mkdir -p /data/jobs

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

EXPOSE 21425

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "21425"]
