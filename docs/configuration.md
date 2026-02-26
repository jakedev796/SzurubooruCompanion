# Configuration Guide

Complete configuration reference for Szurubooru Companion.

## Initial Setup

1. **Generate encryption key:**
   ```bash
   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
   ```

2. **Configure environment variables:**

   **Production** (single s6 image — `docker-compose.yml`):
   ```bash
   cp ccc/backend/.env.example ccc/backend/.env
   ```

   **Development** (separate services — `docker-compose.dev.yml`):
   ```bash
   cp ccc/backend/.env.dev.example ccc/backend/.env.dev
   ```

   Edit the copied file with your credentials:
   ```env
   ADMIN_USER=admin
   ADMIN_PASSWORD=your-secure-password
   ENCRYPTION_KEY=<key-from-step-1>
   ```

   The dev example includes `DATABASE_URL` and `REDIS_URL` with the correct container hostnames. The production image has these baked in and they can be omitted.

3. **Start the stack:**
   ```bash
   # Production
   docker compose up -d

   # Development
   docker compose -f docker-compose.dev.yml up -d
   ```

4. **Login to dashboard** at `http://localhost:21425` (or `http://localhost:21430` in dev compose) with your admin credentials

## Dashboard Configuration

After logging in, configure settings through the dashboard:

### **My Profile** (Settings → My Profile)
- Szurubooru URL, username, and API token
- Test connection to verify credentials
- Fetch and map tag categories from your Szurubooru instance

### **Site Credentials** (Settings → Site Credentials)
Configure authentication for sites that require login credentials (Twitter, Sankaku, Danbooru, Reddit, etc.). All credentials are encrypted in the database and never stored in plain text.

### **Global Settings** (Settings → Global Settings - Admin only)
- **WD14 Tagger:** Enable/disable, confidence threshold, max tags (live — no restart needed)
- **Download Timeouts:** gallery-dl and yt-dlp subprocess timeouts
- **Worker Settings:** Max retries, retry delay, video tagging configuration

> **What requires a restart vs. what is live:**
> ENV variables that require a restart: `WD14_MODEL` (model singleton), `WD14_NUM_WORKERS` (thread pool), `WD14_USE_PROCESS_POOL` (executor type), `WORKER_CONCURRENCY` (worker count).
> Everything else (WD14 enable/disable, confidence threshold, max tags, timeouts, retries) is a live dashboard setting — changes take effect on the next job without restarting.

> **Process pool and worker concurrency:** `WD14_USE_PROCESS_POOL` (ENV) controls whether inference runs in a dedicated subprocess. This is only beneficial when `WORKER_CONCURRENCY=1`, as the subprocess handles one job at a time and all other workers queue behind it. With multiple workers, leave `WD14_USE_PROCESS_POOL=false` (the default) so workers share the thread pool and run inference concurrently.

### **User Management** (Settings → Users - Admin only)
- Create new users with username, password, and role (admin/user)
- Edit users: Reset password, promote/demote admin, activate/deactivate
- Each user configures their own Szurubooru and site credentials

### **Category Mappings** (Settings → My Profile)
Map internal tag categories to your Szurubooru instance's custom categories:
- **general** → Default category for general tags
- **artist** → Artist/creator tags
- **character** → Character name tags
- **copyright** → Series/franchise tags
- **meta** → Meta information tags

Fetch categories directly from Szurubooru using "Fetch Tag Categories" button.

## Environment Variables Reference

- **Production:** [ccc/backend/.env.example](../ccc/backend/.env.example)
- **Development:** [ccc/backend/.env.dev.example](../ccc/backend/.env.dev.example)

## Site-Specific Configuration

Some sites require cookies or special handling. See [Supported Sites](sites.md) for:
- Confirmed working sites
- Cookie/authentication setup
- Special cases (Moeview, 4chan, etc.)
