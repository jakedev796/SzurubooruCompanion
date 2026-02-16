import 'dart:async';
import 'dart:io';

import 'package:battery_optimization_helper/battery_optimization_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';

import 'src/models/job.dart';
import 'src/screens/folder_list_screen.dart';
import 'src/services/app_state.dart';
import 'src/theme/app_theme.dart';
import 'src/services/backend_client.dart';
import 'src/services/background_task.dart';
import 'src/services/notification_service.dart';
import 'src/services/settings_model.dart';
import 'src/services/companion_foreground_service.dart';
import 'src/services/floating_bubble_service.dart';
import 'src/services/storage_permission.dart';

String _formatFolderSyncIntervalShort(int seconds) {
  return switch (seconds) {
    900 => 'every 15 min',
    1800 => 'every 30 min',
    3600 => 'every hour',
    21600 => 'every 6 hours',
    43200 => 'every 12 hours',
    86400 => 'every day',
    604800 => 'every week',
    _ => 'every ${seconds ~/ 60} min',
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await initializeBackgroundTasks();

  runApp(
    Phoenix(
      child: const _AppRoot(),
    ),
  );
}

/// Loads settings and builds the provider tree. Rebuilt on Phoenix.rebirth() so
/// restore gets a fresh load from storage.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  SettingsModel? _settings;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settingsModel = SettingsModel();
      await settingsModel.loadSettings();
      if (mounted) {
        setState(() {
          _settings = settingsModel;
          _loadError = null;
        });
        final folders = await settingsModel.getScheduledFolders();
        if (folders.any((f) => f.enabled)) {
          scheduleFolderScanTask().catchError((e) {
            debugPrint('[AppRoot] Error scheduling folder scan: $e');
          });
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[AppRoot] Error loading settings: $e');
      debugPrint('[AppRoot] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return MaterialApp(
        theme: appDarkTheme,
        darkTheme: appDarkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load settings: $_loadError'),
            ),
          ),
        ),
      );
    }
    if (_settings == null) {
      return MaterialApp(
        theme: appDarkTheme,
        darkTheme: appDarkTheme,
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsModel>.value(value: _settings!),
        ChangeNotifierProxyProvider<SettingsModel, AppState>(
          create: (context) => AppState(_settings!),
          update: (context, settings, previous) =>
              previous ?? AppState(settings),
        ),
      ],
      child: const SzuruCompanionApp(),
    );
  }
}

class ShareIntentService {
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

class SzuruCompanionApp extends StatelessWidget {
  const SzuruCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SzuruCompanion',
      debugShowCheckedModeBanner: false,
      theme: appDarkTheme,
      darkTheme: appDarkTheme,
      themeMode: ThemeMode.dark,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final GlobalKey<FormState> _settingsFormKey = GlobalKey<FormState>();
  final TextEditingController _backendUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _defaultTagsController = TextEditingController();
  final FocusNode _backendUrlFocusNode = FocusNode();
  final FocusNode _apiKeyFocusNode = FocusNode();
  final FocusNode _defaultTagsFocusNode = FocusNode();
  String _selectedSafety = 'unsafe';
  bool _useBackgroundService = true;
  bool _skipTagging = false;
  bool _notifyOnFolderSync = false;
  bool _deleteMediaAfterSync = false;
  bool _showPersistentNotification = true;
  bool _showFloatingBubble = false;
  int _folderSyncIntervalSeconds = 900;
  String _szuruUser = '';
  int _selectedIndex = 0;
  bool _isProcessingShare = false;
  bool _isSyncingFolders = false;
  bool _settingsInitialized = false;
  bool _pendingDeletesProcessed = false;
  bool _isRestoreInProgress = false;
  DateTime? _lastNotificationUpdate;
  Timer? _statusNotificationReshowTimer;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backendUrlFocusNode.addListener(_handleBackendUrlFocusChange);
    _apiKeyFocusNode.addListener(_handleApiKeyFocusChange);
    _defaultTagsFocusNode.addListener(_handleDefaultTagsFocusChange);
    final settings = context.read<SettingsModel>();
    _selectedIndex = settings.isConfigured ? 0 : 2;
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
    if (_isRestoreInProgress) return;
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    try {
      final hasOverlay = await canDrawOverlays();
      if (!mounted) return;
      final settings = context.read<SettingsModel>();
      final settingsWantBubble = settings.showFloatingBubble;

      if (hasOverlay && settingsWantBubble && !_showFloatingBubble) {
        if (mounted) setState(() => _showFloatingBubble = true);
        if (mounted) await _saveSettingsInternal(validate: false, checkPermissions: false);
      } else if (!hasOverlay && _showFloatingBubble) {
        if (mounted) setState(() => _showFloatingBubble = false);
        if (mounted) await _saveSettingsInternal(validate: false, checkPermissions: false);
      }
    } catch (e) {
      debugPrint('[Main] _checkOverlayPermissionOnResume error: $e');
    }
  }

