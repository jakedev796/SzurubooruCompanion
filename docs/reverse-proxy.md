# Reverse Proxy Setup

The CCC dashboard (frontend) uses relative `/api` URLs to communicate with the backend. When exposing the app via a single domain, you must configure your reverse proxy to route `/api` requests to the backend and `/` requests to the frontend.

> **Note for Unraid Users:** If you're using the Unraid template with s6 overlay configuration, `/api` routing is handled automatically. This guide is only necessary for standard Docker Compose deployments. Simply point your reverse proxy at the backend `http://<your-ip>:port` and it will work!

---

## Why Reverse Proxy Routing Matters

**Problem:** If `/api` is not routed to the backend, the dashboard will receive HTML instead of JSON and display:
```
API returned HTML instead of JSON
```

**Solution:** Configure your reverse proxy to split traffic:
- `/api/*` → CCC Backend (port 21425)
- `/*` → CCC Frontend (port 21430)

---

## Nginx Proxy Manager

Recommended for Docker-based setups with graphical configuration.

### Setup

1. **Add a Proxy Host** for your domain (e.g., `ccc.example.com`)
2. **Add Custom Locations:**

   **Location 1 - API Backend:**
   - **Path:** `/api`
   - **Forward Hostname/IP:**
     - Docker: `ccc-backend` (container name)
     - Non-Docker: `localhost` or host IP
   - **Forward Port:** `21425`
   - **Scheme:** `http`

   **Location 2 - Frontend:**
   - **Path:** `/` (or leave as default)
   - **Forward Hostname/IP:**
     - Docker: `ccc-frontend` (container name)
     - Non-Docker: `localhost` or host IP
   - **Forward Port:** `21430`
   - **Scheme:** `http`

3. **Save and test** by accessing your domain

### SSL/TLS

Configure SSL in Nginx Proxy Manager:
- Use Let's Encrypt for automatic certificates
- Or upload your own certificate files
- Enable "Force SSL" to redirect HTTP → HTTPS

---

## Native Nginx

For manual Nginx configuration:

```nginx
server {
    listen 80;
    server_name ccc.example.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ccc.example.com;

    ssl_certificate /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    # API Backend
    location /api {
        proxy_pass http://localhost:21425;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Frontend
    location / {
        proxy_pass http://localhost:21430;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Restart Nginx after configuration:
```bash
sudo nginx -t          # Test configuration
sudo systemctl reload nginx
```

---

## Caddy

Caddy provides automatic HTTPS and simpler configuration:

```caddy
ccc.example.com {
    # API Backend
    handle /api* {
        reverse_proxy localhost:21425
    }

    # Frontend (catch-all)
    handle {
        reverse_proxy localhost:21430
    }
}
```

Caddy automatically provisions Let's Encrypt certificates.

---

## Apache

For Apache with mod_proxy:

```apache
<VirtualHost *:80>
    ServerName ccc.example.com
    Redirect permanent / https://ccc.example.com/
</VirtualHost>

<VirtualHost *:443>
    ServerName ccc.example.com

    SSLEngine on
    SSLCertificateFile /path/to/fullchain.pem
    SSLCertificateKeyFile /path/to/privkey.pem

    # API Backend
    ProxyPass /api http://localhost:21425/api
    ProxyPassReverse /api http://localhost:21425/api

    # Frontend
    ProxyPass / http://localhost:21430/
    ProxyPassReverse / http://localhost:21430/

    # Preserve headers
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
</VirtualHost>
```

Enable required modules:
```bash
sudo a2enmod proxy proxy_http ssl headers
sudo systemctl restart apache2
```

---

## Alternative: Separate API URL

If you prefer to host the API on a separate domain/subdomain, build the frontend with a custom API URL:

**Build frontend with custom API endpoint:**

```bash
cd ccc/frontend
export VITE_API_BASE=https://api.ccc.example.com  # Or http://localhost:21425
npm run build
```

This embeds the API URL into the frontend build, eliminating the need for `/api` routing in your reverse proxy. The frontend will call the specified URL directly.

**Pros:**
- Simpler reverse proxy configuration
- Can host backend and frontend on different domains

**Cons:**
- Requires rebuilding frontend if API URL changes
- CORS configuration may be needed if domains differ

---

## Docker Networking

When running CCC via Docker Compose, use container names for internal routing:

**In Nginx Proxy Manager or reverse proxy running in Docker:**
- Backend: `ccc-backend:21425`
- Frontend: `ccc-frontend:21430`

**In Nginx Proxy Manager or reverse proxy running on host:**
- Backend: `localhost:21425` or host IP
- Frontend: `localhost:21430` or host IP

Ensure your reverse proxy container is on the same Docker network as CCC if using container names.

---

## Troubleshooting

**"API returned HTML instead of JSON":**
- `/api` is not routing to the backend
- Verify the API location is configured before the frontend catch-all
- Check reverse proxy logs for routing issues

**Connection refused or timeout:**
- Verify CCC services are running: `docker compose ps`
- Check firewall rules
- Ensure ports 21425 and 21430 are accessible from the reverse proxy

**CORS errors in browser console:**
- Ensure `proxy_set_header Host $host` is set in Nginx
- Check that `X-Forwarded-Proto` header is passed correctly
- Verify SSL is terminating at the reverse proxy, not the backend

**SSL certificate errors:**
- Let's Encrypt: Ensure port 80 is accessible for HTTP-01 challenge
- Manual certs: Check certificate paths and permissions
- Verify certificate includes full chain
