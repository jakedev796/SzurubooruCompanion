# Supported Sites

CCC supports any site that [gallery-dl](https://github.com/mikf/gallery-dl) or [yt-dlp](https://github.com/yt-dlp/yt-dlp) can extract media from. The list below contains explicitly tested sites.

**Legend:**
- `*` = Requires extra configuration (see [Sites Requiring Configuration](#sites-requiring-configuration))
- `**` = No tag extraction available (see [Sites with Limited Metadata](#sites-with-limited-metadata))

---

## Confirmed Working Sites

| Site | Notes |
|------|-------|
| Sankaku | Requires login credentials `*` |
| Yande.re | |
| X / Twitter | Requires cookies `*` `**` |
| Danbooru | Optional API key for rate limits |
| Gelbooru | Optional API key for rate limits |
| Rule34.xxx | Optional API key for rate limits |
| Rule34Vault | |
| Misskey | Optional credentials for private posts |
| Reddit | Optional credentials for private content |
| Moeview | Use source link, not viewer page `*` |
| 4chan | Use direct media link, not thread `**` |
| Pixiv | Requires cookies `*` |

---

## Sites Requiring Configuration

Some sites require authentication or cookies to download media. Configure these through **CCC Dashboard → Settings → Site Credentials** (all credentials are encrypted).

| Site | Domains | Credentials Needed | Example |
|------|---------|-------------------|---------|
| Sankaku | `sankaku.app`, `chan.sankakucomplex.com` | Username, Password | Required for all downloads |
| Twitter/X | `twitter.com`, `x.com` | Username, Password, Cookies | `auth_token=abc123...` |
| Pixiv | `pixiv.net` | Cookies | Netscape format cookies |

**How to configure:**
1. Login to CCC Dashboard at `http://localhost:21430`
2. Navigate to **Settings → Site Credentials**
3. Expand the site section
4. Enter credentials (see [Exporting Cookies](#exporting-cookies) for cookie-based sites)
5. Click "Save Credentials"

---

## Sites with Optional Credentials

These sites work without credentials but may have rate limits or restricted content access. Configure via **Dashboard → Settings → Site Credentials**.

| Site | Credentials | Purpose |
|------|-------------|---------|
| Danbooru | API key, User ID | Avoid rate limits, access restricted content |
| Gelbooru | API key, User ID | Avoid rate limits |
| Rule34.xxx | API key, User ID | Avoid rate limits |
| Misskey | Username, Password, Access Key (Required) | Access private posts |
| Reddit | Client ID, Client Secret, Username | Access private subreddits/posts |

---

## Sites Requiring Special Handling

### Moeview

**Domain:** `moeview.app`

**Issue:** Moeview is an image viewer/aggregator, not a content host. gallery-dl cannot extract from Moeview URLs.

**Solution:** Use the source link instead:
1. On Moeview, find the "Source" link (usually top-right, e.g., "Source: yande.re")
2. Right-click the source link → "Send link to Szurubooru"
3. CCC receives the actual booru URL (e.g., `yande.re/post/12345`) which gallery-dl supports

**Do not:** Send the Moeview page URL itself

### 4chan

**Domain:** `4chan.org`

**Issue:** Thread URLs don't point to specific media files.

**Solution:** Send the direct media link:
- **Option 1:** Open the image/video in a new tab (so the URL bar shows the media URL) → Use "Send page URL to Szurubooru"
- **Option 2:** Right-click the image/video link → "Send link to Szurubooru"

**Note:** No tag extraction available for 4chan media (anonymous board, no metadata)

---

## Sites with Limited Metadata

Some sites provide minimal or no metadata:

| Site | Limitation |
|------|------------|
| Twitter / X | No tags, limited metadata (username, tweet text) |
| 4chan | No tags, no metadata (anonymous board) |
| Reddit | No tags, limited metadata (subreddit, title) |

For these sites, the WD14 AI tagger will still run to generate tags automatically.

---

## Exporting Cookies

Some sites (Twitter, Pixiv, etc.) require browser cookies for authentication.

### Steps

1. **Install a cookie export extension:**
   - **Chrome:** "Get cookies.txt LOCALLY" or "EditThisCookie"
   - **Firefox:** "Get cookies.txt" or "Cookie Quick Manager"

2. **Export cookies:**
   - Navigate to the site and ensure you're logged in
   - Open the cookie extension
   - Export cookies in **Netscape format** (not JSON)
   - Copy the entire exported text

3. **Add to CCC Dashboard:**
   - Login to CCC Dashboard at `http://localhost:21430`
   - Navigate to **Settings → Site Credentials**
   - Expand the site section (Twitter, Pixiv, etc.)
   - Paste the exported cookies in the "Cookies" field
   - Click "Save Credentials"

### Cookie Format Example (X / Twitter)

```
# Netscape HTTP Cookie File
.x.com	TRUE	/	TRUE	1234567890	auth_token	abc123xyz...
.x.com	TRUE	/	FALSE	1234567890	ct0	def456uvw...
```

### Important Notes

- **Cookies expire:** Typically every few weeks. Re-export when downloads start failing
- **Multiple accounts:** Export cookies while logged into the account you want to use
- **Security:** All cookies are encrypted in the database

---

## Testing Site Support

To test if a site works:

1. Send a URL from the site via browser extension or mobile app
2. Check the CCC dashboard or mobile app job status
3. If it fails, check backend logs: `docker compose logs ccc-backend`

Common failure reasons:
- Site requires authentication (configure cookies/credentials)
- URL format not supported by gallery-dl (check [gallery-dl supported sites](https://github.com/mikf/gallery-dl/blob/master/docs/supportedsites.md))
- Site has anti-bot protection (may need additional configuration)

---

## Requesting Site Support

If a site doesn't work:

1. **Check if [gallery-dl supports it](https://github.com/mikf/gallery-dl/blob/master/docs/supportedsites.md)**

2. **If gallery-dl supports it:**
   - The site likely requires configuration in CCC (cookies, credentials, etc.)
   - Open an issue in the [repository](https://github.com/jakedev796/SzurubooruCompanion/issues)
   - Include: site name, example URL, and any error messages from the backend logs

3. **If gallery-dl does NOT support it:**
   - Request support in the [gallery-dl repository](https://github.com/mikf/gallery-dl/issues)
   - Once gallery-dl adds support, open an issue here to add the configuration

CCC relies on gallery-dl and yt-dlp for extraction. Even if a site is supported by gallery-dl, CCC may need additional configuration to work with it properly.

---

## Browser Extension DOM Extraction

The browser extension has DOM extraction capabilities, allowing custom site support to be added directly in the extension code even if gallery-dl doesn't support the site. This works by extracting data from the page's DOM structure.

**Important limitations:**
- DOM extraction **only works in the browser extension**
- The mobile app cannot access page content, so it relies entirely on gallery-dl/yt-dlp support
- Sites added via DOM extraction will not work when URLs are shared from the mobile app

If you need a site to work across all platforms (browser extension and mobile app), it must be supported by gallery-dl or yt-dlp.
