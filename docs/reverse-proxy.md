# Dashboard behind a reverse proxy

The dashboard (frontend) uses relative `/api` URLs. If you expose the app via a single host (e.g. `https://ccc.example.com`), you **must** route `/api` to the backend and `/` to the frontend; otherwise the dashboard will get HTML instead of JSON and show: "API returned HTML instead of JSON".

## Nginx Proxy Manager

Add a proxy host for your domain, then add two **Custom locations**:

- Path: `/api` -> Forward to: `ccc-backend:21425` (or `http://host-ip:21425` if NPM is not in Docker).
- Path: `/` (or leave default) -> Forward to: `ccc-frontend:21430`.

## Separate API URL

Alternatively, build the frontend with the API on a separate URL: set `VITE_API_BASE=https://api.ccc.example.com` (or `http://host:21425` for same-machine access) when running `npm run build` in `ccc/frontend`, then the dashboard will call that URL instead of relative `/api`.
