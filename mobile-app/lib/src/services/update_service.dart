import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/update_config.dart';
import 'notification_service.dart';

const _updaterChannel = MethodChannel('com.szurubooru.szuruqueue/updater');
const _currentVersionCodeKey = 'current_version_code';
const _skippedVersionCodeKey = 'skipped_update_version_code';
const _pendingInstallApkPathKey = 'pending_install_apk_path';
const _pendingUpdateVersionCodeKey = 'pending_update_version_code';
const _pendingUpdateVersionNameKey = 'pending_update_version_name';
const _pendingUpdateChangelogKey = 'pending_update_changelog';
const _pendingUpdateDownloadUrlKey = 'pending_update_download_url';
const _showBackendUpdateNoticeKey = 'show_backend_update_notice';

/// Remote version info from the update source (e.g. GitHub release + version.json).
class RemoteVersion {
  const RemoteVersion({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.changelog,
  });

  final int versionCode;
  final String versionName;
  final String downloadUrl;
  final String changelog;
}

/// Fetches the latest release that has mobile assets (version.json + APK). Uses list of releases
/// so CCC-only or ext-only tags do not become "latest". Safe to call from background isolate.
Future<RemoteVersion?> fetchLatestFromNetwork() async {
  try {
    final dio = Dio(BaseOptions(
      headers: {'Accept': 'application/vnd.github.v3+json'},
      validateStatus: (s) => s != null && s < 400,
    ));
    final response = await dio.get<List<dynamic>>(UpdateConfig.listReleasesUrl);
    if (response.data == null || response.statusCode != 200) return null;

    for (final r in response.data!) {
      final release = r is Map<String, dynamic> ? r : null;
      if (release == null) continue;
      final assets = release['assets'] as List<dynamic>?;
      if (assets == null || assets.isEmpty) continue;

      String? versionJsonUrl;
      String? apkUrl;
      for (final a in assets) {
        final name = a is Map ? a['name'] as String? : null;
        final url = a is Map ? a['browser_download_url'] as String? : null;
        if (name == 'version.json' && url != null) versionJsonUrl = url;
        if (name == 'SzuruCompanion.apk' && url != null) apkUrl = url;
      }
      if (versionJsonUrl == null || apkUrl == null) continue;

      final versionResponse = await dio.get<Map<String, dynamic>>(versionJsonUrl);
      if (versionResponse.data == null || versionResponse.statusCode != 200) continue;

      final data = versionResponse.data!;
      final versionCode = data['versionCode'];
      final versionName = data['versionName'];
      final changelog = data['changelog'];
      if (versionCode is! int || versionName is! String) continue;

      return RemoteVersion(
        versionCode: versionCode,
        versionName: versionName,
        downloadUrl: apkUrl,
        changelog: changelog is String ? changelog : '',
      );
    }
    return null;
  } catch (e, st) {
    debugPrint('[UpdateService] fetchLatestFromNetwork error: $e');
    debugPrint('[UpdateService] $st');
    return null;
  }
}

/// Runs in background isolate: fetches latest, compares to stored current version, writes pending update to prefs if newer.
/// Does not show notifications; on next app open the main flow will show the update notification.
/// Returns true if a pending update was written.
Future<bool> checkForUpdateInBackground() async {
  final prefs = await SharedPreferences.getInstance();
  final currentCode = prefs.getInt(_currentVersionCodeKey);
  if (currentCode == null) return false;

  final remote = await fetchLatestFromNetwork();
  if (remote == null || remote.versionCode <= currentCode) return false;

  final skipped = prefs.getInt(_skippedVersionCodeKey);
  if (skipped != null && remote.versionCode <= skipped) return false;

  prefs.setInt(_pendingUpdateVersionCodeKey, remote.versionCode);
  prefs.setString(_pendingUpdateVersionNameKey, remote.versionName);
  prefs.setString(_pendingUpdateChangelogKey, remote.changelog);
  prefs.setString(_pendingUpdateDownloadUrlKey, remote.downloadUrl);
  return true;
}

/// Orchestrates update check, skip state, download, and install.
class UpdateService {
  UpdateService._({required Dio dio, required SharedPreferences prefs})
      : _dio = dio,
        _prefs = prefs;

  static UpdateService? _instance;

