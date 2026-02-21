import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import '../models/job.dart';
import '../services/app_state.dart';
import '../services/backend_client.dart';
import '../services/background_task.dart';
import '../services/companion_foreground_service.dart';
import '../services/floating_bubble_service.dart';
import '../services/notification_service.dart';
import '../services/share_intent_service.dart';
import '../services/settings_model.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/job_card.dart';
import '../widgets/job_detail_sheet.dart';
import '../widgets/stat_card.dart';
import 'discover_screen.dart';
import 'first_launch_permissions.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isProcessingShare = false;
  bool _pendingDeletesProcessed = false;
  bool _appliedBubbleOnLoad = false;
  bool _firstLaunchPermissionsChecked = false;
  DateTime? _lastNotificationUpdate;
  Timer? _statusNotificationReshowTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = context.read<SettingsModel>();
    _selectedIndex = settings.isConfigured ? 0 : 3;
    ShareIntentService.setupMethodCallHandler(_handleShare);
    _checkInitialShare();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkOverlayPermissionOnResume();
    }
  }

  Future<void> _checkOverlayPermissionOnResume() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    try {
      await context.read<SettingsModel>().loadSettings();
      if (!mounted) return;
      await _applyBubbleAndNotificationFromState();
    } catch (e) {
      debugPrint('[Main] _checkOverlayPermissionOnResume error: $e');
    }
  }

  Future<void> _applyBubbleAndNotificationFromState() async {
    if (!mounted) return;
    try {
      final settings = context.read<SettingsModel>();
      
      // Early return if backend is not configured or user is not authenticated
      // This prevents services from starting on first launch before setup/login
      if (!settings.isConfigured || !settings.isAuthenticated) {
        debugPrint('[Main] Backend not configured or user not authenticated, stopping services');
        await stopCompanionForegroundService();
        await stopFloatingBubbleService();
        return;
      }
      
      final folders = await settings.getScheduledFolders();
      if (!mounted) return;
      final hasFoldersEnabled = folders.any((f) => f.enabled == true);
      final folderSyncEnabled =
          hasFoldersEnabled && settings.showPersistentNotification;
      if (folderSyncEnabled) {
        await startCompanionForegroundService(
          folderSyncEnabled: true,
          bubbleEnabled: settings.showFloatingBubble && folderSyncEnabled,
          statusBody: buildCompanionNotificationBody(
            folderSyncOn: true,
            bubbleOn: settings.showFloatingBubble && folderSyncEnabled,
          ),
        );
        if (!mounted) return;
        await stopFloatingBubbleService();
      } else {
        if (settings.showFloatingBubble) {
          final hasOverlay = await canDrawOverlays();
          if (hasOverlay) {
            await startCompanionForegroundService(
              folderSyncEnabled: false,
              bubbleEnabled: true,
              statusBody: buildCompanionNotificationBody(bubbleOn: true),
            );
          }
        } else {
          await stopCompanionForegroundService();
        }
        await stopFloatingBubbleService();
      }
    } catch (e) {
      debugPrint('[Main] _applyBubbleAndNotificationFromState error: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_appliedBubbleOnLoad) {
      _appliedBubbleOnLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _applyBubbleAndNotificationFromState();
      });
    }
    if (!_firstLaunchPermissionsChecked) {
      _firstLaunchPermissionsChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await runFirstLaunchPermissionFlowIfNeeded(context);
      });
    }
    if (!_pendingDeletesProcessed) {
      _pendingDeletesProcessed = true;
      _processPendingDeletes();
    }
  }

  Future<void> _processPendingDeletes() async {
    try {
      final settings = context.read<SettingsModel>();
      final filePaths = await settings.getPendingDeleteUris();
      for (final filePath in filePaths) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            debugPrint('[Main] Deleted pending file: $filePath');
          }
        } catch (e) {
          debugPrint('[Main] Error deleting file $filePath: $e');
        }
        await settings.removePendingDeleteUri(filePath);
      }
    } catch (e) {
      debugPrint('[Main] _processPendingDeletes error: $e');
    }
  }

  Future<void> _updateStatusNotificationIfNeeded(
    SettingsModel settings,
    AppState appState,
  ) async {
    try {
      // Don't update notification if backend is not configured or user is not authenticated
      if (!settings.isConfigured || !settings.isAuthenticated) return;
      
      final folders = await settings.getScheduledFolders();
      final folderSyncOn = folders.where((f) => f.enabled).isNotEmpty &&
          settings.showPersistentNotification;
      if (!folderSyncOn && !settings.showFloatingBubble) return;
      if (!mounted) return;
      final connectionText = appState.isConnected
          ? 'Connected'
          : (appState.isConnecting ? 'Connecting...' : 'Disconnected');
      if (!mounted) return;
      final body = buildCompanionNotificationBody(
        connectionText: connectionText,
        folderSyncOn: folderSyncOn,
        bubbleOn: settings.showFloatingBubble,
      );
      await updateCompanionNotification(statusBody: body);
    } catch (e) {
      debugPrint('[Main] _updateStatusNotificationIfNeeded error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusNotificationReshowTimer?.cancel();
    _statusNotificationReshowTimer = null;
    super.dispose();
  }

  Future<void> _checkInitialShare() async {
    final share = await ShareIntentService.getInitialShare();
    if (share != null) {
      await _handleShare(share);
      await ShareIntentService.clearInitialShare();
    }
  }

  Future<void> _handleShare(Map<String, dynamic> data) async {
    final url = data['url'] as String?;
    final path = data['path'] as String?;
    if (url != null && url.isNotEmpty) {
      await _processShare(url);
    } else if (path != null && path.isNotEmpty) {
      _showSnackBar(
        'Local files are not supported yet. Please share a remote URL.',
      );
    }
  }

  Future<void> _processShare(String url) async {
    final settings = context.read<SettingsModel>();
    final appState = context.read<AppState>();
    if (!settings.isConfigured) {
      setState(() => _selectedIndex = 3);
      return;
    }

    if (_isProcessingShare) return;
    setState(() => _isProcessingShare = true);

    final tags = _normalizeTags(settings.defaultTags);

    try {
      if (settings.useBackgroundService) {
        await Workmanager().registerOneOffTask(
          kUploadTask,
          kUploadTask,
          inputData: {
            'url': url,
            'backendUrl': settings.backendUrl,
            'tags': tags,
            'safety': settings.defaultSafety,
            'skipTagging': settings.skipTagging,
          },
        );
        await NotificationService.instance.showUploadSuccess(url);
        await appState.refreshJobs();
        _showSnackBar('Background share scheduled');
      } else {
        final error = await appState.enqueueFromUrl(
          url: url,
          tags: tags,
          safety: settings.defaultSafety,
          skipTagging: settings.skipTagging,
        );
        if (error == null) {
          _showSnackBar('Upload queued successfully');
        } else {
          _showSnackBar('Upload failed: $error');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingShare = false);
      }
    }
  }

  void _showSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: duration),
    );
  }

  List<String> _normalizeTags(String raw) {
    final cleaned = raw
        .split(RegExp(r'[\s,]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return cleaned.isEmpty ? ['tagme'] : cleaned;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsModel, AppState>(
      builder: (context, settings, appState, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            if (_lastNotificationUpdate != null &&
                DateTime.now().difference(_lastNotificationUpdate!) <
                    const Duration(seconds: 2)) {
              return;
            }
            _lastNotificationUpdate = DateTime.now();
            await _updateStatusNotificationIfNeeded(settings, appState);
            if (!mounted) return;
            if (!settings.showPersistentNotification) {
              _statusNotificationReshowTimer?.cancel();
              _statusNotificationReshowTimer = null;
              return;
            }
            final folders = await settings.getScheduledFolders();
            if (!mounted) return;
            if (folders.any((f) => f.enabled == true)) {
              _statusNotificationReshowTimer ??= Timer.periodic(
                const Duration(minutes: 1),
                (_) async {
                  if (!mounted) return;
                  try {
                    if (!mounted) return;
                    final s = context.read<SettingsModel>();
                    final a = context.read<AppState>();
                    await _updateStatusNotificationIfNeeded(s, a);
                    if (!mounted) return;
                  } catch (e, st) {
                    debugPrint('[Main] Timer notification update error: $e');
                    debugPrint('[Main] Timer stack: $st');
                  }
                },
              );
            } else {
              _statusNotificationReshowTimer?.cancel();
              _statusNotificationReshowTimer = null;
            }
          } catch (e) {
            debugPrint('[Main] PostFrameCallback notification error: $e');
          }
        });
        final screens = [
          _buildOverview(settings, appState),
          _buildQueueTab(appState),
          const DiscoverScreen(),
          const SettingsScreen(),
        ];

        return Scaffold(
          appBar: AppBar(
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/icons/192.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
            title: const Text('SzuruCompanion'),
            actions: [
              _buildConnectionStatusIndicator(appState),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => setState(() => _selectedIndex = 3),
              ),
            ],
            bottom: _isProcessingShare
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(4),
                    child: LinearProgressIndicator(minHeight: 4),
                  )
                : null,
          ),
          body: screens[_selectedIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Overview',
              ),
              NavigationDestination(
                icon: Icon(Icons.list_outlined),
                selectedIcon: Icon(Icons.list),
                label: 'Queue',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Discover',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
            onDestinationSelected: (index) => setState(() {
              _selectedIndex = index;
            }),
          ),
        );
      },
    );
  }

  Widget _buildConnectionStatusIndicator(AppState appState) {
    IconData icon;
    Color color;
    String tooltip;
    switch (appState.sseConnectionState) {
      case SseConnectionState.connected:
        icon = Icons.cloud_done;
        color = AppColors.green;
        tooltip = 'Connected to server';
        break;
      case SseConnectionState.connecting:
        icon = Icons.cloud_sync;
        color = AppColors.orange;
        tooltip = 'Connecting...';
        break;
      case SseConnectionState.disconnected:
        icon = Icons.cloud_off;
        color = AppColors.textMuted;
        tooltip = 'Disconnected';
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip,
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildOverview(SettingsModel settings, AppState appState) {
    final stats = appState.stats;
    return RefreshIndicator(
      onRefresh: appState.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectionStatusCard(
            connectionState: appState.sseConnectionState,
            lastUpdated: appState.lastUpdated,
          ),
          const SizedBox(height: 12),
          const Text(
            'Live Queue Stats',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (appState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                appState.errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatCard(
                label: 'Pending',
                value: stats['pending'] ?? 0,
                color: AppColors.orange,
              ),
              const SizedBox(width: 8),
              StatCard(
                label: 'Active',
                value: (stats['downloading'] ?? 0) +
                    (stats['tagging'] ?? 0) +
                    (stats['uploading'] ?? 0),
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              StatCard(
                label: 'Completed',
                value: stats['completed'] ?? 0,
                color: AppColors.green,
              ),
              const SizedBox(width: 8),
              StatCard(
                label: 'Failed',
                value: stats['failed'] ?? 0,
                color: AppColors.red,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Latest jobs',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (appState.isLoadingJobs)
            const Center(child: CircularProgressIndicator())
          else if (appState.jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Waiting for jobs to arrive...'),
            )
          else
            Column(
              children: List.generate(
                appState.jobs.length > 3 ? 3 : appState.jobs.length,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: JobCard(
                    job: appState.jobs[index],
                    booruUrl: appState.booruUrl,
                    onTap: () => _showJobDetail(
                      context,
                      appState.jobs[index],
                      appState,
                      appState.booruUrl,
                    ),
                    onShowFullTagList: _showFullTagList,
                  ),
                ),
              ),
            ),
          if (!settings.isConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ElevatedButton(
                onPressed: () => setState(() => _selectedIndex = 3),
                child: const Text('Configure backend'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueTab(AppState appState) {
    return RefreshIndicator(
      onRefresh: appState.refreshJobs,
      child: appState.isLoadingJobs
          ? const Center(child: CircularProgressIndicator())
          : appState.jobs.isEmpty
              ? const Center(child: Text('No jobs yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  itemCount: appState.jobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => JobCard(
                    job: appState.jobs[index],
                    booruUrl: appState.booruUrl,
                    onTap: () => _showJobDetail(
                      context,
                      appState.jobs[index],
                      appState,
                      appState.booruUrl,
                    ),
                    onShowFullTagList: _showFullTagList,
                  ),
                ),
    );
  }

  void _showFullTagList(List<String> tags) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'All tags (${tags.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                itemCount: tags.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Chip(
                    label: Text(tags[index]),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showJobDetail(
    BuildContext context,
    Job job,
    AppState appState,
    String? booruUrl,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => JobDetailSheetContent(
          jobId: job.id,
          scrollController: scrollController,
          booruUrl: booruUrl,
          onOpenPost: (booru, postId) => JobCard.openPostLink(
            context,
            booru ?? '',
            postId,
          ),
        ),
      ),
    );
  }

}