  /// Start or stop bubble/companion service from current UI state (no save).
  /// Call after first settings sync so restored settings apply the bubble on load.
  Future<void> _applyBubbleAndNotificationFromState() async {
    if (!mounted) return;
    try {
      final settings = context.read<SettingsModel>();
      final folders = await settings.getScheduledFolders();
      if (!mounted) return;
      final hasFoldersEnabled = folders.any((f) => f.enabled == true);
      final folderSyncEnabled = hasFoldersEnabled && _showPersistentNotification;
      if (folderSyncEnabled) {
        await startCompanionForegroundService(
          folderSyncEnabled: true,
          bubbleEnabled: _showFloatingBubble && folderSyncEnabled,
          statusBody: buildCompanionNotificationBody(
            folderSyncOn: true,
            bubbleOn: _showFloatingBubble && folderSyncEnabled,
          ),
        );
        if (!mounted) return;
        await stopFloatingBubbleService();
      } else {
        if (_showFloatingBubble) {
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
    if (!_settingsInitialized) {
      _syncSettingsFields();
      _settingsInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _applyBubbleAndNotificationFromState();
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

  Future<void> _updateStatusNotificationIfNeeded(SettingsModel settings, AppState appState) async {
    try {
      final folders = await settings.getScheduledFolders();
      final folderSyncOn = folders.where((f) => f.enabled).isNotEmpty && settings.showPersistentNotification;
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
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _backendUrlFocusNode.removeListener(_handleBackendUrlFocusChange);
    _apiKeyFocusNode.removeListener(_handleApiKeyFocusChange);
    _defaultTagsFocusNode.removeListener(_handleDefaultTagsFocusChange);
    _backendUrlFocusNode.dispose();
    _apiKeyFocusNode.dispose();
    _defaultTagsFocusNode.dispose();
    _backendUrlController.dispose();
    _apiKeyController.dispose();
    _defaultTagsController.dispose();
    super.dispose();
  }

  void _syncSettingsFields() {
    try {
      if (!mounted) return;
      final settings = context.read<SettingsModel>();
      _backendUrlController.text = settings.backendUrl;
      _apiKeyController.text = settings.apiKey;
      _defaultTagsController.text = settings.defaultTags;
      _selectedSafety = settings.defaultSafety;
      _useBackgroundService = settings.useBackgroundService;
      _skipTagging = settings.skipTagging;
      _notifyOnFolderSync = settings.notifyOnFolderSync;
      _deleteMediaAfterSync = settings.deleteMediaAfterSync;
      _showPersistentNotification = settings.showPersistentNotification;
      _showFloatingBubble = settings.showFloatingBubble;
      _folderSyncIntervalSeconds = settings.folderSyncIntervalSeconds;
      _szuruUser = settings.szuruUser;
    } catch (e) {
      debugPrint('[Main] Error syncing settings fields: $e');
    }
  }

  void _handleBackendUrlFocusChange() {
    if (!_backendUrlFocusNode.hasFocus) {
      // Validate full form when backend URL is edited
      _autoSaveSettings(validate: true);
    }
  }

  void _handleApiKeyFocusChange() {
    if (!_apiKeyFocusNode.hasFocus) {
      _autoSaveSettings(validate: true);
    }
  }

  void _handleDefaultTagsFocusChange() {
    if (!_defaultTagsFocusNode.hasFocus) {
      // Tags don't affect validity, skip form validation here
      _autoSaveSettings(validate: false);
    }
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
      setState(() {
        _selectedIndex = 2;
      });
      return;
    }

    if (_isProcessingShare) return;
    setState(() {
      _isProcessingShare = true;
    });

    final tags = _normalizeTags(settings.defaultTags);

    try {
      if (_useBackgroundService) {
        await Workmanager().registerOneOffTask(
          kUploadTask,
          kUploadTask,
          inputData: {
            'url': url,
            'backendUrl': settings.backendUrl,
            'apiKey': settings.apiKey,
            'tags': tags,
            'safety': _selectedSafety,
            'skipTagging': _skipTagging,
            'szuruUser': settings.szuruUser,
          },
        );
        await NotificationService.instance.showUploadSuccess(url);
        await appState.refreshJobs();
        _showSnackBar('Background share scheduled');
      } else {
        final error = await appState.enqueueFromUrl(
          url: url,
          tags: tags,
          safety: _selectedSafety,
          skipTagging: _skipTagging,
        );
        if (error == null) {
          _showSnackBar('Upload queued successfully');
        } else {
          _showSnackBar('Upload failed: $error');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingShare = false;
        });
      }
    }
  }

  void _showSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), duration: duration));
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
                DateTime.now().difference(_lastNotificationUpdate!) < const Duration(seconds: 2)) {
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
          _buildSettingsTab(settings),
        ];

