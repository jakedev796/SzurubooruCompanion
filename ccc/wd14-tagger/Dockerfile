FROM python:3.11-slim

WORKDIR /app

# OpenCV runtime deps (libGL, libglib, etc.) missing from -slim.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-only PyTorch first to avoid pulling ~2 GB of CUDA libraries.
RUN pip install --no-cache-dir \
        torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Install numpy and pandas in a compatible pair BEFORE wd14-tagger-api,
# so it doesn't pull mismatched binary wheels.
RUN pip install --no-cache-dir "numpy<2" "pandas>=1.5,<2.1"

# Now install the tagger (deps already satisfied, won't override).
RUN pip install --no-cache-dir wd14-tagger-api

ENV PYTHONUNBUFFERED=1
ENV PORT=21435

EXPOSE 21435

CMD ["python", "-m", "wd14_tagger_api", "--port", "21435"]
