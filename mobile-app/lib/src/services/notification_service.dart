import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification ID for the single in-app update flow (updated in place).
const int kUpdateNotificationId = 100;

/// Service for showing local notifications
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// [onNotificationResponse] is called when user taps a notification (e.g. update flow).
  Future<void> init({
    void Function(NotificationResponse response)? onNotificationResponse,
  }) async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onNotificationResponse,
    );
  }

  /// Upload queued success. Uses a dedicated channel so it does not pool under the persistent status notification.
  Future<void> showUploadSuccess(String url) async {
    const androidDetails = AndroidNotificationDetails(
      'upload_sync',
      'Upload & sync',
      channelDescription: 'Upload queued and folder sync complete',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      id: 0,
      title: 'Upload Queued',
      body: url,
      notificationDetails: details,
    );
  }

  /// Dedicated error channel; does not pool under the persistent status notification.
  Future<void> showUploadError(String error) async {
    const androidDetails = AndroidNotificationDetails(
      'job_failures',
      'Job failure notifications',
      channelDescription: 'Notifications for failed uploads and processing errors',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      id: 1,
      title: 'Upload Failed',
      body: error,
      notificationDetails: details,
    );
  }

  /// Expandable upload-failed notification (same dedicated error channel; does not pool under persistent).
  /// [notificationId] should be unique per job (e.g. jobId.hashCode) so multiple failures don't overwrite.
  Future<void> showUploadErrorExpanded({
    required String websiteName,
    required String jobId,
    required String fullDomain,
    required int notificationId,
  }) async {
    final bigText = fullDomain.isEmpty ? jobId : '$jobId\n$fullDomain';
    final style = BigTextStyleInformation(
      bigText,
      contentTitle: 'Upload Failed - $websiteName',
    );
    final androidDetails = AndroidNotificationDetails(
      'job_failures',
      'Job failure notifications',
      channelDescription: 'Notifications for failed uploads and processing errors',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: style,
    );
    final details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      id: notificationId,
      title: 'Upload Failed - $websiteName',
      body: '', // Expanded content (jobId, fullDomain) shown via BigTextStyle
      notificationDetails: details,
    );
  }

  /// Folder sync complete. Same channel as upload success so these events stay separate from the persistent status notification.
  Future<void> showFolderSyncComplete(int filesUploaded) async {
    const androidDetails = AndroidNotificationDetails(
      'upload_sync',
      'Upload & sync',
      channelDescription: 'Upload queued and folder sync complete',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      id: 2,
      title: 'Folder Sync Complete',
      body: filesUploaded == 1
          ? '1 file uploaded'
          : '$filesUploaded files uploaded',
      notificationDetails: details,
    );
  }

  /// Request notification permission (Android 13+). Returns true if granted, false if denied, null if not applicable.
  Future<bool?> requestNotificationPermission() async {
    return _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static const _updateChannelId = 'app_updates';
  static const _updateChannelName = 'App updates';
  static const _updateChannelDescription =
      'Update available and download progress';

  /// Update available: tap to start download. Uses BigText for changelog.
  Future<void> showUpdateAvailable({
    required String versionName,
    required String changelog,
  }) async {
    final style = BigTextStyleInformation(
      changelog.isNotEmpty ? changelog : 'Tap to download.',
      contentTitle: 'Update available: $versionName',
    );
    final androidDetails = AndroidNotificationDetails(
      _updateChannelId,
      _updateChannelName,
      channelDescription: _updateChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: style,
    );
    final details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      id: kUpdateNotificationId,
      title: 'Update available: $versionName',
      body: changelog.isNotEmpty ? changelog : 'Tap to download.',
      notificationDetails: details,
      payload: 'update_available',
    );
  }

  /// Download in progress; [progressPercent] 0–100.
  Future<void> showUpdateDownloading(int progressPercent) async {
    const androidDetails = AndroidNotificationDetails(
      _updateChannelId,
      _updateChannelName,
      channelDescription: _updateChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
    );
    final details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      id: kUpdateNotificationId,
      title: 'Downloading update',
      body: '$progressPercent%',
      notificationDetails: details,
      payload: 'downloading',
    );
  }

  /// Update download progress (update same notification).
  Future<void> updateUpdateDownloadProgress(int progressPercent) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _updateChannelId,
        _updateChannelName,
        channelDescription: _updateChannelDescription,
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: progressPercent,
      ),
    );
    await _notifications.show(
      id: kUpdateNotificationId,
      title: 'Downloading update',
      body: '$progressPercent%',
      notificationDetails: details,
      payload: 'downloading',
    );
  }

  /// Download complete; tap to install.
  Future<void> showUpdateReadyToInstall() async {
    const androidDetails = AndroidNotificationDetails(
      _updateChannelId,
      _updateChannelName,
      channelDescription: _updateChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      id: kUpdateNotificationId,
      title: 'Update ready',
      body: 'Tap to install',
      notificationDetails: details,
      payload: 'ready_to_install',
    );
  }

  /// Dismiss the update notification.
  Future<void> dismissUpdateNotification() async {
    await _notifications.cancel(id: kUpdateNotificationId);
  }
}
