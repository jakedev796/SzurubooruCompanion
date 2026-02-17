import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth.dart';
import '../models/scheduled_folder.dart';

/// Settings model for the SzuruCompanion app.
///
/// Stores and manages backend URL, share/folder preferences, and scheduled folders.
/// All settings except backendUrl are synced to the CCC backend when authenticated.
class SettingsModel extends ChangeNotifier {
  String _backendUrl = '';
  bool _useBackgroundService = true;
  String _defaultTags = '';
  String _defaultSafety = 'unsafe';
  bool _skipTagging = false;
  bool _isConfigured = false;
  int _pollingIntervalSeconds = 5;
  bool _notifyOnFolderSync = false;
  bool _deleteMediaAfterSync = false;
  bool _showPersistentNotification = true;
  bool _showFloatingBubble = false;
  int _folderSyncIntervalSeconds = 900;
  bool _isAuthenticated = false;
  String? _username;

  String get backendUrl => _backendUrl;
  bool get useBackgroundService => _useBackgroundService;
  String get defaultTags => _defaultTags;
  String get defaultSafety => _defaultSafety;
  bool get skipTagging => _skipTagging;
  bool get isConfigured => _isConfigured;
  int get pollingIntervalSeconds => _pollingIntervalSeconds;
  bool get notifyOnFolderSync => _notifyOnFolderSync;
  bool get deleteMediaAfterSync => _deleteMediaAfterSync;
  bool get showPersistentNotification => _showPersistentNotification;
  bool get showFloatingBubble => _showFloatingBubble;
  int get folderSyncIntervalSeconds => _folderSyncIntervalSeconds;
  bool get isAuthenticated => _isAuthenticated;
  String? get username => _username;