  static Future<UpdateService> getInstance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    _instance = UpdateService._(
      dio: Dio(BaseOptions(
        headers: {'Accept': 'application/vnd.github.v3+json'},
        validateStatus: (s) => s != null && s < 400,
      )),
      prefs: prefs,
    );
    return _instance!;
  }

  final Dio _dio;
  final SharedPreferences _prefs;

  Future<PackageInfo> getCurrentVersion() => PackageInfo.fromPlatform();

  /// Saves current app versionCode to SharedPreferences so the background update check can compare.
  Future<void> saveCurrentVersionToPrefs() async {
    final info = await PackageInfo.fromPlatform();
    final code = int.tryParse(info.buildNumber) ?? 0;
    await _prefs.setInt(_currentVersionCodeKey, code);
  }

  /// Fetches the latest release that has mobile assets (version.json + APK). Ignores CCC-only or ext-only releases.
  Future<RemoteVersion?> getLatestVersion() async {
    try {
      final response = await _dio.get<List<dynamic>>(UpdateConfig.listReleasesUrl);
      if (response.data == null || response.statusCode != 200) return null;

      for (final r in response.data!) {
        final release = r is Map<String, dynamic> ? r : null;
        if (release == null) continue;
        final assets = release['assets'] as List<dynamic>?;
        if (assets == null || assets.isEmpty) continue;

        String? versionJsonUrl;
        String? apkUrl;
        for (final a in assets) {
          final name = a is Map ? a['name'] as String? : null;
          final url = a is Map ? a['browser_download_url'] as String? : null;
          if (name == 'version.json' && url != null) versionJsonUrl = url;
          if (name == 'SzuruCompanion.apk' && url != null) apkUrl = url;
        }
        if (versionJsonUrl == null || apkUrl == null) continue;

        final versionResponse = await _dio.get<Map<String, dynamic>>(versionJsonUrl);
        if (versionResponse.data == null || versionResponse.statusCode != 200) continue;

        final data = versionResponse.data!;
        final versionCode = data['versionCode'];
        final versionName = data['versionName'];
        final changelog = data['changelog'];
        if (versionCode is! int || versionName is! String) continue;

        return RemoteVersion(
          versionCode: versionCode,
          versionName: versionName,
          downloadUrl: apkUrl,
          changelog: changelog is String ? changelog : '',
        );
      }
      return null;
    } catch (e, st) {
      debugPrint('[UpdateService] getLatestVersion error: $e');
      debugPrint('[UpdateService] $st');
      return null;
    }
  }

  /// True if a remote version is newer than current and not skipped (unless [ignoreSkipped]).
  Future<bool> shouldPromptUpdate({
    required int currentVersionCode,
    required RemoteVersion remote,
    bool ignoreSkipped = false,
  }) async {
    if (remote.versionCode <= currentVersionCode) return false;
    if (ignoreSkipped) return true;
    final skipped = _prefs.getInt(_skippedVersionCodeKey);
    return skipped == null || remote.versionCode > skipped;
  }

  void markVersionSkipped(int versionCode) {
    _prefs.setInt(_skippedVersionCodeKey, versionCode);
  }

  void clearSkippedVersion() {
    _prefs.remove(_skippedVersionCodeKey);
  }

  void setPendingUpdate({
    required int versionCode,
    required String versionName,
    required String changelog,
    required String downloadUrl,
  }) {
    _prefs.setInt(_pendingUpdateVersionCodeKey, versionCode);
    _prefs.setString(_pendingUpdateVersionNameKey, versionName);
    _prefs.setString(_pendingUpdateChangelogKey, changelog);
    _prefs.setString(_pendingUpdateDownloadUrlKey, downloadUrl);
  }

  bool get hasPendingUpdate =>
      _prefs.containsKey(_pendingUpdateVersionCodeKey) &&
      _prefs.containsKey(_pendingUpdateDownloadUrlKey);

  RemoteVersion? getPendingUpdate() {
    final code = _prefs.getInt(_pendingUpdateVersionCodeKey);
    final name = _prefs.getString(_pendingUpdateVersionNameKey);
    final changelog = _prefs.getString(_pendingUpdateChangelogKey);
    final url = _prefs.getString(_pendingUpdateDownloadUrlKey);
    if (code == null || name == null || url == null) return null;
    return RemoteVersion(
      versionCode: code,
      versionName: name,
      downloadUrl: url,
      changelog: changelog ?? '',
    );
  }

  void clearPendingUpdate() {
    _prefs.remove(_pendingUpdateVersionCodeKey);
    _prefs.remove(_pendingUpdateVersionNameKey);
    _prefs.remove(_pendingUpdateChangelogKey);
    _prefs.remove(_pendingUpdateDownloadUrlKey);
  }

  bool get shouldShowBackendUpdateNotice =>
      _prefs.getBool(_showBackendUpdateNoticeKey) ?? true;

  void setShowBackendUpdateNotice(bool value) {
    _prefs.setBool(_showBackendUpdateNoticeKey, value);
  }

  void markBackendUpdateNoticeShown() {
    _prefs.setBool(_showBackendUpdateNoticeKey, false);
  }

  String? get pendingInstallApkPath => _prefs.getString(_pendingInstallApkPathKey);

  void _setPendingInstallApkPath(String? path) {
    if (path == null) {
      _prefs.remove(_pendingInstallApkPathKey);
    } else {
      _prefs.setString(_pendingInstallApkPathKey, path);
    }
  }

  /// Result of an update check for UI (manual check).
  static const int checkResultNoUpdate = 0;
  static const int checkResultUpdateAvailable = 1;
  static const int checkResultError = 2;

  /// Runs update check: if a newer version is available and not skipped (or [ignoreSkipped]),
  /// stores pending update and shows "Update available" notification (unless [isManualCheck] and caller will show dialog).
  /// Returns [checkResultNoUpdate], [checkResultUpdateAvailable], or [checkResultError] when [isManualCheck] is true; otherwise null.
  Future<int?> checkAndNotifyUpdate({
    bool ignoreSkipped = false,
    bool isManualCheck = false,
  }) async {
    final remote = await getLatestVersion();
    if (remote == null) return isManualCheck ? checkResultError : null;

    final info = await getCurrentVersion();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;
    final shouldPrompt = await shouldPromptUpdate(
      currentVersionCode: currentCode,
      remote: remote,
      ignoreSkipped: ignoreSkipped,
    );

    if (!shouldPrompt) {
      return isManualCheck ? checkResultNoUpdate : null;
    }

    setPendingUpdate(
      versionCode: remote.versionCode,
      versionName: remote.versionName,
      changelog: remote.changelog,
      downloadUrl: remote.downloadUrl,
    );
    if (!isManualCheck) {
      await NotificationService.instance.showUpdateAvailable(
        versionName: remote.versionName,
        changelog: remote.changelog,
      );
    }
    return isManualCheck ? checkResultUpdateAvailable : null;
  }

  /// Handles notification tap for the update flow. Call from NotificationService response callback.
  Future<void> handleNotificationTap(String? payload) async {
    if (payload == null) return;
    switch (payload) {
      case 'update_available':
        await startDownload();
        break;
      case 'ready_to_install':
        await _launchInstall();
        break;
    }
  }

  /// Downloads the pending update and shows progress; on success stores path and shows "Tap to install".
  Future<void> startDownload() async {
    final remote = getPendingUpdate();
    if (remote == null) return;

    try {
      final dir = await getTemporaryDirectory();
      final apkFile = File('${dir.path}/SzuruCompanion_update.apk');

      await NotificationService.instance.showUpdateDownloading(0);

      await _dio.download(
        remote.downloadUrl,
        apkFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final percent = (received / total * 100).round().clamp(0, 100);
            NotificationService.instance
                .updateUpdateDownloadProgress(percent)
                .ignore();
          }
        },
      );

      if (!await apkFile.exists()) {
        debugPrint('[UpdateService] Download failed: file missing');
        return;
      }

      _setPendingInstallApkPath(apkFile.path);
      await NotificationService.instance.showUpdateReadyToInstall();
    } catch (e, st) {
      debugPrint('[UpdateService] startDownload error: $e');
      debugPrint('[UpdateService] $st');
    }
  }

  Future<void> _launchInstall() async {
    final path = pendingInstallApkPath;
    if (path == null || path.isEmpty) return;
    setShowBackendUpdateNotice(true);
    try {
      await _updaterChannel.invokeMethod<void>('installApk', path);
    } on PlatformException catch (e) {
      debugPrint('[UpdateService] installApk error: ${e.message}');
      setShowBackendUpdateNotice(false);
    } finally {
      _setPendingInstallApkPath(null);
    }
  }
}
