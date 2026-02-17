# Mobile App

Flutter Android app for sending URLs and media to the CCC backend. Supports system share sheet integration, floating bubble overlay for quick clipboard capture, and built-in job monitoring.

**Platform:** Android only (no iOS support planned)

---

## Installation

### Pre-built APK

Release APKs are available in [`builds/`](../builds/).

**Install via sideloading:**
1. Copy `SzuruCompanion.apk` to your Android device
2. Open the APK file and tap "Install"
3. Allow installation from unknown sources if prompted

**Install via ADB:**
```bash
adb install builds/SzuruCompanion.apk
```

### Configuration

After installing:
1. Open the app
2. You will be prompted for **Setup** (backend URL) and then **Login** (username/password). The app uses JWT authentication with the CCC backend; no API key is used.
3. Enter your CCC backend URL (e.g., `https://ccc.example.com` or `http://192.168.1.100:21425`)
4. Log in with your dashboard username and password
5. Configure optional features (floating bubble, folder sync) in the **Settings** tab

---

## Features

### Share Sheet Integration

Send URLs from any app using Android's native share feature:

1. Open any app (browser, gallery, social media)
2. Find the share button
3. Select "SzuruCompanion" from the share menu
4. The URL is queued to your CCC backend

### Floating Bubble Overlay

A draggable bubble that sits on top of other apps for quick clipboard capture.

**Enable:**
1. Open SzuruCompanion → Settings
2. Toggle "Enable Floating Bubble"
3. Grant "Display over other apps" permission when prompted

**Usage:**
1. Copy any URL in any app (browser, Twitter, Reddit, etc.)
2. Tap the floating bubble
3. Visual feedback shows success (green glow) or failure (red pulse)
4. The URL is queued immediately

**Bubble behavior:**
- Drag to reposition (snaps to left/right edge)
- Position is saved between app restarts
- Green glow animation on successful queue
- Red pulse animation on failure

### Job Status Viewer

Monitor your upload queue directly in the app:

1. Open SzuruCompanion
2. Navigate to the **Jobs** tab
3. View real-time status of queued, processing, and completed jobs
4. See job details, errors, and processing logs

### Background Folder Sync

Optional automated uploads from device folders.

**Enable:**
1. Open SzuruCompanion → Settings
2. Toggle "Enable Folder Sync"
3. Select folders to monitor (e.g., Camera, Downloads)
4. Configure sync interval

When enabled, the app periodically scans selected folders and uploads new media to your CCC backend.

---

## Building from Source

**Prerequisites:**
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.10+
- Android SDK and build tools

**Build commands:**

```bash
cd mobile-app
flutter pub get

# Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Build release AAB (for Play Store)
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

**Development:**

```bash
# Run on connected device/emulator
flutter run

# Hot reload enabled - press 'r' to reload, 'R' to restart
```
---

## Permissions

The app requires the following Android permissions:

| Permission | Purpose | Required |
|------------|---------|----------|
| Internet | Communicate with CCC backend | Yes |
| Display over other apps | Floating bubble overlay | Optional |
| Read external storage | Folder sync feature | Optional |
| Foreground service | Background processing | Yes |

---

## Troubleshooting

**Floating bubble not appearing:**
- Grant "Display over other apps" permission in Android settings
- Ensure the service is running (check notification)
- Try toggling the feature off and on in Settings

**Visual feedback not showing:**
- Bubble animations only trigger after tapping the bubble
- Ensure the backend URL is configured correctly
- Check that the CCC backend is accessible from your device

**Share sheet not working:**
- Verify the backend URL is correct in Settings
- Check network connectivity
- Ensure the app has internet permission

**Folder sync not uploading:**
- Grant storage permission
- Verify selected folders contain media files
- Check sync interval and last sync time in Settings

**Job status not updating:**
- Ensure the backend URL is accessible and you are logged in (JWT)
- Pull down to refresh the jobs list
