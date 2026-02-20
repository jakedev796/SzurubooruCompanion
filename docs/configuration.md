# Configuration Guide

Complete configuration reference for Szurubooru Companion.

## Initial Setup

1. **Generate encryption key:**
   ```bash
   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
   ```

2. **Configure environment variables** in `ccc/backend/.env`:
   ```env
   ADMIN_USER=admin
   ADMIN_PASSWORD=your-secure-password
   ENCRYPTION_KEY=<key-from-step-1>
   ```

3. **Start the stack:**
   ```bash
   docker compose up -d
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
- **WD14 Tagger:** Enable/disable, model selection, confidence threshold, max tags
- **Worker Settings:** Concurrency, timeouts, retry configuration
- Container restart required for WD14 changes to take effect

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

See [ccc/backend/.env.example](../ccc/backend/.env.example) for all available options.

## Site-Specific Configuration

Some sites require cookies or special handling. See [Supported Sites](sites.md) for:
- Confirmed working sites
- Cookie/authentication setup
- Special cases (Moeview, 4chan, etc.)
