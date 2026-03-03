# Supported Sites

CCC supports any site that [gallery-dl](https://github.com/mikf/gallery-dl) or [yt-dlp](https://github.com/yt-dlp/yt-dlp) can extract media from. The full list with download/tag extraction/config status is in the dashboard under **Settings → Supported Sites**.

Configure credentials at **Settings → Site Credentials** when required (all credentials are encrypted).

---

## Sites Requiring Special Handling

### Moeview

**Domain:** `moeview.app`

Moeview is an image viewer/aggregator, not a content host. gallery-dl cannot extract from Moeview URLs.

**Solution:** Use the source link instead. On Moeview, find the "Source" link (e.g. "Source: yande.re"), right-click → "Send link to Szurubooru". Do not send the Moeview page URL itself.

### 4chan

**Domain:** `4chan.org`

Thread URLs don't point to specific media files. Send the direct media link instead: open the image/video in a new tab, or right-click the image link → "Send link to Szurubooru". No tag extraction available (anonymous board).

---

## Exporting Cookies

Sites like Twitter and Pixiv require browser cookies. Export in **Netscape format** using an extension (e.g. "Get cookies.txt LOCALLY"), then paste into **Settings → Site Credentials**. Cookies expire periodically; re-export when downloads fail.

---

## Testing Site Support

1. Send a URL via browser extension or mobile app
2. Check job status in the dashboard
3. If it fails: check backend logs (`docker compose logs ccc-backend`), verify credentials, or check [gallery-dl supported sites](https://github.com/mikf/gallery-dl/blob/master/docs/supportedsites.md)

---

## Requesting Site Support

1. Check if [gallery-dl supports it](https://github.com/mikf/gallery-dl/blob/master/docs/supportedsites.md)
2. If yes: open an issue here with site name, example URL, and error logs
3. If no: request support in gallery-dl first; once added, open an issue here for configuration

---

## Browser Extension DOM Extraction

The browser extension can extract data from page DOM even when gallery-dl doesn't support a site. This only works in the extension; the mobile app relies entirely on gallery-dl/yt-dlp.
