import 'package:flutter/services.dart';

const _channel = MethodChannel('com.szurubooru.szuruqueue/share');

/// Builds the persistent notification body from connection text and feature flags.
String buildCompanionNotificationBody({
  String? connectionText,
  bool folderSyncOn = false,
  bool bubbleOn = false,
}) {
  final parts = <String>[];
  if (connectionText != null && connectionText.isNotEmpty) {
    parts.add(connectionText);
  }
  if (folderSyncOn) parts.add('Folder sync on');
  if (bubbleOn) parts.add('Bubble on');
  if (parts.isEmpty) return 'SzuruCompanion active';
  return parts.join(' • ');
}

/// Start or sync the single companion foreground service (one notification, optional bubble).
/// Starts when folder sync and/or bubble is enabled. Uses one merged notification (dataSync type)
/// so Android does not show a separate "overlay" system notification.
Future<void> startCompanionForegroundService({
  required bool folderSyncEnabled,
  required bool bubbleEnabled,
  String? statusBody,
}) async {
  try {
    if (!folderSyncEnabled && !bubbleEnabled) {
      await stopCompanionForegroundService();
      return;
    }
    final body = statusBody ??
        buildCompanionNotificationBody(
          folderSyncOn: folderSyncEnabled,
          bubbleOn: bubbleEnabled,
        );
    await _channel.invokeMethod('startCompanionForegroundService', {
      'folderSyncEnabled': folderSyncEnabled,
      'bubbleEnabled': bubbleEnabled,
      'statusBody': body,
    });
  } on PlatformException catch (_) {}
}

/// Update only the persistent notification body (e.g. connection status). Keeps bubble state.
Future<void> updateCompanionNotification({String? statusBody}) async {
  if (statusBody == null || statusBody.isEmpty) return;
  try {
    await _channel.invokeMethod('updateCompanionNotification', {
      'statusBody': statusBody,
    });
  } catch (_) {}
}

/// Stop the companion foreground service and remove the persistent notification.
Future<void> stopCompanionForegroundService() async {
  try {
    await _channel.invokeMethod('stopCompanionForegroundService');
  } on PlatformException catch (_) {}
}
