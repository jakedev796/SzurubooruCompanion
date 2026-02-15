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

  Future<void> showUploadError(String error) async {
    const androidDetails = AndroidNotificationDetails(
      'szuruqueue',
      'SzuruCompanion Notifications',
      channelDescription: 'Notifications for upload queue',
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

  static const int _statusNotificationId = 100;

  /// Channel for the persistent status notification (connection, jobs, folder sync).
  static const String _statusChannelId = 'status';
  static const String _statusChannelName = 'SzuruCompanion Notifications';

  static AndroidNotificationDetails get _statusNotificationDetails =>
      const AndroidNotificationDetails(
        _statusChannelId,
        _statusChannelName,
        channelDescription: 'App status and folder sync',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
      );

  /// Show or update the persistent status notification (connectivity only).
  Future<void> updateStatusNotification({required String connectionText}) async {
    final details = NotificationDetails(android: _statusNotificationDetails);
    await _notifications.show(
      id: _statusNotificationId,
      title: 'SzuruCompanion',
      body: connectionText,
      notificationDetails: details,
    );
  }

  /// Show the status notification with a single body (e.g. when first enabling folder sync).
  Future<void> showStatusNotification({String? body}) async {
    final details = NotificationDetails(android: _statusNotificationDetails);
    await _notifications.show(
      id: _statusNotificationId,
      title: 'SzuruCompanion',
      body: body ?? 'Folder sync on',
      notificationDetails: details,
    );
  }

  /// Remove the persistent status notification.
  Future<void> cancelStatusNotification() async {
    await _notifications.cancel(id: _statusNotificationId);
  }

  /// Request notification permission (Android 13+). Returns true if granted, false if denied, null if not applicable.
  Future<bool?> requestNotificationPermission() async {
    return _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
}
