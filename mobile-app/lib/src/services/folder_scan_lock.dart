import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-isolate mutex for the folder sync pipeline.
///
/// Why this exists: manual Sync Now runs in the main isolate while scheduled
/// folder sync runs in a WorkManager background isolate. The per-widget
/// `_isSyncingFolders` flag doesn't help across isolates, and two concurrent
/// scans of the same folder upload every file twice. SharedPreferences is the
/// only sync primitive both isolates share, so we use it as a coarse mutex
/// with a TTL so a crashed scan can't wedge sync forever.
class FolderScanLock {
  static const String _key = 'folder_scan_lock';
  static const int _ttlSeconds = 30 * 60;

  /// Try to acquire the lock. Returns true if acquired; caller must release.
  static Future<bool> acquire(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (existing != null) {
      try {
        final map = jsonDecode(existing) as Map<String, dynamic>;
        final ts = map['timestamp'] as int? ?? 0;
        if (now - ts < _ttlSeconds) {
          debugPrint(
              '[FolderScanLock] Held by ${map['owner']} for ${now - ts}s; $owner backing off');
          return false;
        }
        debugPrint(
            '[FolderScanLock] Stale lock from ${map['owner']} (${now - ts}s old); $owner overriding');
      } catch (_) {
        // Malformed entry; treat as free.
      }
    }

    await prefs.setString(
      _key,
      jsonEncode({'owner': owner, 'timestamp': now}),
    );
    return true;
  }

  /// Release the lock if we still own it. Safe to call even if we don't.
  static Future<void> release(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing == null) return;
    try {
      final map = jsonDecode(existing) as Map<String, dynamic>;
      if (map['owner'] == owner) {
        await prefs.remove(_key);
      }
    } catch (_) {
      await prefs.remove(_key);
    }
  }
}
