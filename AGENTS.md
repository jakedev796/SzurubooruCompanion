## Cursor Cloud specific instructions

### Overview

Szurubooru Companion is a multi-component project: FastAPI backend, React/Vite frontend, browser extension (WXT), and a Flutter mobile app. For development, only the backend and frontend are relevant in this environment; the browser extension and mobile app are optional client-side components.

### Services

| Service | How to run | Port |
|---|---|---|
| PostgreSQL 16 | `sudo docker start ccc-postgres` (container pre-created) | 5432 |
| Redis 7 | `sudo docker start ccc-redis` (container pre-created) | 6379 |
| Backend (FastAPI) | See below | 21425 |
| Frontend (Vite) | `cd ccc/frontend && npm run dev` (or `npx vite --host 0.0.0.0 --port 21430`) | 21430 |

### Running the backend

The backend does **not** use python-dotenv. You must export environment variables from the `.env` file before running uvicorn:

```bash
cd ccc/backend
source .venv/bin/activate
set -a && source .env && set +a
export PYTHONPATH=/workspace/ccc/backend
uvicorn app.main:app --host 0.0.0.0 --port 21425 --reload --no-access-log
```

### Running the frontend

The Vite dev server proxies `/api` requests to `http://localhost:21425` (configured in `vite.config.js`). Use Node.js 20:

```bash
export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use 20
cd ccc/frontend
npm run dev
```

### Key gotchas

- **Python version**: The backend targets Python 3.11 (matching the Dockerfile). The venv is at `ccc/backend/.venv`.
- **Node version**: Frontend and browser extension require Node.js 20 (via nvm).
- **PyTorch CPU-only**: Install torch from the CPU index to avoid pulling GPU-specific packages: `pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu`
- **Docker daemon**: Must start the Docker daemon before Postgres/Redis containers: `sudo dockerd &>/dev/null &`
- **No lint/test tooling**: The project does not have eslint, pytest, or other lint/test configurations. Use `npm run build` (frontend) and `python -c "from app.main import app"` (backend) to verify code correctness.
- **Encryption key**: Required env var `ENCRYPTION_KEY` must be a valid Fernet key. Generate with: `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`
- **Onboarding wizard**: On first launch with an empty DB, the dashboard shows a setup wizard at `/onboarding`. Create an admin account through the UI or via `POST /api/setup/admin`.
- **gallery-dl and yt-dlp**: Must be pip-installed into the backend venv (not just in requirements.txt).
