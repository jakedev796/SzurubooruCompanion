import 'package:flutter/services.dart';

/// Handles Android share intent (MethodChannel) for receiving shared URLs/files.
class ShareIntentService {
  ShareIntentService._();

  static const MethodChannel _channel = MethodChannel(
    'com.szurubooru.szuruqueue/share',
  );

  static Future<Map<String, dynamic>?> getInitialShare() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getInitialShare',
    );
    return raw?.cast<String, dynamic>();
  }

  static Future<void> clearInitialShare() async {
    await _channel.invokeMethod('clearInitialShare');
  }

  static void setupMethodCallHandler(Function(Map<String, dynamic>) onShare) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'share') {
        final data = <String, dynamic>{};
        if (call.arguments is Map) {
          (call.arguments as Map).forEach((key, value) {
            data[key.toString()] = value;
          });
        }
        onShare(data);
      }
    });
  }
}
