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
}
