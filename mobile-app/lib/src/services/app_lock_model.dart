import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyEnabled = 'app_lock_enabled';

/// Manages optional app lock using native system authentication (device PIN,
/// pattern, password, or fingerprint). Android only; no-op on Darwin/Windows.
/// Off by default.
class AppLockModel extends ChangeNotifier {
  AppLockModel() {
    _load();
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final LocalAuthentication _auth = LocalAuthentication();
  bool _isEnabled = false;
  bool _loaded = false;

  bool get isEnabled => _isEnabled;
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_keyEnabled) ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// Whether the device can authenticate (has lock or biometric configured).
  /// Returns false on non-Android (Darwin, Windows).
  Future<bool> isDeviceSupported() async {
    if (!_isAndroid) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('[AppLockModel] isDeviceSupported error: $e');
      return false;
    }
  }

  /// Trigger native system authentication. Returns true on success.
  /// No-op on non-Android (Darwin, Windows); returns false.
  Future<bool> authenticate() async {
    if (!_isAndroid) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock SzuruCompanion',
        options: const AuthenticationOptions(
          biometricOnly: false,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('[AppLockModel] authenticate PlatformException: ${e.code}');
      return false;
    } catch (e, stack) {
      debugPrint('[AppLockModel] authenticate error: $e');
      if (kDebugMode) debugPrint(stack.toString());
      return false;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_isEnabled == value) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    _isEnabled = value;
    notifyListeners();
  }
}
