import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth.dart';
import 'backend_client.dart';
import 'notification_service.dart';
import 'settings_model.dart';

/// Background service that maintains SSE connection and shows notifications for failed jobs.
/// Runs in the same process as the foreground service, which keeps the process alive
/// so SSE works even when app UI is closed.
class SseBackgroundService {
  static final SseBackgroundService instance = SseBackgroundService._();
  SseBackgroundService._();

  BackendClient? _backendClient;
  StreamSubscription<JobUpdate>? _jobUpdateSubscription;
  StreamSubscription<SseConnectionState>? _sseStateSubscription;
  Timer? _reconnectTimer;
  String? _lastBackendUrl;
  DateTime? _lastFailedJobCheck;
  bool _isRunning = false;
  int _reconnectDelaySeconds = 3;

  /// Optional callback invoked when SSE connection state changes, so the persistent
  /// notification can be updated (e.g. from [startCompanionForegroundService]).
  static void Function(SseConnectionState)? notificationUpdater;

  /// Start the background SSE service.
  /// This will maintain an SSE connection and show notifications for failed jobs.
  /// The foreground service keeps the process alive so this works even when app UI is closed.
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('[SseBackgroundService] Already running');
      return;
    }

    try {
      debugPrint('[SseBackgroundService] Starting background SSE service...');
      await _connectSse();
      _isRunning = true;
      debugPrint('[SseBackgroundService] Background SSE service started');
    } catch (e, stackTrace) {
      debugPrint('[SseBackgroundService] Failed to start: $e');
      debugPrint('[SseBackgroundService] Stack trace: $stackTrace');
      _isRunning = false;
    }
  }

  /// Stop the background SSE service.
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    try {
      debugPrint('[SseBackgroundService] Stopping background SSE service...');
      _disconnectSse();
      _isRunning = false;
      notificationUpdater = null;
      debugPrint('[SseBackgroundService] Background SSE service stopped');
    } catch (e) {
      debugPrint('[SseBackgroundService] Error stopping: $e');
    }
  }

  Future<void> _connectSse() async {
    try {
      final settings = SettingsModel();
      await settings.loadSettings();
      final serverUrl = settings.backendUrl;
      if (serverUrl.isEmpty || !settings.canMakeApiCalls) {
        debugPrint('[SseBackgroundService] Backend not configured, skipping SSE');
        return;
      }

      // Only reconnect if URL changed
      if (serverUrl == _lastBackendUrl && _backendClient != null) {
        return;
      }

      // Disconnect existing connection
      _disconnectSse();

      // Create new client
      _backendClient = BackendClient(baseUrl: serverUrl);

      // Load auth tokens
      final prefs = await SharedPreferences.getInstance();
      final authJson = prefs.getString('auth_tokens');
      if (authJson != null) {
        try {
          final tokens = AuthTokens.fromJson(
            jsonDecode(authJson) as Map<String, dynamic>,
          );
          _backendClient!.setAccessToken(tokens.accessToken);
        } catch (e) {
          debugPrint('[SseBackgroundService] Failed to load auth: $e');
        }
      }

      _lastBackendUrl = serverUrl;

      // Connect to SSE
      _backendClient!.connectSse(autoReconnect: true);

      // Listen to connection state and reconnect when disconnected
      _sseStateSubscription = _backendClient!.sseStateStream.listen((state) {
        notificationUpdater?.call(state);
        if (state == SseConnectionState.connected) {
          _reconnectDelaySeconds = 3;
        }
        if (state == SseConnectionState.disconnected && _isRunning) {
          _reconnectTimer?.cancel();
          final delay = _reconnectDelaySeconds;
          _reconnectDelaySeconds = _reconnectDelaySeconds >= 60 ? 60 : _reconnectDelaySeconds * 2;
          _reconnectTimer = Timer(Duration(seconds: delay), () {
            _reconnectTimer = null;
            _disconnectSse();
            _connectSse();
          });
        }
      });

      // Listen to job updates
      _jobUpdateSubscription = _backendClient!.jobUpdateStream.listen((update) {
        _handleJobUpdate(update);
      });

      debugPrint('[SseBackgroundService] SSE connected to $serverUrl');
    } catch (e) {
      debugPrint('[SseBackgroundService] Error connecting SSE: $e');
    }
  }

  void _disconnectSse() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sseStateSubscription?.cancel();
    _sseStateSubscription = null;
    _jobUpdateSubscription?.cancel();
    _jobUpdateSubscription = null;
    _backendClient?.disconnectSse();
    _backendClient = null;
    _lastBackendUrl = null;
    _reconnectDelaySeconds = 3;
    debugPrint('[SseBackgroundService] SSE disconnected');
  }

  // Handle job updates from SSE
  Future<void> _handleJobUpdate(JobUpdate update) async {
    try {
      if (_backendClient == null) return;

      // Fetch full job details to check if it just failed
      final job = await _backendClient!.fetchJob(update.jobId);
      if (job == null) return;

      final isFailed = job.status.toLowerCase() == 'failed' &&
          job.errorMessage != null &&
          job.errorMessage!.isNotEmpty;

      // Check if this is a newly failed job (updated recently)
      // Only notify if retries are exhausted (retriesExhausted == true)
      if (isFailed && update.retriesExhausted == true) {
        final now = DateTime.now();
        final shouldNotify = _lastFailedJobCheck == null ||
            job.updatedAt.isAfter(_lastFailedJobCheck!);

        if (shouldNotify) {
          String websiteName;
          String fullDomain;
          if (job.sources.isNotEmpty) {
            final url = job.sources.first;
            final uri = Uri.tryParse(url);
            websiteName = uri != null
                ? (uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host)
                : url;
            fullDomain = url;
          } else {
            websiteName = job.displayName != 'Job ${job.id}'
                ? job.displayName
                : 'Processing';
            fullDomain = '';
          }
          final notificationId = job.id.hashCode.abs() % 100000;
          await NotificationService.instance.showUploadErrorExpanded(
            websiteName: websiteName,
            jobId: job.id,
            fullDomain: fullDomain,
            notificationId: notificationId,
          );
          debugPrint('[SseBackgroundService] Notified about failed job: ${job.id}');
          _lastFailedJobCheck = now;
        }
      }
    } catch (e) {
      debugPrint('[SseBackgroundService] Error handling job update: $e');
    }
  }

  bool get isRunning => _isRunning;
}
