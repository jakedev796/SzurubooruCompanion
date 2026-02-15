import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service for managing MANAGE_EXTERNAL_STORAGE permission
class StoragePermissionService {
  static const MethodChannel _channel = MethodChannel(
    'com.szurubooru.szuruqueue/storage',
  );

  /// Check if app has MANAGE_EXTERNAL_STORAGE permission
  static Future<bool> hasStoragePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasStoragePermission');
      return result ?? false;
    } catch (e) {
      debugPrint('[StoragePermission] Error checking permission: $e');
      return false;
    }
  }

  /// Request MANAGE_EXTERNAL_STORAGE permission
  /// This will open the system settings page where user must manually grant permission
  static Future<void> requestStoragePermission() async {
    try {
      await _channel.invokeMethod('requestStoragePermission');
    } catch (e) {
      debugPrint('[StoragePermission] Error requesting permission: $e');
    }
  }
}
