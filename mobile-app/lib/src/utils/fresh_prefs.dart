import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences with its cache refreshed from disk.
///
/// Each isolate caches preferences on first load and never sees writes made
/// by another isolate (scheduled folder sync runs in a WorkManager isolate,
/// the native service writes directly). Use this for any state both sides
/// read and write, or stale values get written back over newer ones.
Future<SharedPreferences> freshPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs;
}
