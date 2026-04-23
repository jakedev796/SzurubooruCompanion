import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Small helper around connectivity_plus used to gate automatic uploads
/// (scheduled folder sync, offline-queue flush) when the user has turned on
/// "Upload only on WiFi".
///
/// Ethernet is treated as equivalent to WiFi (unmetered, same user intent).
/// Manual user actions should not consult this gate — if the user explicitly
/// taps "Sync Now", the preference is intentionally bypassed.
class NetworkGate {
  static Future<bool> isOnWifiOrEthernet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (e) {
      // Fail open: if we can't check, assume OK rather than blocking uploads forever.
      debugPrint('[NetworkGate] Connectivity check failed, allowing upload: $e');
      return true;
    }
  }

  /// True if an automatic upload may proceed given the wifi-only preference.
  static Future<bool> canAutoUpload({required bool wifiOnly}) async {
    if (!wifiOnly) return true;
    return await isOnWifiOrEthernet();
  }
}
