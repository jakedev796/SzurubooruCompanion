import 'package:flutter/services.dart';

const _channel = MethodChannel('com.szurubooru.szuruqueue/share');

/// Start the floating bubble overlay service.
/// Requires SYSTEM_ALERT_WINDOW permission (check with [canDrawOverlays] first).
Future<void> startFloatingBubbleService() async {
  try {
    await _channel.invokeMethod('startFloatingBubbleService');
  } on PlatformException catch (_) {
    // Service may not be available on all devices
  }
}

/// Stop the floating bubble overlay service.
Future<void> stopFloatingBubbleService() async {
  try {
    await _channel.invokeMethod('stopFloatingBubbleService');
  } on PlatformException catch (_) {}
}

/// Check whether the app has "Display over other apps" permission.
Future<bool> canDrawOverlays() async {
  try {
    final result = await _channel.invokeMethod<bool>('canDrawOverlays');
    return result ?? false;
  } on PlatformException catch (_) {
    return false;
  }
}

/// Open Android Settings so the user can grant overlay permission.
Future<void> requestOverlayPermission() async {
  try {
    await _channel.invokeMethod('requestOverlayPermission');
  } on PlatformException catch (_) {}
}
