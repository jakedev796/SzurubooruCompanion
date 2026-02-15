import 'package:flutter/services.dart';

const _channel = MethodChannel('com.szurubooru.szuruqueue/share');

/// Start the foreground status service so the app stays active for background sync/delete.
/// Call from main isolate only (e.g. when enabling folder sync).
Future<void> startStatusForegroundService({String? body}) async {
  try {
    await _channel.invokeMethod('startForegroundStatusService', {
      'body': body ?? 'Folder sync enabled. Next sync in ~15 min.',
    });
  } on PlatformException catch (_) {
    // Service may not be available on all devices
  }
}

/// Stop the foreground status service (e.g. when disabling folder sync).
Future<void> stopStatusForegroundService() async {
  try {
    await _channel.invokeMethod('stopForegroundStatusService');
  } on PlatformException catch (_) {}
}