  /// Load settings from persistent storage
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString('backendUrl') ?? '';
    _useBackgroundService = prefs.getBool('useBackgroundService') ?? true;
    _defaultTags = prefs.getString('defaultTags') ?? '';
    _defaultSafety = prefs.getString('defaultSafety') ?? 'unsafe';
    _skipTagging = prefs.getBool('skipTagging') ?? false;
    _pollingIntervalSeconds = prefs.getInt('pollingIntervalSeconds') ?? 5;
    _notifyOnFolderSync = prefs.getBool('notifyOnFolderSync') ?? false;
    _deleteMediaAfterSync = prefs.getBool('deleteMediaAfterSync') ?? false;
    _showPersistentNotification = prefs.getBool('showPersistentNotification') ?? true;
    _showFloatingBubble = prefs.getBool('showFloatingBubble') ?? false;
    _folderSyncIntervalSeconds = prefs.getInt('folderSyncIntervalSeconds') ?? 900;
    _isAuthenticated = prefs.containsKey('auth_tokens');
    _username = prefs.getString('username');
    _isConfigured = _backendUrl.isNotEmpty;
    notifyListeners();
  }

  /// Update auth state (called after login/logout). [tokens] can be null on logout.
  Future<void> setAuthState(bool authed, String username, dynamic tokens) async {
    _isAuthenticated = authed;
    _username = authed ? username : null;
    final prefs = await SharedPreferences.getInstance();
    if (authed && username.isNotEmpty) {
      await prefs.setString('username', username);
    } else {
      await prefs.remove('username');
    }
    if (authed && tokens != null && tokens is AuthTokens) {
      await prefs.setString('auth_tokens', jsonEncode(tokens.toJson()));
    } else if (!authed) {
      await prefs.remove('auth_tokens');
    }
    notifyListeners();
  }

  /// Save settings to persistent storage
  Future<void> saveSettings({
    String? backendUrl,
    bool? useBackgroundService,
    String? defaultTags,
    String? defaultSafety,
    bool? skipTagging,
    int? pollingIntervalSeconds,
    bool? notifyOnFolderSync,
    bool? deleteMediaAfterSync,
    bool? showPersistentNotification,
    bool? showFloatingBubble,
    int? folderSyncIntervalSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (backendUrl != null) {
      _backendUrl = backendUrl;
      await prefs.setString('backendUrl', _backendUrl);
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
    if (showFloatingBubble != null) {
      _showFloatingBubble = showFloatingBubble;
      await prefs.setBool('showFloatingBubble', _showFloatingBubble);
    }
    if (folderSyncIntervalSeconds != null) {
      _folderSyncIntervalSeconds = folderSyncIntervalSeconds.clamp(900, 604800);
      await prefs.setInt('folderSyncIntervalSeconds', _folderSyncIntervalSeconds);
    }
    _isConfigured = _backendUrl.isNotEmpty;
    notifyListeners();
  }

  /// Clear all settings
  Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _backendUrl = '';
    _useBackgroundService = true;
    _defaultTags = '';
    _defaultSafety = 'unsafe';
    _skipTagging = false;
    _pollingIntervalSeconds = 5;
    _notifyOnFolderSync = false;
    _deleteMediaAfterSync = false;
    _showPersistentNotification = true;
    _showFloatingBubble = false;
    _folderSyncIntervalSeconds = 900;
    _isAuthenticated = false;
    _username = null;
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

  /// Check if the settings are valid for making API calls (backend URL is set).
  bool get canMakeApiCalls => _backendUrl.isNotEmpty;

  /// All mobile settings to sync to the CCC backend (everything except backendUrl). Used when saving or on logout.
  Future<Map<String, dynamic>> getSyncablePreferences() async {
    final folders = await getScheduledFolders();
    return {
      'useBackgroundService': _useBackgroundService,
      'defaultTags': _defaultTags,
      'defaultSafety': _defaultSafety,
      'skipTagging': _skipTagging,
      'pollingIntervalSeconds': _pollingIntervalSeconds,
      'notifyOnFolderSync': _notifyOnFolderSync,
      'deleteMediaAfterSync': _deleteMediaAfterSync,
      'showPersistentNotification': _showPersistentNotification,
      'showFloatingBubble': _showFloatingBubble,
      'folderSyncIntervalSeconds': _folderSyncIntervalSeconds,
      'scheduledFolders': folders.map((f) => f.toJson()).toList(),
    };
  }

  /// Apply preferences fetched from the backend (e.g. after login). Persists to local storage.
  Future<void> applySyncedPreferences(Map<String, dynamic> prefs) async {
    final prefsStorage = await SharedPreferences.getInstance();
    if (prefs.containsKey('useBackgroundService')) {
      _useBackgroundService = prefs['useBackgroundService'] as bool? ?? _useBackgroundService;
      await prefsStorage.setBool('useBackgroundService', _useBackgroundService);
    }
    if (prefs.containsKey('defaultTags')) {
      _defaultTags = prefs['defaultTags'] as String? ?? _defaultTags;
      await prefsStorage.setString('defaultTags', _defaultTags);
    }
    if (prefs.containsKey('defaultSafety')) {
      _defaultSafety = prefs['defaultSafety'] as String? ?? _defaultSafety;
      await prefsStorage.setString('defaultSafety', _defaultSafety);
    }
    if (prefs.containsKey('skipTagging')) {
      _skipTagging = prefs['skipTagging'] as bool? ?? _skipTagging;
      await prefsStorage.setBool('skipTagging', _skipTagging);
    }
    if (prefs.containsKey('pollingIntervalSeconds')) {
      final v = prefs['pollingIntervalSeconds'];
      if (v is int) {
        _pollingIntervalSeconds = v.clamp(1, 3600);
        await prefsStorage.setInt('pollingIntervalSeconds', _pollingIntervalSeconds);
      }
    }
    if (prefs.containsKey('notifyOnFolderSync')) {
      _notifyOnFolderSync = prefs['notifyOnFolderSync'] as bool? ?? _notifyOnFolderSync;
      await prefsStorage.setBool('notifyOnFolderSync', _notifyOnFolderSync);
    }
    if (prefs.containsKey('deleteMediaAfterSync')) {
      _deleteMediaAfterSync = prefs['deleteMediaAfterSync'] as bool? ?? _deleteMediaAfterSync;
      await prefsStorage.setBool('deleteMediaAfterSync', _deleteMediaAfterSync);
    }
    if (prefs.containsKey('showPersistentNotification')) {
      _showPersistentNotification = prefs['showPersistentNotification'] as bool? ?? _showPersistentNotification;
      await prefsStorage.setBool('showPersistentNotification', _showPersistentNotification);
    }
    if (prefs.containsKey('showFloatingBubble')) {
      _showFloatingBubble = prefs['showFloatingBubble'] as bool? ?? _showFloatingBubble;
      await prefsStorage.setBool('showFloatingBubble', _showFloatingBubble);
    }
    if (prefs.containsKey('folderSyncIntervalSeconds')) {
      final v = prefs['folderSyncIntervalSeconds'];
      if (v is int) {
        _folderSyncIntervalSeconds = v.clamp(900, 604800);
        await prefsStorage.setInt('folderSyncIntervalSeconds', _folderSyncIntervalSeconds);
      }
    }
    if (prefs.containsKey('scheduledFolders')) {
      final list = prefs['scheduledFolders'];
      if (list is List<dynamic>) {
        final folders = list
            .map((e) => e is Map<String, dynamic> ? ScheduledFolder.fromJson(e) : null)
            .whereType<ScheduledFolder>()
            .toList();
        await setScheduledFolders(folders);
      }
    }
    notifyListeners();
  }

  /// Export all settings (except auth) to a JSON file in [directoryPath]. Returns the file path or null on failure.
  Future<String?> backupSettingsToDirectory(String directoryPath) async {
    try {
      final folders = await getScheduledFolders();
      final map = <String, dynamic>{
        'backendUrl': _backendUrl,
        'useBackgroundService': _useBackgroundService,
        'defaultTags': _defaultTags,
        'defaultSafety': _defaultSafety,
        'skipTagging': _skipTagging,
        'pollingIntervalSeconds': _pollingIntervalSeconds,
        'notifyOnFolderSync': _notifyOnFolderSync,
        'deleteMediaAfterSync': _deleteMediaAfterSync,
        'showPersistentNotification': _showPersistentNotification,
        'showFloatingBubble': _showFloatingBubble,
        'folderSyncIntervalSeconds': _folderSyncIntervalSeconds,
        'scheduledFolders': folders.map((f) => f.toJson()).toList(),
      };
      final date = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'szurucompanion_backup_$date.json';
      final file = File('$directoryPath${Platform.pathSeparator}$fileName');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
      return file.path;
    } catch (e) {
      debugPrint('[SettingsModel] backupSettingsToDirectory error: $e');
      return null;
    }
  }

  /// From backup JSON, determine which permissions to prompt for before restore (e.g. overlay if bubble was on, storage if folders enabled).
  Map<String, bool> checkPermissionsNeededFromBackupContent(String backupJson) {
    try {
      final map = jsonDecode(backupJson) as Map<String, dynamic>;
      final showFloatingBubble = map['showFloatingBubble'] as bool? ?? false;
      final list = map['scheduledFolders'] as List<dynamic>?;
      final hasEnabledFolders = list != null &&
          list.any((e) => e is Map && (e['enabled'] as bool? ?? true));
      return {
        'needsOverlayPermission': showFloatingBubble,
        'needsStoragePermission': hasEnabledFolders,
      };
    } catch (e) {
      debugPrint('[SettingsModel] checkPermissionsNeededFromBackupContent error: $e');
      return {'needsOverlayPermission': false, 'needsStoragePermission': false};
    }
  }

  /// Restore settings from a backup JSON string (does not restore auth tokens). Returns true on success.
  Future<bool> restoreSettingsFromJsonString(String backupJson) async {
    try {
      final map = jsonDecode(backupJson) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      if (map.containsKey('backendUrl')) await prefs.setString('backendUrl', map['backendUrl'] as String? ?? '');
      if (map.containsKey('useBackgroundService')) await prefs.setBool('useBackgroundService', map['useBackgroundService'] as bool? ?? true);
      if (map.containsKey('defaultTags')) await prefs.setString('defaultTags', map['defaultTags'] as String? ?? '');
      if (map.containsKey('defaultSafety')) await prefs.setString('defaultSafety', map['defaultSafety'] as String? ?? 'unsafe');
      if (map.containsKey('skipTagging')) await prefs.setBool('skipTagging', map['skipTagging'] as bool? ?? false);
      if (map.containsKey('pollingIntervalSeconds')) await prefs.setInt('pollingIntervalSeconds', map['pollingIntervalSeconds'] as int? ?? 5);
      if (map.containsKey('notifyOnFolderSync')) await prefs.setBool('notifyOnFolderSync', map['notifyOnFolderSync'] as bool? ?? false);
      if (map.containsKey('deleteMediaAfterSync')) await prefs.setBool('deleteMediaAfterSync', map['deleteMediaAfterSync'] as bool? ?? false);
      if (map.containsKey('showPersistentNotification')) await prefs.setBool('showPersistentNotification', map['showPersistentNotification'] as bool? ?? true);
      if (map.containsKey('showFloatingBubble')) await prefs.setBool('showFloatingBubble', map['showFloatingBubble'] as bool? ?? false);
      if (map.containsKey('folderSyncIntervalSeconds')) {
        final v = map['folderSyncIntervalSeconds'] as int? ?? 900;
        await prefs.setInt('folderSyncIntervalSeconds', v.clamp(900, 604800));
      }
      if (map.containsKey('scheduledFolders')) {
        final list = map['scheduledFolders'] as List<dynamic>?;
        if (list != null) {
          final folders = list
              .map((e) => e is Map<String, dynamic> ? ScheduledFolder.fromJson(e) : null)
              .whereType<ScheduledFolder>()
              .toList();
          await setScheduledFolders(folders);
        }
      }
      await loadSettings();
      return true;
    } catch (e) {
      debugPrint('[SettingsModel] restoreSettingsFromJsonString error: $e');
      return false;
    }
  }

  static const String _scheduledFoldersKey = 'scheduled_folders';
  static const String _pendingDeleteUrisKey = 'pending_delete_uris';
  static const String _lastFolderSyncTimestampKey = 'last_folder_sync_timestamp';
  static const String _lastFolderSyncCountKey = 'last_folder_sync_count';

  /// Get all scheduled folders
  Future<List<ScheduledFolder>> getScheduledFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_scheduledFoldersKey);
    if (jsonString == null) return [];
    
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => ScheduledFolder.fromJson(json)).toList();
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
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pendingDeleteUrisKey);
    final list = jsonString != null
        ? (jsonDecode(jsonString) as List<dynamic>).cast<String>()
        : <String>[];
    if (!list.contains(uri)) {
      list.add(uri);
      await prefs.setString(_pendingDeleteUrisKey, jsonEncode(list));
    }
  }

  /// Get URIs queued for deletion.
  Future<List<String>> getPendingDeleteUris() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pendingDeleteUrisKey);
    if (jsonString == null) return [];
    return (jsonDecode(jsonString) as List<dynamic>).cast<String>();
  }

  /// Remove a URI from the pending-delete queue.
  Future<void> removePendingDeleteUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_pendingDeleteUrisKey);
    if (jsonString == null) return;
    final list = (jsonDecode(jsonString) as List<dynamic>).cast<String>();
    list.remove(uri);
    await prefs.setString(_pendingDeleteUrisKey, jsonEncode(list));
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
}
