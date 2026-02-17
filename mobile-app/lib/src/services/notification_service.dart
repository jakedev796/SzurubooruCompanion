import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service for showing local notifications
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(settings: settings);
  }

  Future<void> showUploadSuccess(String url) async {
    const androidDetails = AndroidNotificationDetails(
      'szuruqueue',
      'SzuruCompanion Notifications',
      channelDescription: 'Notifications for upload queue',
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

  /// Simple one-line upload error (e.g. folder scan, background enqueue).
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

  /// Expandable upload-failed notification: title "Upload Failed - {websiteName}",
  /// expanded body shows jobId and fullDomain on separate lines.
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

  Future<void> showFolderSyncComplete(int filesUploaded) async {
    const androidDetails = AndroidNotificationDetails(
      'folder_sync',
      'SzuruCompanion Notifications',
      channelDescription: 'Folder sync notifications',
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
}
