# Supported sites

The following sites have been confirmed working with CCC. Any site [supported by gallery-dl](https://github.com/mikf/gallery-dl) may work; this list is only what has been explicitly tested.

- An asterisk (\*) indicates caveats (see sections below).
- Double asterisk (\**) indicates no tag extraction is available (see sections below).

| Site |
|------|
| Sankaku\* |
| Yande.re |
| X / Twitter\** |
| Danbooru |
| Moeview\* |
| 4chan\** |

## Sites requiring extra configuration

Some sources need env vars (e.g. login credentials) for gallery-dl to work; without them, jobs from these sites may fail.

| Site | Domains | Required configuration |
|------|---------|------------------------|
| **Sankaku** | sankaku.app, chan.sankakucomplex.com, idol.sankakucomplex.com, www.sankakucomplex.com | Set `SANKAKU_USERNAME` and `SANKAKU_PASSWORD` in `ccc/backend/.env`. Login is required for the extractor to work. |
| **Twitter / X** | twitter.com, x.com | Set `TWITTER_COOKIES` in `ccc/backend/.env` to the Netscape-format cookie content. See [Twitter Cookie Setup](#twitter-cookie-setup) below. |

## Sites requiring special handling

Some sites are aggregators or viewers that display content from other sources. gallery-dl may not support the aggregator URL; you need to send the **underlying source link** to CCC instead of the page you are on.

| Site | What to do |
|------|------------|
| **Moeview / moebooru** (moeview.app, etc.) | Do not "Send page URL to Szurubooru" from the Moeview page. Use the **source** link (e.g. in the top-right: "Source: yande.re" or similar). Right-click that source link and choose "Send link to Szurubooru" so CCC receives the actual booru URL (e.g. yande.re) that gallery-dl supports. |
| **4chan** | Do not send the thread page URL. Either have the **specific media open in a tab by itself** (e.g. the image/video URL) and use "Send page URL to Szurubooru", or right-click the **link to the media** (the image or video link on the thread) and choose "Send link to Szurubooru". Same idea as Moeview: CCC must receive the direct media URL, not the thread. **No tag extraction available for obvious reasons.** |

## Twitter Cookie Setup

Twitter authentication in gallery-dl works best with browser cookies. Due to Twitter's API restrictions, username/password alone is often unreliable. Pass the literal cookie content via env (no file needed):

1. **Install a browser extension** to export cookies:
   - Chrome: "Get cookies.txt LOCALLY" or "EditThisCookie"
   - Firefox: "Get cookies.txt" or "Cookie Quick Manager"

2. **Export cookies** while logged into Twitter:
   - Navigate to [twitter.com](https://twitter.com) and ensure you're logged in
   - Open the cookie extension and export cookies in **Netscape format**
   - Copy the full exported text (the entire file content)

3. **Set the env var** in `ccc/backend/.env` to that literal content:
   ```bash
   TWITTER_COOKIES="domain	flag	path	secure	expiry	name	value
   .twitter.com	TRUE	/	TRUE	1234567890	auth_token	..."
   ```
   Use quotes and paste the full Netscape-format block. For multi-line values, ensure your `.env` supports it (e.g. quoted multi-line or escaped newlines as needed by your env loader).

4. **Restart the backend** after updating:
   ```bash
   docker compose restart ccc-backend
   ```

**Important notes:**
- No physical cookie file or volume mount is required; the backend writes the content to a temp file when calling gallery-dl and removes it after.
- Cookies expire and need periodic refresh (typically every few weeks).
- If Twitter downloads start failing with authentication errors, re-export and update `TWITTER_COOKIES`.