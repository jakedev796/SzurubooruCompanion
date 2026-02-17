import 'dart:async';

import 'package:flutter/material.dart';

import '../models/job.dart';
import 'backend_client.dart';
import 'notification_service.dart';
import 'settings_model.dart';

/// Application state management class.
/// 
/// Manages:
/// - Job list and filtering
/// - Statistics
/// - SSE connection for real-time updates
/// - Backend client configuration
class AppState extends ChangeNotifier {
  AppState(this.settings) {
    _previousBackendUrl = settings.backendUrl;
    _initializeSse();
    settings.addListener(_onSettingsChanged);
    if (settings.isConfigured) {
      refreshAll();
    }
  }

  final SettingsModel settings;
  BackendClient? _backendClient;
  StreamSubscription<SseConnectionState>? _sseStateSubscription;
  StreamSubscription<JobUpdate>? _jobUpdateSubscription;
  
  // Track previous URL to avoid unnecessary SSE reconnections
  String _previousBackendUrl = '';
  
  bool isLoadingJobs = false;
  bool isLoadingStats = false;
  List<Job> jobs = [];
  String? booruUrl;
  List<String> szuruUsers = [];
  Map<String, int> stats = {
    'pending': 0,
    'downloading': 0,
    'tagging': 0,
    'uploading': 0,
    'completed': 0,
    'failed': 0,
  };
  String? errorMessage;
  DateTime? lastUpdated;
  
  /// SSE connection state
  SseConnectionState sseConnectionState = SseConnectionState.disconnected;

  bool get hasJobs => jobs.isNotEmpty;
  bool get hasStats => stats.values.any((value) => value > 0);
  bool get isConnected => sseConnectionState == SseConnectionState.connected;
  bool get isConnecting => sseConnectionState == SseConnectionState.connecting;

  /// Create or get the backend client with current settings.
  BackendClient get backendClient {
    _backendClient ??= BackendClient(
      baseUrl: settings.backendUrl,
      apiKey: settings.apiKey,
    );
    return _backendClient!;
  }

  /// Initialize SSE connection for real-time updates.
  void _initializeSse() {
    if (!settings.isConfigured || !settings.canMakeApiCalls) {
      return;
    }
    
    _connectSse();
  }
  
  /// Connect to SSE endpoint
  void _connectSse() {
    // Disconnect existing connection
    _disconnectSse();
    
    if (!settings.isConfigured || !settings.canMakeApiCalls) {
      return;
    }
    
    // Listen to SSE events
    final sseStream = backendClient.connectSse(autoReconnect: true);
    
    // Listen to connection state changes
    _sseStateSubscription = backendClient.sseStateStream.listen((state) {
      sseConnectionState = state;
      notifyListeners();
    });
    
    // Listen to job updates
    _jobUpdateSubscription = backendClient.jobUpdateStream.listen((update) {
      _handleJobUpdate(update);
    });
    
    // Also listen to the raw stream for errors
    sseStream.listen(
      (event) {
        // Events are handled via jobUpdateStream
        if (event.type == SseEventType.connected) {
          // Initial connection - refresh data
          refreshAll();
        }
      },
      onError: (error) {
        errorMessage = userFriendlyErrorMessage(error);
        notifyListeners();
      },
    );
  }
  
  /// Disconnect from SSE endpoint
  void _disconnectSse() {
    _sseStateSubscription?.cancel();
    _sseStateSubscription = null;
    _jobUpdateSubscription?.cancel();
    _jobUpdateSubscription = null;
    _backendClient?.disconnectSse();
    sseConnectionState = SseConnectionState.disconnected;
  }
  
  /// Handle a job update from SSE
  void _handleJobUpdate(JobUpdate update) {
    // Find and update the job in the list
    final index = jobs.indexWhere((j) => j.id == update.jobId);
    
    if (index != -1) {
      // Update existing job
      final existingJob = jobs[index];
      final wasFailed = existingJob.status.toLowerCase() == 'failed';
      final updatedJob = Job(
        id: existingJob.id,
        status: update.status,
        jobType: existingJob.jobType,
        url: existingJob.url,
        originalFilename: existingJob.originalFilename,
        sourceOverride: existingJob.sourceOverride,
        safety: existingJob.safety,
        skipTagging: existingJob.skipTagging,
        szuruPostId: update.szuruPostId ?? existingJob.szuruPostId,
        errorMessage: update.error ?? existingJob.errorMessage,
        tagsApplied: update.tags ?? existingJob.tagsApplied,
        tagsFromSource: existingJob.tagsFromSource,
        tagsFromAi: existingJob.tagsFromAi,
        retryCount: existingJob.retryCount,
        createdAt: existingJob.createdAt,
        updatedAt: update.timestamp,
      );
      
      jobs[index] = updatedJob;
      if (!wasFailed && updatedJob.status.toLowerCase() == 'failed') {
        String websiteName;
        String fullDomain;
        if (updatedJob.sources.isNotEmpty) {
          final url = updatedJob.sources.first;
          final uri = Uri.tryParse(url);
          websiteName = uri != null
              ? (uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host)
              : url;
          fullDomain = url;
        } else {
          websiteName = updatedJob.displayName != 'Job ${updatedJob.id}'
              ? updatedJob.displayName
              : 'Processing';
          fullDomain = '';
        }
        final notificationId = updatedJob.id.hashCode.abs() % 100000;
        NotificationService.instance.showUploadErrorExpanded(
          websiteName: websiteName,
          jobId: updatedJob.id,
          fullDomain: fullDomain,
          notificationId: notificationId,
        );
      }
    } else {
      // Job not in list - refresh to get full details
      refreshJobs();
    }
    
    // Update stats
    refreshStats();
    
    lastUpdated = DateTime.now();
    notifyListeners();
  }

