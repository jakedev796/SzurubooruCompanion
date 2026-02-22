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
  Map<String, int> stats = {
    'pending': 0,
    'downloading': 0,
    'tagging': 0,
    'uploading': 0,
    'completed': 0,
    'merged': 0,
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
    _backendClient ??= BackendClient(baseUrl: settings.backendUrl);
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
      // Fire-and-forget async handler so we can await network calls inside
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

  /// Manually reconnect to SSE (called from UI reconnect button)
  void reconnect() {
    debugPrint('[AppState] Manual reconnect requested');
    _connectSse();
  }

  /// Handle a job update from SSE
  Future<void> _handleJobUpdate(JobUpdate update) async {
    // Find and update the job in the list
    final index = jobs.indexWhere((j) => j.id == update.jobId);
    
    if (index != -1) {
      // Update existing job
      final existingJob = jobs[index];
      final wasFailed = existingJob.status.toLowerCase() == 'failed';

      // For terminal statuses or when we get post id/tags, refresh full job from backend
      final statusLower = update.status.toLowerCase();
      final isTerminal =
          statusLower == 'completed' || statusLower == 'merged' || statusLower == 'failed';
      final hasPostId = update.szuruPostId != null;
      final hasTags = update.tags != null && update.tags!.isNotEmpty;

      Job updatedJob = Job(
        id: existingJob.id,
        status: update.status,
        jobType: existingJob.jobType,
        url: existingJob.url,
        originalFilename: existingJob.originalFilename,
        sourceOverride: existingJob.sourceOverride,
        safety: existingJob.safety,
        skipTagging: existingJob.skipTagging,
        szuruPostId: update.szuruPostId ?? existingJob.szuruPostId,
        relatedPostIds: update.relatedPostIds ?? existingJob.relatedPostIds,
        errorMessage: update.error ?? existingJob.errorMessage,
        tagsApplied: update.tags ?? existingJob.tagsApplied,
        tagsFromSource: existingJob.tagsFromSource,
        tagsFromAi: existingJob.tagsFromAi,
        retryCount: existingJob.retryCount,
        createdAt: existingJob.createdAt,
        updatedAt: update.timestamp,
      );

      if (isTerminal || hasPostId || hasTags) {
        try {
          final full = await backendClient.fetchJob(update.jobId);
          if (full != null) {
            updatedJob = full;
          }
        } catch (e) {
          debugPrint('[AppState] Failed to refresh job ${update.jobId} after SSE update: $e');
        }
      }

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
      // Job not in current list - it might be:
      // - A new job for the current user created from another device / background flow
      // - A job belonging to another user (which the backend will hide)
      try {
        final full = await backendClient.fetchJob(update.jobId);
        if (full != null) {
          // Only append if backend confirms it is visible to this user
          jobs.insert(0, full);
        }
      } catch (e) {
        // If the job is not visible (e.g. belongs to another user), ignore the update
        debugPrint('[AppState] Ignoring SSE for unknown job ${update.jobId}: $e');
      }
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
    }
    
    if (settings.isConfigured && settings.canMakeApiCalls) {
      refreshAll();
    } else {
      _disconnectSse();
      jobs = [];
      stats = {'pending': 0, 'downloading': 0, 'tagging': 0, 'uploading': 0, 'completed': 0, 'merged': 0, 'failed': 0};
      notifyListeners();
    }
  }

  Future<void> refreshAll() async {
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
      final fetched = await backendClient.fetchJobs();

      // Preserve any existing safety/post information if the refreshed
      // payload does not include it (e.g. for older jobs).
      final existingById = {for (final j in jobs) j.id: j};
      jobs = fetched.map((job) {
        final existing = existingById[job.id];
        if (existing == null) return job;

        final hasSafety = (job.safety != null && job.safety!.isNotEmpty) ||
            (job.post?.safety != null && job.post!.safety!.isNotEmpty);
        if (hasSafety) return job;

        // Carry over previously-known safety/post mirror if the new summary lacks it
        return Job(
          id: job.id,
          status: job.status,
          jobType: job.jobType,
          url: job.url,
          originalFilename: job.originalFilename,
          sourceOverride: job.sourceOverride,
          safety: existing.safety,
          skipTagging: job.skipTagging,
          szuruPostId: job.szuruPostId,
          relatedPostIds: job.relatedPostIds,
          errorMessage: job.errorMessage,
          tagsApplied: job.tagsApplied,
          tagsFromSource: job.tagsFromSource,
          tagsFromAi: job.tagsFromAi,
          szuruUser: job.szuruUser,
          dashboardUsername: job.dashboardUsername,
          retryCount: job.retryCount,
          createdAt: job.createdAt,
          updatedAt: job.updatedAt,
          post: existing.post ?? job.post,
        );
      }).toList();

      // For any completed/merged/failed jobs that still lack safety info
      // after the list refresh, hydrate them in the background from the
      // full job endpoint so safety colors show even when summaries do
      // not yet include safety.
      for (final job in jobs) {
        final status = job.status.toLowerCase();
        final isTerminal =
            status == 'completed' || status == 'merged' || status == 'failed';
        final hasSafety = (job.safety != null && job.safety!.isNotEmpty) ||
            (job.post?.safety != null && job.post!.safety!.isNotEmpty);
        if (isTerminal && !hasSafety) {
          // Fire-and-forget; we don't await so refreshJobs can complete quickly
          unawaited(_hydrateJobSafety(job.id));
        }
      }
      errorMessage = null;
    } catch (error) {
      errorMessage = userFriendlyErrorMessage(error);
    } finally {
      isLoadingJobs = false;
      lastUpdated = DateTime.now();
      notifyListeners();
    }
  }

  /// Hydrate a single job's safety/post mirror from the full job endpoint.
  /// This is used for older jobs where the list/summary payload may not
  /// yet include safety, but the detailed job does.
  Future<void> _hydrateJobSafety(String jobId) async {
    try {
      final full = await backendClient.fetchJob(jobId);
      if (full == null) return;

      final index = jobs.indexWhere((j) => j.id == jobId);
      if (index == -1) return;

      jobs[index] = full;
      lastUpdated = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('[AppState] Failed to hydrate safety for job $jobId: $e');
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
      return 'Backend URL is required';
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

  /// Retry a failed job using the same job ID.
  Future<String?> retryJob(String jobId) async {
    if (!settings.isConfigured || !settings.canMakeApiCalls) {
      return 'Backend configuration is missing';
    }

    try {
      await backendClient.retryJob(jobId);
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
