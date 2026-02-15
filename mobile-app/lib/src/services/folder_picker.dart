import 'package:saf/saf.dart';
import 'package:uuid/uuid.dart';
import '../models/scheduled_folder.dart';
import 'settings_model.dart';

/// Helper class for picking folders using SAF
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
      // Use a default directory path - the user will select the actual directory
      final saf = Saf("/storage/emulated/0");
      
      // Request directory permission - this opens the folder picker
      final granted = await saf.getDirectoryPermission(
        grantWritePermission: false,
        isDynamic: true,
      );
      
      if (granted != true) {
        return null; // User cancelled or permission denied
      }

      // Get the selected directory path
      final directories = await Saf.getPersistedPermissionDirectories();
      if (directories == null || directories.isEmpty) {
        return null;
      }

      // Get the most recently selected directory
      final selectedPath = directories.last;

      final folder = ScheduledFolder(
        id: _uuid.v4(),
        name: name,
        uri: selectedPath,
        intervalSeconds: intervalSeconds,
        enabled: true,
        defaultTags: defaultTags,
        defaultSafety: defaultSafety,
        skipTagging: skipTagging,
      );

      await _settings.addScheduledFolder(folder);
      return folder;
    } catch (e) {
      debugPrint('Error picking folder: $e');
      return null;
    }
  }

  /// Get display name for a folder URI
  Future<String> getFolderDisplayName(String uri) async {
    try {
      // Extract the last part of the URI path as display name
      final parts = uri.split('/');
      final name = parts.lastWhere(
        (p) => p.isNotEmpty,
        orElse: () => 'Unknown Folder',
      );
      return Uri.decodeComponent(name);
    } catch (e) {
      return 'Unknown Folder';
    }
  }

  /// Validate that a folder URI is still accessible
  Future<bool> isFolderAccessible(String uri) async {
    try {
      final saf = Saf(uri);
      final paths = await saf.getFilesPath();
      return paths != null;
    } catch (e) {
      return false;
    }
  }
}

/// Debug print function for folder_picker
void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}
