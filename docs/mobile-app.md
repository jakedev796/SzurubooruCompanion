# Mobile App (Flutter)

Android app for sending URLs and media to the CCC backend via the system share sheet. Android only; there are no plans to support iOS at this time.

## Install

Release APKs are in the repo root [`builds/`](../builds/) folder. Sideload the APK (copy to device and open, or use `adb install <path-to-apk>`).

After installing, open the app and set the CCC URL in Settings. Use the system share sheet to send URLs or media to the app.

## Build from source (developers)

**Prerequisites:** [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.10+).

```bash
cd mobile-app
flutter pub get
```

**Android:**

| Command | Output |
|---------|--------|
| `flutter build apk` | APK at `build/app/outputs/flutter-apk/app-release.apk` |
| `flutter build appbundle` | AAB at `build/app/outputs/bundle/release/app-release.aab` (for Play Store) |

**Install:** Sideload the APK or run `adb install build/app/outputs/flutter-apk/app-release.apk` with a device connected.
