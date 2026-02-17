import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scheduled_folder.dart';
import '../models/auth.dart';

/// Settings model for the SzuruCompanion app.
/// 
/// Stores and manages:
/// - Backend URL (the CCC backend server address)
/// - API Key (optional, for authentication with the backend if required)
/// - Background service preference
/// - Default tags for uploads
/// - Default safety rating
/// - Polling interval for job status updates
class SettingsModel extends ChangeNotifier {
  String _backendUrl = '';
  String _apiKey = '';
  bool _useBackgroundService = true;
  String _defaultTags = '';
  String _defaultSafety = 'unsafe';
  bool _skipTagging = false;
  bool _isConfigured = false;
  int _pollingIntervalSeconds = 5;
  bool _notifyOnFolderSync = false;
  bool _deleteMediaAfterSync = false;
  bool _showPersistentNotification = true;
  int _folderSyncIntervalSeconds = 900;
  bool _showFloatingBubble = false;
  bool _isAuthenticated = false;
  String _username = '';

  String get backendUrl => _backendUrl;
  String get apiKey => _apiKey;
  bool get useBackgroundService => _useBackgroundService;
  String get defaultTags => _defaultTags;
  String get defaultSafety => _defaultSafety;
  bool get skipTagging => _skipTagging;
  bool get isConfigured => _isConfigured;
  int get pollingIntervalSeconds => _pollingIntervalSeconds;
  bool get notifyOnFolderSync => _notifyOnFolderSync;
  bool get deleteMediaAfterSync => _deleteMediaAfterSync;
  bool get showPersistentNotification => _showPersistentNotification;
  int get folderSyncIntervalSeconds => _folderSyncIntervalSeconds;
  bool get showFloatingBubble => _showFloatingBubble;
  bool get isAuthenticated => _isAuthenticated;
  String get username => _username;

  /// Load settings from persistent storage
  /// If SharedPreferences is empty, attempts to restore from backup file
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if SharedPreferences has any settings
    final hasBackendUrl = prefs.containsKey('backendUrl');
    
    // If no settings found, try to restore from backup
    if (!hasBackendUrl) {
      await _restoreFromBackup();
      // Reload prefs after restore
      final prefsAfterRestore = await SharedPreferences.getInstance();
      _backendUrl = prefsAfterRestore.getString('backendUrl') ?? '';
      _apiKey = prefsAfterRestore.getString('apiKey') ?? '';
      _useBackgroundService = prefsAfterRestore.getBool('useBackgroundService') ?? true;
      _defaultTags = prefsAfterRestore.getString('defaultTags') ?? '';
      _defaultSafety = prefsAfterRestore.getString('defaultSafety') ?? 'unsafe';
      _skipTagging = prefsAfterRestore.getBool('skipTagging') ?? false;
      _pollingIntervalSeconds = prefsAfterRestore.getInt('pollingIntervalSeconds') ?? 5;
      _notifyOnFolderSync = prefsAfterRestore.getBool('notifyOnFolderSync') ?? false;
      _deleteMediaAfterSync = prefsAfterRestore.getBool('deleteMediaAfterSync') ?? false;
      _showPersistentNotification = prefsAfterRestore.getBool('showPersistentNotification') ?? true;
      _folderSyncIntervalSeconds = prefsAfterRestore.getInt('folderSyncIntervalSeconds') ?? 900;
      _showFloatingBubble = prefsAfterRestore.getBool('showFloatingBubble') ?? false;
    } else {
      // Load normally from SharedPreferences
      _backendUrl = prefs.getString('backendUrl') ?? '';
      _apiKey = prefs.getString('apiKey') ?? '';
      _useBackgroundService = prefs.getBool('useBackgroundService') ?? true;
      _defaultTags = prefs.getString('defaultTags') ?? '';
      _defaultSafety = prefs.getString('defaultSafety') ?? 'unsafe';
      _skipTagging = prefs.getBool('skipTagging') ?? false;
      _pollingIntervalSeconds = prefs.getInt('pollingIntervalSeconds') ?? 5;
      _notifyOnFolderSync = prefs.getBool('notifyOnFolderSync') ?? false;
      _deleteMediaAfterSync = prefs.getBool('deleteMediaAfterSync') ?? false;
      _showPersistentNotification = prefs.getBool('showPersistentNotification') ?? true;
      _folderSyncIntervalSeconds = prefs.getInt('folderSyncIntervalSeconds') ?? 900;
      _showFloatingBubble = prefs.getBool('showFloatingBubble') ?? false;
    }

