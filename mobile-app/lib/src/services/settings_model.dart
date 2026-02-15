import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scheduled_folder.dart';

/// Settings model for the SzuruQueue app.
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

  String get backendUrl => _backendUrl;
  String get apiKey => _apiKey;
  bool get useBackgroundService => _useBackgroundService;
  String get defaultTags => _defaultTags;
  String get defaultSafety => _defaultSafety;
  bool get skipTagging => _skipTagging;
  bool get isConfigured => _isConfigured;
  int get pollingIntervalSeconds => _pollingIntervalSeconds;

  /// Load settings from persistent storage
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString('backendUrl') ?? '';
    _apiKey = prefs.getString('apiKey') ?? '';
    _useBackgroundService = prefs.getBool('useBackgroundService') ?? true;
    _defaultTags = prefs.getString('defaultTags') ?? '';
    _defaultSafety = prefs.getString('defaultSafety') ?? 'unsafe';
    _skipTagging = prefs.getBool('skipTagging') ?? false;
    _pollingIntervalSeconds = prefs.getInt('pollingIntervalSeconds') ?? 5;
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
    
    _isConfigured = _backendUrl.isNotEmpty;
    notifyListeners();
  }

  /// Clear all settings
  Future<void> clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    _backendUrl = '';
    _apiKey = '';
    _useBackgroundService = true;
    _defaultTags = '';
    _defaultSafety = 'unsafe';
    _skipTagging = false;
    _pollingIntervalSeconds = 5;
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

  // Key for storing scheduled folders
  static const String _scheduledFoldersKey = 'scheduled_folders';

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
}
