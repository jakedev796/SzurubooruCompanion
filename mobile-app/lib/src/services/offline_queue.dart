import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_client.dart';
import 'notification_service.dart';

class OfflineQueueEntry {
  final String type; // 'url' or 'file'
  final Map<String, dynamic> payload;
  final int retryCount;
  final int createdAt; // epoch seconds

  OfflineQueueEntry({
    required this.type,
    required this.payload,
    this.retryCount = 0,
    required this.createdAt,
  });

  OfflineQueueEntry copyWith({int? retryCount}) => OfflineQueueEntry(
    type: type,
    payload: payload,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'payload': payload,
    'retryCount': retryCount,
    'createdAt': createdAt,
  };

  factory OfflineQueueEntry.fromJson(Map<String, dynamic> json) =>
      OfflineQueueEntry(
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        retryCount: json['retryCount'] as int? ?? 0,
        createdAt: json['createdAt'] as int,
      );
}

/// Persists failed uploads for retry when connectivity returns.
class OfflineQueue {
  static const String _key = 'offline_queue';
  static const int maxRetries = 3;
  static const int maxAgeDays = 7;

  static Future<void> enqueueUrl({
    required String url,
    required List<String> tags,
    required String safety,
    bool? skipTagging,
  }) async {
    final entry = OfflineQueueEntry(
      type: 'url',
      payload: {
        'url': url,
        'tags': tags,
        'safety': safety,
        if (skipTagging != null) 'skipTagging': skipTagging,
      },
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await _addEntry(entry);
    debugPrint('[OfflineQueue] Queued URL for retry: $url');
  }

  static Future<void> enqueueFile({
    required String filePath,
    required List<String> tags,
    required String safety,
    bool? skipTagging,
  }) async {
    final entry = OfflineQueueEntry(
      type: 'file',
      payload: {
        'filePath': filePath,
        'tags': tags,
        'safety': safety,
        if (skipTagging != null) 'skipTagging': skipTagging,
      },
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await _addEntry(entry);
    debugPrint('[OfflineQueue] Queued file for retry: $filePath');
  }

  /// Process all queued entries. Returns count of successfully processed items.
  static Future<int> flush(BackendClient client) async {
    final entries = await _getEntries();
    if (entries.isEmpty) return 0;

    debugPrint('[OfflineQueue] Flushing ${entries.length} queued entries');
    int processed = 0;
    final remaining = <OfflineQueueEntry>[];

    for (final entry in entries) {
      try {
        bool success = false;
        if (entry.type == 'url') {
          final url = entry.payload['url'] as String;
          final tags = (entry.payload['tags'] as List<dynamic>).cast<String>();
          final safety = entry.payload['safety'] as String;
          final skipTagging = entry.payload['skipTagging'] as bool?;
          await client.enqueueFromUrl(
            url: url,
            tags: tags,
            safety: safety,
            skipTagging: skipTagging,
          );
          success = true;
        } else if (entry.type == 'file') {
          final filePath = entry.payload['filePath'] as String;
          final tags = (entry.payload['tags'] as List<dynamic>).cast<String>();
          final safety = entry.payload['safety'] as String;
          final skipTagging = entry.payload['skipTagging'] as bool?;
          final file = File(filePath);
          if (await file.exists()) {
            final result = await client.enqueueFromFile(
              file: file,
              tags: tags,
              safety: safety,
              skipTagging: skipTagging,
            );
            success = result.error == null;
          } else {
            debugPrint('[OfflineQueue] File no longer exists: $filePath');
            success = true; // Remove from queue
          }
        }

        if (success) {
          processed++;
        } else {
          throw Exception('Upload returned error');
        }
      } catch (e) {
        debugPrint('[OfflineQueue] Failed to process entry: $e');
        final newCount = entry.retryCount + 1;
        if (newCount >= maxRetries) {
          debugPrint('[OfflineQueue] Max retries reached, dropping entry');
          final label = entry.type == 'url'
              ? entry.payload['url'] as String
              : entry.payload['filePath'] as String;
          await NotificationService.instance.showUploadError(
            'Permanently failed after $maxRetries retries: $label',
          );
        } else {
          remaining.add(entry.copyWith(retryCount: newCount));
        }
      }
    }

    await _setEntries(remaining);
    debugPrint('[OfflineQueue] Flush complete: $processed processed, ${remaining.length} remaining');
    return processed;
  }

  /// Remove entries older than maxAgeDays.
  static Future<void> prune() async {
    final entries = await _getEntries();
    final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - (maxAgeDays * 86400);
    final fresh = entries.where((e) => e.createdAt > cutoff).toList();
    if (fresh.length < entries.length) {
      debugPrint('[OfflineQueue] Pruned ${entries.length - fresh.length} stale entries');
      await _setEntries(fresh);
    }
  }

  static Future<List<OfflineQueueEntry>> _getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => OfflineQueueEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[OfflineQueue] Error reading queue: $e');
      return [];
    }
  }

  static Future<void> _setEntries(List<OfflineQueueEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    if (entries.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(entries.map((e) => e.toJson()).toList()));
    }
  }

  static Future<void> _addEntry(OfflineQueueEntry entry) async {
    final entries = await _getEntries();
    entries.add(entry);
    await _setEntries(entries);
  }
}
