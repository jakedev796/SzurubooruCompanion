import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/scheduled_folder.dart';
import 'settings_model.dart';

/// Helper class for picking folders using file_picker with MANAGE_EXTERNAL_STORAGE
class FolderPicker {
  final SettingsModel _settings;
  final _uuid = const Uuid();

  FolderPicker(this._settings);

  /// Open folder picker and return selected folder info
  ///
  /// Returns null if user cancels or an error occurs
  Future<ScheduledFolder?> pickFolder({
    required String name,
    required int intervalSeconds,
    List<String>? defaultTags,
    String? defaultSafety,
    bool skipTagging = false,
  }) async {
    try {
      // Use file_picker to select a directory
      final result = await FilePicker.platform.getDirectoryPath();

      if (result == null) {
        debugPrint('[FolderPicker] User cancelled folder selection');
        return null; // User cancelled
      }

      debugPrint('[FolderPicker] Selected directory: $result');

      // Verify the directory exists
      final directory = Directory(result);
      if (!await directory.exists()) {
        debugPrint('[FolderPicker] ERROR: Selected directory does not exist: $result');
        return null;
      }

      // Convert absolute path to relative path if it's under /storage/emulated/0/
      String folderUri = result;
      const storagePrefix = '/storage/emulated/0/';
      if (result.startsWith(storagePrefix)) {
        folderUri = result.substring(storagePrefix.length);
        debugPrint('[FolderPicker] Converted to relative path: $folderUri');
      }

      final folder = ScheduledFolder(
        id: _uuid.v4(),
        name: name,
        uri: folderUri,
        intervalSeconds: intervalSeconds,
        enabled: true,
        defaultTags: defaultTags,
        defaultSafety: defaultSafety,
        skipTagging: skipTagging,
      );

      await _settings.addScheduledFolder(folder);
      debugPrint('[FolderPicker] Folder added: ${folder.name} at ${folder.uri}');
      return folder;
    } catch (e, stackTrace) {
      debugPrint('[FolderPicker] Error picking folder: $e');
      debugPrint('[FolderPicker] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get display name for a folder URI
  String getFolderDisplayName(String uri) {
    try {
      // Extract the last part of the path as display name
      final parts = uri.split('/');
      final name = parts.lastWhere(
        (p) => p.isNotEmpty,
        orElse: () => 'Unknown Folder',
      );
      return Uri.decodeComponent(name);
    } catch (e) {
      debugPrint('[FolderPicker] Error getting display name: $e');
      return 'Unknown Folder';
    }
  }

  /// Validate that a folder URI is still accessible
  Future<bool> isFolderAccessible(String uri) async {
    try {
      // Convert relative path to absolute if needed
      final absolutePath = uri.startsWith('/')
          ? uri
          : '/storage/emulated/0/$uri';

      final directory = Directory(absolutePath);
      final exists = await directory.exists();
      debugPrint('[FolderPicker] Folder $uri accessible: $exists');
      return exists;
    } catch (e) {
      debugPrint('[FolderPicker] Error checking folder accessibility: $e');
      return false;
    }
  }
}
