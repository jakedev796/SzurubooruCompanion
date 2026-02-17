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

Some sites require authentication or cookies to download media. Configure these in `ccc/backend/.env`.

### Sankaku

**Domains:** `sankaku.app`, `chan.sankakucomplex.com`, `idol.sankakucomplex.com`

**Required:**
```env
SANKAKU_USERNAME=your-username
SANKAKU_PASSWORD=your-password
```

Login is mandatory for the extractor to function.

### Twitter / X

**Domains:** `twitter.com`, `x.com`

**Required:**
```env
TWITTER_COOKIES="<netscape-format cookies>"
```

Twitter authentication requires browser cookies due to API restrictions. See [Twitter Cookie Setup](#twitter-cookie-setup) below for detailed instructions.

### Pixiv

**Domains:** `pixiv.net`

**Required:**
```env
PIXIV_COOKIES="<netscape-format cookies>"
```

Pixiv requires authentication for most content. Export cookies using the same method as Twitter.

---

## Sites with Optional Credentials

These sites work without credentials but may have rate limits or restricted content access.

| Site | Environment Variables | Purpose |
|------|----------------------|---------|
| Danbooru | `DANBOORU_API_KEY`, `DANBOORU_USER_ID` | Avoid rate limits, access restricted content |
| Gelbooru | `GELBOORU_API_KEY`, `GELBOORU_USER_ID` | Avoid rate limits |
| Rule34.xxx | `RULE34_API_KEY`, `RULE34_USER_ID` | Avoid rate limits |
| Misskey | `MISSKEY_USERNAME`, `MISSKEY_PASSWORD` | Access private posts |
| Reddit | `REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET`, `REDDIT_USERNAME` | Access private subreddits/posts |

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

## Twitter Cookie Setup

Twitter authentication requires browser cookies in Netscape format.

### Export Cookies

1. **Install a cookie export extension:**
   - Chrome: "Get cookies.txt LOCALLY" or "EditThisCookie"
   - Firefox: "Get cookies.txt" or "Cookie Quick Manager"

2. **Export while logged into Twitter:**
   - Navigate to [twitter.com](https://twitter.com) and ensure you're logged in
   - Open the cookie extension
   - Export cookies in **Netscape format** (not JSON)
   - Copy the entire exported text

### Configure Backend

3. **Set the environment variable** in `ccc/backend/.env`:

```env
TWITTER_COOKIES="# Netscape HTTP Cookie File
.twitter.com	TRUE	/	TRUE	1234567890	auth_token	abc123xyz...
.twitter.com	TRUE	/	FALSE	1234567890	ct0	def456uvw...
..."
```

Use quotes and paste the full Netscape-format content. For multi-line values, most `.env` parsers support quoted multi-line strings.

4. **Restart the backend:**

```bash
docker compose restart ccc-backend
```

### Important Notes

- **No file needed:** The backend writes cookies to a temporary file when calling gallery-dl and removes it after
- **Cookies expire:** Typically every few weeks. Re-export and update when downloads start failing
- **Multiple accounts:** Export cookies while logged into the account you want CCC to use

### Troubleshooting

**"Authentication failed" errors:**
- Re-export cookies (they may have expired)
- Ensure you copied the entire Netscape format block
- Verify you're logged into Twitter when exporting
- Check that the env var is properly quoted in `.env`

---

## Pixiv Cookie Setup

Follow the same process as Twitter:

1. Export Pixiv cookies in Netscape format while logged in
2. Set `PIXIV_COOKIES` in `ccc/backend/.env`
3. Restart the backend

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
