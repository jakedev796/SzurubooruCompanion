# SzuruCompanion Mobile App

A Flutter-based mobile companion for [Szurubooru](https://github.com/rr-/szurubooru) that works with the CCC backend to queue and manage image uploads.

## Features

- Submit URLs for download, tagging, and upload to your Szurubooru instance
- Real-time job status updates via SSE (Server-Sent Events)
- View job history with status filtering
- Multi-user support — select which Szurubooru user to upload as
- Share URLs directly from other apps via Android share intent
- Folder sync — automatically enqueue images from a local folder

## Setup

1. Install [Flutter](https://docs.flutter.dev/get-started/install)
2. Run `flutter pub get` in this directory
3. Run `flutter run` to launch on a connected device or emulator
4. Configure the backend URL in Setup, then log in with your dashboard username and password (JWT; no API key)

## Building

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release
```