    // Load auth state
    _username = prefs.getString('username') ?? '';
    _isAuthenticated = prefs.containsKey('auth_tokens');

    _isConfigured = _backendUrl.isNotEmpty;
    notifyListeners();
  }

  /// Save settings to persistent storage
  Future<void> saveSettings({
    String? backendUrl,
    String? apiKey,
    bool? useBackgroundService,
    String? defaultTags,
    String? defaultSafety,
    bool? skipTagging,
    int? pollingIntervalSeconds,
    bool? notifyOnFolderSync,
    bool? deleteMediaAfterSync,
    bool? showPersistentNotification,
    int? folderSyncIntervalSeconds,
    bool? showFloatingBubble,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (backendUrl != null) {
      _backendUrl = backendUrl;
      await prefs.setString('backendUrl', _backendUrl);
    }
    
    if (apiKey != null) {
      _apiKey = apiKey;
      await prefs.setString('apiKey', _apiKey);
    }
    if (useBackgroundService != null) {
      _useBackgroundService = useBackgroundService;
      await prefs.setBool('useBackgroundService', _useBackgroundService);
    }
    
    if (defaultTags != null) {
      _defaultTags = defaultTags;
      await prefs.setString('defaultTags', _defaultTags);
    }
    
    if (defaultSafety != null) {
      _defaultSafety = defaultSafety;
      await prefs.setString('defaultSafety', _defaultSafety);
    }
    
    if (skipTagging != null) {
      _skipTagging = skipTagging;
      await prefs.setBool('skipTagging', _skipTagging);
    }
    
    if (pollingIntervalSeconds != null) {
      _pollingIntervalSeconds = pollingIntervalSeconds;
      await prefs.setInt('pollingIntervalSeconds', _pollingIntervalSeconds);
    }
    if (notifyOnFolderSync != null) {
      _notifyOnFolderSync = notifyOnFolderSync;
      await prefs.setBool('notifyOnFolderSync', _notifyOnFolderSync);
    }
    if (deleteMediaAfterSync != null) {
      _deleteMediaAfterSync = deleteMediaAfterSync;
      await prefs.setBool('deleteMediaAfterSync', _deleteMediaAfterSync);
    }
    if (showPersistentNotification != null) {
      _showPersistentNotification = showPersistentNotification;
      await prefs.setBool('showPersistentNotification', _showPersistentNotification);
    }
    if (folderSyncIntervalSeconds != null) {
      _folderSyncIntervalSeconds = folderSyncIntervalSeconds.clamp(900, 604800);
      await prefs.setInt('folderSyncIntervalSeconds', _folderSyncIntervalSeconds);
    }
    if (showFloatingBubble != null) {
      _showFloatingBubble = showFloatingBubble;
      await prefs.setBool('showFloatingBubble', _showFloatingBubble);
    }
    _isConfigured = _backendUrl.isNotEmpty;
    
    // Backup settings to external storage for persistence across reinstalls
    await _backupToExternalStorage();
    
    notifyListeners();
  }

  /// Clear all settings and backup file
  Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    // Also delete the backup file to prevent restoration
    await _deleteBackupFile();
    
    _backendUrl = '';
    _apiKey = '';
    _useBackgroundService = true;
    _defaultTags = '';
    _defaultSafety = 'unsafe';
    _skipTagging = false;
    _pollingIntervalSeconds = 5;
    _notifyOnFolderSync = false;
    _deleteMediaAfterSync = false;
    _showPersistentNotification = true;
    _folderSyncIntervalSeconds = 900;
    _showFloatingBubble = false;
    _isConfigured = false;
    notifyListeners();
  }

  /// Parse default tags into a list
  List<String> get defaultTagsList {
    if (_defaultTags.isEmpty) return [];
    return _defaultTags
        .split(RegExp(r'[\s,]+'))
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  /// Check if the settings are valid for making API calls.
  /// Only requires backend URL - API key is optional.
  bool get canMakeApiCalls => _backendUrl.isNotEmpty;

  static const String _scheduledFoldersKey = 'scheduled_folders';
  static const String _pendingDeleteUrisKey = 'pending_delete_uris';
  static const String _lastFolderSyncTimestampKey = 'last_folder_sync_timestamp';
  static const String _lastFolderSyncCountKey = 'last_folder_sync_count';
  static const String _settingsBackupFileName = 'szurucompanion_settings_backup.json';

  /// Get all scheduled folders. Returns empty list on parse error to avoid crashing.
  Future<List<ScheduledFolder>> getScheduledFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_scheduledFoldersKey);
      if (jsonString == null) return [];
      final decoded = jsonDecode(jsonString);
      if (decoded is! List<dynamic>) return [];
      final result = <ScheduledFolder>[];
      for (final item in decoded) {
        try {
          if (item is Map<String, dynamic>) {
            result.add(ScheduledFolder.fromJson(item));
          }
        } catch (_) {
          // Skip malformed folder entry
        }
      }
      return result;
    } catch (e) {
      debugPrint('[SettingsModel] getScheduledFolders error: $e');
      return [];
    }
  }

  /// Save all scheduled folders
  Future<void> setScheduledFolders(List<ScheduledFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = folders.map((f) => f.toJson()).toList();
    await prefs.setString(_scheduledFoldersKey, jsonEncode(jsonList));
  }

  /// Add a new scheduled folder
  Future<void> addScheduledFolder(ScheduledFolder folder) async {
    final folders = await getScheduledFolders();
    folders.add(folder);
    await setScheduledFolders(folders);
  }

  /// Update an existing scheduled folder
  Future<void> updateScheduledFolder(ScheduledFolder folder) async {
    final folders = await getScheduledFolders();
    final index = folders.indexWhere((f) => f.id == folder.id);
    if (index != -1) {
      folders[index] = folder;
      await setScheduledFolders(folders);
    }
  }

  /// Remove a scheduled folder
  Future<void> removeScheduledFolder(String folderId) async {
    final folders = await getScheduledFolders();
    folders.removeWhere((f) => f.id == folderId);
    await setScheduledFolders(folders);
  }

  /// Update last run timestamp for a folder
  Future<void> updateFolderLastRun(String folderId, int timestamp) async {
    final folders = await getScheduledFolders();
    final index = folders.indexWhere((f) => f.id == folderId);
    if (index != -1) {
      folders[index] = folders[index].copyWith(lastRunTimestamp: timestamp);
      await setScheduledFolders(folders);
    }
  }

  /// Enqueue a content URI for deletion when app is in foreground (used by background sync).
  Future<void> addPendingDeleteUri(String uri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getPendingDeleteUris();
      if (!list.contains(uri)) {
        list.add(uri);
        await prefs.setString(_pendingDeleteUrisKey, jsonEncode(list));
      }
    } catch (e) {
      debugPrint('[SettingsModel] addPendingDeleteUri error: $e');
    }
  }

  /// Get URIs queued for deletion. Returns empty list on parse error.
  Future<List<String>> getPendingDeleteUris() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_pendingDeleteUrisKey);
      if (jsonString == null) return [];
      final decoded = jsonDecode(jsonString);
      if (decoded is! List<dynamic>) return [];
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('[SettingsModel] getPendingDeleteUris error: $e');
      return [];
    }
  }

  /// Remove a URI from the pending-delete queue.
  Future<void> removePendingDeleteUri(String uri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await getPendingDeleteUris();
      list.remove(uri);
      await prefs.setString(_pendingDeleteUrisKey, jsonEncode(list));
    } catch (e) {
      debugPrint('[SettingsModel] removePendingDeleteUri error: $e');
    }
  }

  /// Record last folder sync result (called from background task).
  Future<void> setLastFolderSync(int filesUploaded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastFolderSyncTimestampKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(_lastFolderSyncCountKey, filesUploaded);
  }

  /// Get last folder sync time and count for display.
  Future<({int timestamp, int count})> getLastFolderSync() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_lastFolderSyncTimestampKey) ?? 0;
    final count = prefs.getInt(_lastFolderSyncCountKey) ?? 0;
    return (timestamp: ts, count: count);
  }

  Future<Map<String, dynamic>> _buildBackupMap(SharedPreferences prefs) async {
    final folders = await getScheduledFolders();
    return <String, dynamic>{
      'backendUrl': prefs.getString('backendUrl') ?? '',
      'apiKey': prefs.getString('apiKey') ?? '',
      'useBackgroundService': prefs.getBool('useBackgroundService') ?? true,
      'defaultTags': prefs.getString('defaultTags') ?? '',
      'defaultSafety': prefs.getString('defaultSafety') ?? 'unsafe',
      'skipTagging': prefs.getBool('skipTagging') ?? false,
      'pollingIntervalSeconds': prefs.getInt('pollingIntervalSeconds') ?? 5,
      'notifyOnFolderSync': prefs.getBool('notifyOnFolderSync') ?? false,
      'deleteMediaAfterSync': prefs.getBool('deleteMediaAfterSync') ?? false,
      'showPersistentNotification': prefs.getBool('showPersistentNotification') ?? true,
      'folderSyncIntervalSeconds': prefs.getInt('folderSyncIntervalSeconds') ?? 900,
      'showFloatingBubble': prefs.getBool('showFloatingBubble') ?? false,
      'scheduledFolders': folders.map((f) => f.toJson()).toList(),
    };
  }

  /// Backup settings to external storage (persists across app reinstalls)
  Future<void> _backupToExternalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final directory = await getApplicationDocumentsDirectory();
      final backupFile = File(path.join(directory.path, _settingsBackupFileName));
      await backupFile.writeAsString(jsonEncode(await _buildBackupMap(prefs)));
    } catch (e) {
      debugPrint('[SettingsModel] Failed to backup settings: $e');
    }
  }

  Future<void> _applyBackupMapToPrefs(Map<String, dynamic> settingsMap, SharedPreferences prefs) async {
    try {
      if (settingsMap.containsKey('backendUrl')) {
        await prefs.setString('backendUrl', settingsMap['backendUrl'] as String? ?? '');
      }
      if (settingsMap.containsKey('apiKey')) {
        await prefs.setString('apiKey', settingsMap['apiKey'] as String? ?? '');
      }
      if (settingsMap.containsKey('useBackgroundService')) {
        await prefs.setBool('useBackgroundService', settingsMap['useBackgroundService'] as bool? ?? true);
      }
      if (settingsMap.containsKey('defaultTags')) {
        await prefs.setString('defaultTags', settingsMap['defaultTags'] as String? ?? '');
      }
      if (settingsMap.containsKey('defaultSafety')) {
        await prefs.setString('defaultSafety', settingsMap['defaultSafety'] as String? ?? 'unsafe');
      }
      if (settingsMap.containsKey('skipTagging')) {
        await prefs.setBool('skipTagging', settingsMap['skipTagging'] as bool? ?? false);
      }
      if (settingsMap.containsKey('pollingIntervalSeconds')) {
        await prefs.setInt('pollingIntervalSeconds', settingsMap['pollingIntervalSeconds'] as int? ?? 5);
      }
      if (settingsMap.containsKey('notifyOnFolderSync')) {
        await prefs.setBool('notifyOnFolderSync', settingsMap['notifyOnFolderSync'] as bool? ?? false);
      }
      if (settingsMap.containsKey('deleteMediaAfterSync')) {
        await prefs.setBool('deleteMediaAfterSync', settingsMap['deleteMediaAfterSync'] as bool? ?? false);
      }
      if (settingsMap.containsKey('showPersistentNotification')) {
        await prefs.setBool('showPersistentNotification', settingsMap['showPersistentNotification'] as bool? ?? true);
      }
      if (settingsMap.containsKey('folderSyncIntervalSeconds')) {
        await prefs.setInt('folderSyncIntervalSeconds', settingsMap['folderSyncIntervalSeconds'] as int? ?? 900);
      }
      if (settingsMap.containsKey('showFloatingBubble')) {
        await prefs.setBool('showFloatingBubble', settingsMap['showFloatingBubble'] as bool? ?? false);
      }
      if (settingsMap.containsKey('scheduledFolders')) {
        try {
          final foldersJson = settingsMap['scheduledFolders'];
          if (foldersJson is List<dynamic>) {
            final folders = foldersJson.map((json) {
              try {
                if (json is Map<String, dynamic>) {
                  return ScheduledFolder.fromJson(json);
                }
              } catch (e) {
                debugPrint('[SettingsModel] Failed to parse folder: $e');
              }
              return null;
            }).whereType<ScheduledFolder>().toList();
            await setScheduledFolders(folders);
          }
        } catch (e) {
          debugPrint('[SettingsModel] Failed to restore scheduled folders: $e');
        }
      }
    } catch (e) {
      debugPrint('[SettingsModel] Error applying backup to prefs: $e');
      rethrow;
    }
  }

  /// Restore settings from external storage backup (default app documents path)
  Future<void> _restoreFromBackup() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final backupFile = File(path.join(directory.path, _settingsBackupFileName));
      if (!await backupFile.exists()) return;
      final jsonString = await backupFile.readAsString();
      final settingsMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await _applyBackupMapToPrefs(settingsMap, prefs);
      debugPrint('[SettingsModel] Restored settings from backup');
    } catch (e) {
      debugPrint('[SettingsModel] Failed to restore settings from backup: $e');
    }
  }

  /// Delete the backup file
  Future<void> _deleteBackupFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final backupFile = File(path.join(directory.path, _settingsBackupFileName));
      if (await backupFile.exists()) {
        await backupFile.delete();
        debugPrint('[SettingsModel] Deleted backup file');
      }
    } catch (e) {
      debugPrint('[SettingsModel] Failed to delete backup file: $e');
    }
  }

  /// Backup settings to the default app documents directory (used for auto-backup)
  Future<bool> backupSettings() async {
    try {
      await _backupToExternalStorage();
      return true;
    } catch (e) {
      debugPrint('[SettingsModel] Failed to backup settings: $e');
      return false;
    }
  }

  /// Backup settings to a user-selected directory. Returns the full file path on success, null on failure.
  Future<String?> backupSettingsToDirectory(String directoryPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupFile = File(path.join(directoryPath, _settingsBackupFileName));
      await backupFile.writeAsString(jsonEncode(await _buildBackupMap(prefs)));
      return backupFile.path;
    } catch (e) {
      debugPrint('[SettingsModel] Failed to backup settings to directory: $e');
      return null;
    }
  }

  /// Read backup file and return what permissions are needed. Prefer [checkPermissionsNeededFromBackupContent] with already-read JSON when leaving the app to grant permissions.
  Future<Map<String, bool>> checkPermissionsNeededFromBackup(String filePath) async {
    try {
      final backupFile = File(filePath);
      if (!await backupFile.exists()) return {'needsOverlayPermission': false, 'needsStoragePermission': false};
      final jsonString = await backupFile.readAsString();
      return checkPermissionsNeededFromBackupContent(jsonString);
    } catch (e) {
      debugPrint('[SettingsModel] Failed to check permissions from backup: $e');
      return {'needsOverlayPermission': false, 'needsStoragePermission': false};
    }
  }

  /// Same as [checkPermissionsNeededFromBackup] but from backup JSON string. Use when content was already read (e.g. before sending user to Settings).
  Map<String, bool> checkPermissionsNeededFromBackupContent(String jsonString) {
    try {
      final settingsMap = jsonDecode(jsonString) as Map<String, dynamic>?;
      if (settingsMap == null) return {'needsOverlayPermission': false, 'needsStoragePermission': false};
      final showFloatingBubble = settingsMap['showFloatingBubble'] as bool? ?? false;
      final showPersistentNotification = settingsMap['showPersistentNotification'] as bool? ?? true;
      bool needsStoragePermission = false;
      if (showPersistentNotification) {
        final foldersJson = settingsMap['scheduledFolders'] as List<dynamic>?;
        if (foldersJson != null) {
          try {
            final folders = foldersJson.map((e) => e is Map<String, dynamic> ? ScheduledFolder.fromJson(e) : null).whereType<ScheduledFolder>().toList();
            needsStoragePermission = folders.any((f) => f.enabled);
          } catch (_) {}
        }
      }
      return {'needsOverlayPermission': showFloatingBubble, 'needsStoragePermission': needsStoragePermission};
    } catch (e) {
      debugPrint('[SettingsModel] Failed to check permissions from backup content: $e');
      return {'needsOverlayPermission': false, 'needsStoragePermission': false};
    }
  }

  /// Restore settings from a user-selected backup file.
  /// Prefer [restoreSettingsFromJsonString] when the app may leave to grant permissions so the path stays valid.
  Future<bool> restoreSettingsFromFile(String filePath) async {
    try {
      final backupFile = File(filePath);
      if (!await backupFile.exists()) {
        debugPrint('[SettingsModel] Backup file does not exist: $filePath');
        return false;
      }
      final jsonString = await backupFile.readAsString();
      return await restoreSettingsFromJsonString(jsonString);
    } catch (e, stackTrace) {
      debugPrint('[SettingsModel] Failed to restore settings from file: $e');
      debugPrint('[SettingsModel] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Restore settings from backup JSON string. Use when file path may be invalid after leaving the app (e.g. returning from Settings).
  /// Writes to SharedPreferences and internal backup so restart sees the same data.
  Future<bool> restoreSettingsFromJsonString(String jsonString) async {
    try {
      if (jsonString.isEmpty) {
        debugPrint('[SettingsModel] Backup JSON is empty');
        return false;
      }
      final settingsMap = jsonDecode(jsonString) as Map<String, dynamic>?;
      if (settingsMap == null) {
        debugPrint('[SettingsModel] Failed to parse backup JSON');
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      await _applyBackupMapToPrefs(settingsMap, prefs);
      await _writeInternalBackup(settingsMap);
      await loadSettings();
      debugPrint('[SettingsModel] Successfully restored settings from JSON');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[SettingsModel] Failed to restore from JSON: $e');
      debugPrint('[SettingsModel] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Write a backup map to the internal backup file (app documents directory).
  /// Used so that after restart, if SharedPreferences has not yet persisted,
  /// loadSettings() -> _restoreFromBackup() will still load the restored data.
  Future<void> _writeInternalBackup(Map<String, dynamic> settingsMap) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final internalFile = File(path.join(directory.path, _settingsBackupFileName));
      await internalFile.writeAsString(jsonEncode(settingsMap));
    } catch (e) {
      debugPrint('[SettingsModel] Failed to write internal backup: $e');
    }
  }

  /// Restore from the default app documents backup (used when SharedPreferences is empty)
  Future<bool> restoreSettings() async {
    try {
      await _restoreFromBackup();
      await loadSettings();
      return true;
    } catch (e) {
      debugPrint('[SettingsModel] Failed to restore settings: $e');
      return false;
    }
  }

  /// Check if a backup file exists in the default app documents directory
  Future<bool> hasBackup() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final backupFile = File(path.join(directory.path, _settingsBackupFileName));
      return await backupFile.exists();
    } catch (e) {
      return false;
    }
  }

  /// Set authentication state and store tokens
  Future<void> setAuthState(bool authed, String username, AuthTokens? tokens) async {
    _isAuthenticated = authed;
    _username = username;

    final prefs = await SharedPreferences.getInstance();
    if (authed && tokens != null) {
      await prefs.setString('auth_tokens', jsonEncode(tokens.toJson()));
      await prefs.setString('username', username);
    } else {
      await prefs.remove('auth_tokens');
      await prefs.remove('username');
    }
    notifyListeners();
  }

  /// Get preferences that should be synced to backend (excludes device-specific settings)
  Map<String, dynamic> getSyncablePreferences() {
    return {
      'defaultTags': _defaultTags,
      'defaultSafety': _defaultSafety,
      'skipTagging': _skipTagging,
      'pollingIntervalSeconds': _pollingIntervalSeconds,
      'folderSyncIntervalSeconds': _folderSyncIntervalSeconds,
      'notifyOnFolderSync': _notifyOnFolderSync,
      'deleteMediaAfterSync': _deleteMediaAfterSync,
      // Exclude: showFloatingBubble, useBackgroundService (device-specific)
    };
  }

  /// Apply synced preferences from backend (merges with local, doesn't override device-specific settings)
  Future<void> applySyncedPreferences(Map<String, dynamic> prefs) async {
    await saveSettings(
      defaultTags: prefs['defaultTags'] as String?,
      defaultSafety: prefs['defaultSafety'] as String?,
      skipTagging: prefs['skipTagging'] as bool?,
      pollingIntervalSeconds: prefs['pollingIntervalSeconds'] as int?,
      folderSyncIntervalSeconds: prefs['folderSyncIntervalSeconds'] as int?,
      notifyOnFolderSync: prefs['notifyOnFolderSync'] as bool?,
      deleteMediaAfterSync: prefs['deleteMediaAfterSync'] as bool?,
    );
  }
}