  void _onSettingsChanged() {
    // Only reconnect SSE if the backend URL actually changed
    final urlChanged = _previousBackendUrl != settings.backendUrl;
    _previousBackendUrl = settings.backendUrl;
    
    if (urlChanged) {
      // Reinitialize SSE when URL changes
      _backendClient?.dispose();
      _backendClient = null;
      _initializeSse();
    } else if (_backendClient != null) {
      _backendClient!.updateApiKey(settings.apiKey);
    }
    
    if (settings.isConfigured && settings.canMakeApiCalls) {
      refreshAll();
    } else {
      _disconnectSse();
      jobs = [];
      stats = {'pending': 0, 'downloading': 0, 'tagging': 0, 'uploading': 0, 'completed': 0, 'failed': 0};
      notifyListeners();
    }
  }

  Future<void> refreshAll() async {
    // Fetch config first so szuruUsers is available for job filtering
    await _fetchConfig();
    await Future.wait([
      refreshJobs(),
      refreshStats(),
    ]);
  }

  Future<void> _fetchConfig() async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) return;
    try {
      final config = await backendClient.fetchConfig();
      booruUrl = config['booru_url'] as String?;
      if (booruUrl != null && booruUrl!.endsWith('/')) {
        booruUrl = booruUrl!.substring(0, booruUrl!.length - 1);
      }
      final users = config['szuru_users'];
      if (users is List) {
        szuruUsers = users.cast<String>();
      }
      notifyListeners();
    } catch (_) {
      // Non-fatal; post links will just be hidden
    }
  }

  Future<void> refreshJobs() async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) return;

    isLoadingJobs = true;
    notifyListeners();

    try {
      // Jobs are automatically filtered by authenticated user on backend
      jobs = await backendClient.fetchJobs();
      errorMessage = null;
    } catch (error) {
      errorMessage = userFriendlyErrorMessage(error);
    } finally {
      isLoadingJobs = false;
      lastUpdated = DateTime.now();
      notifyListeners();
    }
  }

  Future<void> refreshStats() async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) return;

    isLoadingStats = true;
    notifyListeners();

    try {
      // Stats are automatically filtered by authenticated user on backend
      stats = await backendClient.fetchStats();
      errorMessage = null;
    } catch (error) {
      errorMessage = userFriendlyErrorMessage(error);
    } finally {
      isLoadingStats = false;
      lastUpdated = DateTime.now();
      notifyListeners();
    }
  }

  /// Enqueue a new job from a URL.
  ///
  /// Returns null on success, or an error message string on failure.
  Future<String?> enqueueFromUrl({
    required String url,
    required List<String> tags,
    required String safety,
    String? source,
    bool? skipTagging,
  }) async {
    if (!settings.isConfigured) {
      return 'Backend configuration is missing';
    }

    if (!settings.canMakeApiCalls) {
      return 'API key is required';
    }

    // Add tagme if no tags provided
    final finalTags = tags.isEmpty ? ['tagme'] : tags;

    try {
      await backendClient.enqueueFromUrl(
        url: url,
        tags: finalTags,
        safety: safety,
        source: source,
        skipTagging: skipTagging ?? settings.skipTagging,
      );

      await refreshJobs();
      return null;
    } catch (error) {
      return userFriendlyErrorMessage(error);
    }
  }

  /// Resume a paused or stopped job.
  Future<String?> resumeJob(String jobId) async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) {
      return 'Backend configuration is missing';
    }

    try {
      await backendClient.resumeJob(jobId);
      await refreshAll();
      return null;
    } catch (error) {
      return userFriendlyErrorMessage(error);
    }
  }

  /// Pause a running job.
  Future<String?> pauseJob(String jobId) async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) {
      return 'Backend configuration is missing';
    }

    try {
      await backendClient.pauseJob(jobId);
      await refreshAll();
      return null;
    } catch (error) {
      return userFriendlyErrorMessage(error);
    }
  }

  /// Stop a job.
  Future<String?> stopJob(String jobId) async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) {
      return 'Backend configuration is missing';
    }

    try {
      await backendClient.stopJob(jobId);
      await refreshAll();
      return null;
    } catch (error) {
      return userFriendlyErrorMessage(error);
    }
  }

  /// Start a pending job.
  Future<String?> startJob(String jobId) async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) {
      return 'Backend configuration is missing';
    }

    try {
      await backendClient.startJob(jobId);
      await refreshAll();
      return null;
    } catch (error) {
      return userFriendlyErrorMessage(error);
    }
  }

  /// Delete a job.
  Future<String?> deleteJob(String jobId) async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) {
      return 'Backend configuration is missing';
    }

    try {
      await backendClient.deleteJob(jobId);
      await refreshAll();
      return null;
    } catch (error) {
      return userFriendlyErrorMessage(error);
    }
  }

  /// Fetch a single job by ID (for detail view).
  Future<Job?> fetchJob(String jobId) async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) return null;
    try {
      return await backendClient.fetchJob(jobId);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _disconnectSse();
    _backendClient?.dispose();
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