        return Scaffold(
          appBar: AppBar(
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/icons/192.png',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
              ),
            ),
            title: const Text('SzuruCompanion'),
            actions: [
              _buildConnectionStatusIndicator(appState),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => setState(() {
                  _selectedIndex = 2;
                }),
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
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
            onDestinationSelected: (index) => setState(() {
              _selectedIndex = index;
            }),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showShareTestDialog(),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  /// Build connection status indicator for the app bar
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
          // Connection status card
          _buildConnectionStatusCard(appState),
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
              _buildStatCard('Pending', stats['pending'] ?? 0, AppColors.orange),
              const SizedBox(width: 8),
              _buildStatCard('Active', (stats['downloading'] ?? 0) + (stats['tagging'] ?? 0) + (stats['uploading'] ?? 0), AppColors.accent),
              const SizedBox(width: 8),
              _buildStatCard(
                'Completed',
                stats['completed'] ?? 0,
                AppColors.green,
              ),
              const SizedBox(width: 8),
              _buildStatCard('Failed', stats['failed'] ?? 0, AppColors.red),
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
                  child: _buildJobCard(appState.jobs[index], appState.booruUrl),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Share settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Backend URL: ${settings.backendUrl}'),
          Text(
            'Background processing: ${settings.useBackgroundService ? 'enabled' : 'disabled'}',
          ),
          Text('Default safety: ${settings.defaultSafety}'),
          Text('Default tags: ${settings.defaultTags}'),
          Text('Skip tagging: ${settings.skipTagging ? 'yes' : 'no'}'),
          if (!settings.isConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ElevatedButton(
                onPressed: () => setState(() {
                  _selectedIndex = 2;
                }),
                child: const Text('Configure backend'),
              ),
            ),
        ],
      ),
    );
  }

  /// Build connection status card for the overview
  Widget _buildConnectionStatusCard(AppState appState) {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    switch (appState.sseConnectionState) {
      case SseConnectionState.connected:
        statusText = 'Connected - Real-time updates active';
        statusIcon = Icons.check_circle;
        statusColor = AppColors.green;
        break;
      case SseConnectionState.connecting:
        statusText = 'Connecting...';
        statusIcon = Icons.sync;
        statusColor = AppColors.orange;
        break;
      case SseConnectionState.disconnected:
        statusText = 'Disconnected';
        statusIcon = Icons.cloud_off;
        statusColor = AppColors.textMuted;
        break;
    }

    return Card(
      color: statusColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (appState.lastUpdated != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last update: ${_relativeTime(appState.lastUpdated!)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
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
                  itemBuilder: (context, index) =>
                      _buildJobCard(appState.jobs[index], appState.booruUrl),
                ),
    );
  }

  Widget _buildSettingsTab(SettingsModel settings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _settingsFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backend Settings Section
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: const Text(
                  'Backend Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                initiallyExpanded: true,
                children: [
                const SizedBox(height: 8),
                TextFormField(
                  controller: _backendUrlController,
                  focusNode: _backendUrlFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'https://your-bot.booru',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Backend URL is required';
                    }
                    if (!value.startsWith('http://') &&
                        !value.startsWith('https://')) {
                      return 'URL must start with http:// or https://';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiKeyController,
                  focusNode: _apiKeyFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'API Key (optional)',
                    hintText: 'Leave empty if backend does not require authentication',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Consumer<AppState>(
                  builder: (context, appState, _) {
                    if (appState.szuruUsers.length <= 1) {
                      return const SizedBox.shrink();
                    }
                    final validUser = appState.szuruUsers.contains(_szuruUser)
                        ? _szuruUser
                        : '';
                    return DropdownButtonFormField<String>(
                      value: validUser,
                      decoration: const InputDecoration(
                        labelText: 'Upload as',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Default user'),
                        ),
                        ...appState.szuruUsers.map(
                          (u) => DropdownMenuItem(value: u, child: Text(u)),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _szuruUser = value ?? '';
                        });
                        _autoSaveSettings(validate: false);
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
            ),
            
            // Share Settings Section
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: const Text(
                  'Share Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                children: [
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Background processing'),
                  subtitle: const Text(
                    'Use WorkManager to queue shares without opening the UI',
                  ),
                  value: _useBackgroundService,
                  onChanged: (value) {
                    setState(() {
                      _useBackgroundService = value;
                    });
                    _autoSaveSettings(validate: false);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _defaultTagsController,
                  focusNode: _defaultTagsFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Default tags',
                    hintText: 'tagme, favorite',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedSafety,
                  decoration: const InputDecoration(
                    labelText: 'Default safety',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'safe', child: Text('Safe')),
                    DropdownMenuItem(value: 'sketchy', child: Text('Sketchy')),
                    DropdownMenuItem(value: 'unsafe', child: Text('Unsafe')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSafety = value ?? 'unsafe';
                    });
                    _autoSaveSettings(validate: false);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Skip auto-tagging'),
                  subtitle: const Text(
                    'Disable automatic tagging from source and AI',
                  ),
                  value: _skipTagging,
                  onChanged: (value) {
                    setState(() {
                      _skipTagging = value;
                    });
                    _autoSaveSettings(validate: false);
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Share workflow',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Share any remote URL into SzuruCompanion and it will automatically queue the link with your preferred tags and safety rating.',
                ),
                const SizedBox(height: 12),
              ],
            ),
            ),
            
            // Folder Settings Section
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: const Text(
                  'Folder Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                children: [
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('Scheduled Folders'),
                  subtitle: const Text('Configure automatic folder uploads'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FolderListScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ElevatedButton.icon(
                  onPressed: _isSyncingFolders ? null : _runFolderSync,
                  icon: _isSyncingFolders
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_isSyncingFolders ? 'Syncing...' : 'Sync Folders Now'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Notify on folder sync'),
                  subtitle: const Text(
                    'Show a notification when folder sync runs and how many files were uploaded',
                  ),
                  value: _notifyOnFolderSync,
                  onChanged: (value) {
                    setState(() {
                      _notifyOnFolderSync = value;
                    });
                    _autoSaveSettings(validate: false);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Delete media after folder sync'),
                  subtitle: const Text(
                    'Remove source files after upload. We try to delete in background; if that fails, files are deleted when you next open the app.',
                  ),
                  value: _deleteMediaAfterSync,
                  onChanged: (value) {
                    setState(() {
                      _deleteMediaAfterSync = value;
                    });
                    _autoSaveSettings(validate: false);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Show persistent status notification'),
                  subtitle: const Text(
                    'Keep a notification in the status bar when folder sync is on (connectivity status).',
                  ),
                  value: _showPersistentNotification,
                  onChanged: (value) {
                    setState(() {
                      _showPersistentNotification = value;
                    });
                    _autoSaveSettings(validate: false);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _folderSyncIntervalSeconds,
                  decoration: const InputDecoration(
                    labelText: 'Folder sync interval',
                    border: OutlineInputBorder(),
                    helperText: 'Clock-aligned (e.g. 30 min runs at :00 and :30)',
                  ),
                  items: const [
                    DropdownMenuItem(value: 900, child: Text('Every 15 minutes')),
                    DropdownMenuItem(value: 1800, child: Text('Every 30 minutes')),
                    DropdownMenuItem(value: 3600, child: Text('Every hour')),
                    DropdownMenuItem(value: 21600, child: Text('Every 6 hours')),
                    DropdownMenuItem(value: 43200, child: Text('Every 12 hours')),
                    DropdownMenuItem(value: 86400, child: Text('Every day')),
                    DropdownMenuItem(value: 604800, child: Text('Every week')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _folderSyncIntervalSeconds = value);
                      _autoSaveSettings(validate: false);
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
            ),
            
            // App Features Section
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: const Text(
                  'App Features',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                children: [
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Floating bubble'),
                  subtitle: const Text(
                    'Show a floating bubble overlay. Tap it to queue whatever URL is in your clipboard.',
                  ),
                  value: _showFloatingBubble,
                  onChanged: (value) async {
                    setState(() {
                      _showFloatingBubble = value;
                    });
                    await _saveSettingsInternal(validate: false, checkPermissions: true);
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Real-time Updates',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This app uses Server-Sent Events (SSE) for real-time job updates. '
                  'No polling is required - updates are pushed instantly from the server.',
                ),
                const SizedBox(height: 12),
              ],
            ),
            ),
            
            // Backup & Restore Section
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: const Text(
                  'Backup & Restore',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                children: [
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Backup: choose a folder to save a settings file. Restore: choose a backup file. Settings are also auto-backed up when changed.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final directoryPath = await FilePicker.platform.getDirectoryPath();
                          if (directoryPath == null || !mounted) return;
                          final filePath = await settings.backupSettingsToDirectory(directoryPath);
                          if (mounted) {
                            _showSnackBar(
                              filePath != null
                                  ? 'Backup saved to $filePath'
                                  : 'Failed to backup settings',
                            );
                          }
                        },
                        icon: const Icon(Icons.backup),
                        label: const Text('Backup'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['json'],
                              allowMultiple: false,
                              withData: true,
                            );
                            if (result == null || result.files.isEmpty || !mounted) return;
                            final file = result.files.single;
                            String? backupJson;
                            if (file.bytes != null && file.bytes!.isNotEmpty) {
                              backupJson = String.fromCharCodes(file.bytes!);
                            } else if (file.path != null) {
                              final f = File(file.path!);
                              if (await f.exists()) backupJson = await f.readAsString();
                            }
                            if (backupJson == null || backupJson.isEmpty) {
                              if (mounted) _showSnackBar('Could not read backup file');
                              return;
                            }
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Restore Settings'),
                                content: const Text(
                                  'This will replace your current settings with the backup. Continue?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Restore'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !mounted) return;

                            final permissionsNeeded = settings.checkPermissionsNeededFromBackupContent(backupJson);
                            if (!mounted) return;

                            setState(() => _isRestoreInProgress = true);
                            try {
                              await _promptPermissionsBeforeRestore(permissionsNeeded);
                              if (!mounted) return;

                              final success = await settings.restoreSettingsFromJsonString(backupJson);
                              if (!mounted) return;
                              if (success) {
                                try {
                                  final rootContext = context;
                                  await showDialog<void>(
                                    context: rootContext,
                                    barrierDismissible: false,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Settings Restored'),
                                      content: const Text(
                                        'Settings have been restored from backup. '
                                        'Tap Restart to apply changes.',
                                      ),
                                      actions: [
                                        ElevatedButton(
                                          onPressed: () async {
                                            Navigator.pop(dialogContext);
                                            await Future.delayed(const Duration(milliseconds: 400));
                                            if (rootContext.mounted) Phoenix.rebirth(rootContext);
                                          },
                                          child: const Text('Restart'),
                                        ),
                                      ],
                                    ),
                                  );
                                } catch (e) {
                                  debugPrint('[Main] Restore success dialog error: $e');
                                  if (mounted) _showSnackBar('Settings restored. Restart the app to apply.');
                                }
                              } else {
                                if (mounted) _showSnackBar('Failed to restore settings');
                              }
                            } finally {
                              if (mounted) setState(() => _isRestoreInProgress = false);
                            }
                          } catch (e) {
                            debugPrint('[Main] Restore flow error: $e');
                            if (mounted) {
                              setState(() => _isRestoreInProgress = false);
                              _showSnackBar('Restore failed');
                            }
                          }
                        },
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
            ),
            
            // Save Settings Button
            ElevatedButton(
              onPressed: _saveSettings,
              child: const Text('Save settings'),
            ),
            const SizedBox(height: 16),
            // App Health Section
            const Text(
              'App health',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const _AppHealthSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard(Job job, [String? booruUrl]) {
    final tags = job.allTags;
    final showPostLink = job.status == 'completed' &&
        job.szuruPostId != null &&
        booruUrl != null &&
        booruUrl.isNotEmpty;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    job.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(job.status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    job.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: _getStatusColor(job.status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.progressValue / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 8),
            Text('Progress: ${job.progressValue.toStringAsFixed(0)}%'),
            if (job.safetyDisplay.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Safety: ${job.safetyDisplay}'),
              ),
            if (showPostLink)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  onTap: () => _openPostLink(booruUrl, job.szuruPostId!),
                  child: Text(
                    'View post #${job.szuruPostId}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (tags.isNotEmpty) _buildTagChips(tags),
            const SizedBox(height: 6),
            Text(
              'Updated ${_relativeTime(job.updatedAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runFolderSync() async {
    setState(() => _isSyncingFolders = true);
    try {
      final outcome = await triggerManualScanAll();
      if (mounted) {
        if (outcome.uploaded > 0) {
          _showSnackBar(
            outcome.uploaded == 1
                ? '1 file uploaded'
                : '${outcome.uploaded} files uploaded',
          );
        } else {
          _showSnackBar('No files to sync');
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('Folder sync failed: $e');
    } finally {
      if (mounted) setState(() => _isSyncingFolders = false);
    }
  }

  Future<void> _openPostLink(String booruUrl, int postId) async {
    final uri = Uri.parse('$booruUrl/post/$postId');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }

  static const int _visibleTagCount = 4;

  Widget _buildTagChips(List<String> tags) {
    final visible = tags.take(_visibleTagCount).toList();
    final remaining = tags.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visible.map(
          (tag) => Chip(
            label: Text(tag, style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
          ),
        ),
        if (remaining > 0)
          GestureDetector(
            onTap: () => _showFullTagList(tags),
            child: Chip(
              label: Text('+$remaining', style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
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

  Color _getStatusColor(String status) {
    return AppStatusColors.forStatus(status);
  }

  Future<void> _autoSaveSettings({bool validate = true}) async {
    if (validate && _settingsFormKey.currentState?.validate() != true) return;
    if (!mounted) return;

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      await _saveSettingsInternal(validate: validate, checkPermissions: false);
    });
  }

  Future<void> _saveSettings() async {
    _autoSaveTimer?.cancel();
    await _saveSettingsInternal(validate: true, checkPermissions: true);
  }

  /// Before restoring from backup, prompt for any permissions required by the backup.
  /// This ensures permissions are granted before settings are restored and app restarts.
  Future<void> _promptPermissionsBeforeRestore(Map<String, bool> permissionsNeeded) async {
    if (!mounted) return;

    if (permissionsNeeded['needsOverlayPermission'] == true) {
      final hasOverlay = await canDrawOverlays();
      if (!hasOverlay && mounted) {
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Overlay Permission'),
            content: const Text(
              'Your backup has the floating bubble enabled. '
              'Grant "Display over other apps" permission to use it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Grant'),
              ),
            ],
          ),
        );
        if (shouldRequest == true && mounted) {
          await requestOverlayPermission();
          await Future.delayed(const Duration(milliseconds: 800));
          if (!mounted) return;
          final granted = await canDrawOverlays();
          if (granted && mounted) {
            _showSnackBar('Overlay permission granted');
          }
        }
      }
    }

    if (!mounted) return;
    if (permissionsNeeded['needsStoragePermission'] == true) {
      final hasStorage = await StoragePermissionService.hasStoragePermission();
      if (!hasStorage && mounted) {
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Storage Permission'),
            content: const Text(
              'Your backup has folder sync enabled. '
              'Grant "All files access" permission for background sync to work?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Grant'),
              ),
            ],
          ),
        );
        if (shouldRequest == true && mounted) {
          await StoragePermissionService.requestStoragePermission();
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          final granted = await StoragePermissionService.hasStoragePermission();
          if (granted && mounted) {
            _showSnackBar('Storage permission granted');
          }
        }
      }
    }
  }

  Future<void> _saveSettingsInternal({bool validate = true, bool checkPermissions = true}) async {
    try {
      if (validate && _settingsFormKey.currentState?.validate() != true) return;
      if (!mounted) return;

      final settings = context.read<SettingsModel>();
      final folders = await settings.getScheduledFolders();
      final hasFoldersEnabled = folders.isNotEmpty && folders.any((f) => f.enabled == true);

    // Check storage permission if folders are enabled (skip for auto-save)
    if (checkPermissions && hasFoldersEnabled) {
      final hasPermission = await StoragePermissionService.hasStoragePermission();
      if (!mounted) return;
      if (!hasPermission) {
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Storage Permission Required'),
            content: const Text(
              'You have enabled folders for background sync, but the app doesn\'t have '
              '"All files access" permission.\n\n'
              'Background folder sync will not work without this permission.\n\n'
              'Would you like to grant it now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (shouldRequest == true) {
          await StoragePermissionService.requestStoragePermission();
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
        }
      }
    }

    // Handle floating bubble permission before saving (skip for auto-save)
    if (checkPermissions && _showFloatingBubble) {
      final hasOverlay = await canDrawOverlays();
      if (!mounted) return;
      if (!hasOverlay) {
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Overlay Permission Required'),
            content: const Text(
              'The floating bubble needs "Display over other apps" permission '
              'to appear on top of other apps.\n\n'
              'Would you like to grant it now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (shouldRequest == true) {
          await requestOverlayPermission();
          await Future.delayed(const Duration(milliseconds: 800));
          if (!mounted) return;
          final granted = await canDrawOverlays();
          if (mounted) {
            if (granted) {
              setState(() { _showFloatingBubble = true; });
              _showSnackBar('Overlay permission granted - floating bubble enabled');
            } else {
              setState(() { _showFloatingBubble = false; });
              _showSnackBar('Overlay permission not granted - bubble disabled');
            }
          }
        } else if (mounted) {
          setState(() { _showFloatingBubble = false; });
        }
      }
    }

    if (!mounted) return;
    await settings.saveSettings(
      backendUrl: _backendUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      useBackgroundService: _useBackgroundService,
      defaultTags: _defaultTagsController.text,
      defaultSafety: _selectedSafety,
      skipTagging: _skipTagging,
      notifyOnFolderSync: _notifyOnFolderSync,
      deleteMediaAfterSync: _deleteMediaAfterSync,
      showPersistentNotification: _showPersistentNotification,
      showFloatingBubble: _showFloatingBubble,
      folderSyncIntervalSeconds: _folderSyncIntervalSeconds,
      szuruUser: _szuruUser,
    );
    if (!mounted) return;

    final folderSyncEnabled = hasFoldersEnabled && _showPersistentNotification;
    if (folderSyncEnabled) {
      await startCompanionForegroundService(
        folderSyncEnabled: true,
        bubbleEnabled: _showFloatingBubble && folderSyncEnabled,
        statusBody: buildCompanionNotificationBody(
          folderSyncOn: true,
          bubbleOn: _showFloatingBubble && folderSyncEnabled,
        ),
      );
      if (!mounted) return;
      await stopFloatingBubbleService();
    } else {
      if (_showFloatingBubble) {
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
      if (!mounted) return;
      await stopFloatingBubbleService();
    }
    if (!mounted) return;

    if (hasFoldersEnabled) {
      try {
        await scheduleFolderScanTask();
      } catch (e) {
        debugPrint('[Main] Error scheduling folder scan in save: $e');
      }
    } else {
      try {
        await cancelFolderScanTask();
      } catch (e) {
        debugPrint('[Main] Error cancelling folder scan in save: $e');
      }
    }
    if (!mounted) return;

    _syncSettingsFields();
    if (mounted) _showSnackBar('Settings saved');
    } catch (e, stackTrace) {
      debugPrint('[Main] _saveSettingsInternal error: $e');
      debugPrint('[Main] Stack trace: $stackTrace');
      if (mounted) {
        final msg = e.toString().split('\n').first;
        final reason = msg.length > 80 ? '${msg.substring(0, 77)}...' : msg;
        _showSnackBar('Failed to save settings: $reason', duration: const Duration(seconds: 5));
      }
    }
  }

  void _showShareTestDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test share URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://example.com/image.jpg',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processShare(controller.text.trim());
            },
            child: const Text('Queue'),
          ),
        ],
      ),
    );
  }
}

Widget _buildStatCard(String label, int value, Color color) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

String _relativeTime(DateTime timestamp) {
  final diff = DateTime.now().difference(timestamp);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _AppHealthSection extends StatefulWidget {
  const _AppHealthSection();

  @override
  State<_AppHealthSection> createState() => _AppHealthSectionState();
}

class _AppHealthSectionState extends State<_AppHealthSection> {
  BatteryRestrictionSnapshot? _snapshot;
  int _enabledFolderCount = 0;
  bool _loading = true;
  bool _hasStoragePermission = false;
  bool _hasOverlayPermission = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsModel>();
    _load(settings);
  }

  Future<void> _load(SettingsModel settings, {bool afterReturningFromSettings = false}) async {
    if (afterReturningFromSettings) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
    }
    final snapshot = await BatteryOptimizationHelper.getBatteryRestrictionSnapshot();
    final folders = await settings.getScheduledFolders();
    final enabled = folders.where((f) => f.enabled).length;
    final hasStorage = await StoragePermissionService.hasStoragePermission();
    final hasOverlay = await canDrawOverlays();
    if (mounted) {
      setState(() {
        _snapshot = snapshot;
        _enabledFolderCount = enabled;
        _hasStoragePermission = hasStorage;
        _hasOverlayPermission = hasOverlay;
        _loading = false;
      });
    }
  }

  Future<void> _fixBatteryOptimization() async {
    final outcome = await BatteryOptimizationHelper.ensureOptimizationDisabledDetailed(
      openSettingsIfDirectRequestNotPossible: true,
    );
    if (!mounted) return;
    final message = switch (outcome.status) {
      OptimizationOutcomeStatus.alreadyDisabled => 'Already allowed.',
      OptimizationOutcomeStatus.disabledAfterPrompt => 'Battery optimization disabled.',
      OptimizationOutcomeStatus.settingsOpened => 'Please disable battery optimization for this app.',
      OptimizationOutcomeStatus.unsupported => 'Not available on this device.',
      OptimizationOutcomeStatus.failed => 'Could not open settings.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (mounted) _load(context.read<SettingsModel>(), afterReturningFromSettings: true);
  }

  Future<void> _requestStoragePermission() async {
    final hasPermission = await StoragePermissionService.hasStoragePermission();
    if (hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission already granted')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Show explanation dialog first
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage Permission Required'),
        content: const Text(
          'SzuruCompanion needs "All files access" permission to sync folders in the background.\n\n'
          'This allows the app to automatically upload media files even when the app is closed.\n\n'
          'You\'ll be taken to Android settings where you need to toggle ON the permission for SzuruCompanion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );

    if (shouldRequest == true && mounted) {
      try {
        await StoragePermissionService.requestStoragePermission();
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _load(context.read<SettingsModel>(), afterReturningFromSettings: true);
      } catch (e) {
        debugPrint('[Main] _requestStoragePermission error: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not complete storage permission flow')));
      }
    }
  }

  Future<void> _requestOverlayPermission() async {
    final hasPermission = await canDrawOverlays();
    if (hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Overlay permission already granted')),
        );
      }
      return;
    }

    if (!mounted) return;

    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Overlay Permission Required'),
        content: const Text(
          'SzuruCompanion needs "Display over other apps" permission to show the floating bubble '
          'on top of other apps.\n\n'
          'You\'ll be taken to Android settings where you need to toggle ON the permission for SzuruCompanion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );

    if (shouldRequest == true && mounted) {
      try {
        await requestOverlayPermission();
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        final granted = await canDrawOverlays();
        if (!mounted) return;
        final settings = context.read<SettingsModel>();
        if (granted && settings.showFloatingBubble && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Overlay permission granted')),
          );
        }
        if (mounted) _load(context.read<SettingsModel>(), afterReturningFromSettings: true);
      } catch (e) {
        debugPrint('[Main] _requestOverlayPermission error: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not complete overlay permission flow')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 24,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    final supported = _snapshot?.isSupported ?? false;
    final batteryOn = supported && (_snapshot!.isBatteryOptimizationEnabled);
    final storageGranted = _hasStoragePermission;

    return Column(
      children: [
        // Storage Permission Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      storageGranted ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                      size: 20,
                      color: storageGranted
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Storage permission',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (!storageGranted)
                      TextButton(
                        onPressed: _requestStoragePermission,
                        child: const Text('Grant'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  storageGranted
                      ? 'All files access granted – folder sync enabled.'
                      : 'Required for background folder sync to work.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Overlay Permission Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _hasOverlayPermission ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                      size: 20,
                      color: _hasOverlayPermission
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Overlay permission',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (!_hasOverlayPermission)
                      TextButton(
                        onPressed: _requestOverlayPermission,
                        child: const Text('Grant'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _hasOverlayPermission
                      ? 'Display over other apps granted – floating bubble is available.'
                      : 'Required for the floating bubble overlay to work.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Battery Optimization Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      batteryOn ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      size: 20,
                      color: batteryOn
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Battery optimization',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (supported && batteryOn)
                      TextButton(
                        onPressed: _fixBatteryOptimization,
                        child: const Text('Fix'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  !supported
                      ? 'Battery status not available on this device.'
                      : batteryOn
                          ? 'On – may delay or prevent folder sync in background.'
                          : 'Off – folder sync can run reliably.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (_enabledFolderCount > 0) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Folder sync: $_enabledFolderCount folder(s) watched. Background scan ${_formatFolderSyncIntervalShort(context.watch<SettingsModel>().folderSyncIntervalSeconds)}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
