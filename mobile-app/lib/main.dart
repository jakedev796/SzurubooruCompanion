import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'src/models/job.dart';
import 'src/screens/folder_list_screen.dart';
import 'src/services/app_state.dart';
import 'src/theme/app_theme.dart';
import 'src/services/backend_client.dart';
import 'src/services/background_task.dart';
import 'src/services/notification_service.dart';
import 'src/services/settings_model.dart';

const _statusFilters = ['pending', 'downloading', 'tagging', 'uploading', 'completed', 'failed', 'all'];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  
  // Initialize background tasks for folder scanning
  await initializeBackgroundTasks();

  final settingsModel = SettingsModel();
  await settingsModel.loadSettings();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsModel>.value(value: settingsModel),
        ChangeNotifierProxyProvider<SettingsModel, AppState>(
          create: (context) => AppState(settingsModel),
          update: (context, settings, previous) =>
              previous ?? AppState(settings),
        ),
      ],
      child: const SzuruCompanionApp(),
    ),
  );
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

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<FormState> _settingsFormKey = GlobalKey<FormState>();
  final TextEditingController _backendUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _defaultTagsController = TextEditingController();
  String _selectedSafety = 'unsafe';
  bool _useBackgroundService = true;
  bool _skipTagging = false;
  int _selectedIndex = 0;
  bool _isProcessingShare = false;
  bool _settingsInitialized = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsModel>();
    _selectedIndex = settings.isConfigured ? 0 : 2;
    ShareIntentService.setupMethodCallHandler(_handleShare);
    _checkInitialShare();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_settingsInitialized) {
      _syncSettingsFields();
      _settingsInitialized = true;
    }
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _apiKeyController.dispose();
    _defaultTagsController.dispose();
    super.dispose();
  }

  void _syncSettingsFields() {
    final settings = context.read<SettingsModel>();
    _backendUrlController.text = settings.backendUrl;
    _apiKeyController.text = settings.apiKey;
    _defaultTagsController.text = settings.defaultTags;
    _selectedSafety = settings.defaultSafety;
    _useBackgroundService = settings.useBackgroundService;
    _skipTagging = settings.skipTagging;
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
                  child: _buildJobCard(appState.jobs[index]),
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
    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _statusFilters
                .map(
                  (filter) => ChoiceChip(
                    label: Text(filter.capitalize()),
                    selected: appState.selectedStatus == filter,
                    onSelected: (_) => appState.updateStatusFilter(filter),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            onRefresh: appState.refreshJobs,
            child: appState.isLoadingJobs
                ? const Center(child: CircularProgressIndicator())
                : appState.jobs.isEmpty
                ? const Center(child: Text('No jobs in this status yet.'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: appState.jobs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _buildJobCard(appState.jobs[index]),
                  ),
          ),
        ),
      ],
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
            const Text(
              'Backend settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _backendUrlController,
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
              decoration: const InputDecoration(
                labelText: 'API Key (optional)',
                hintText: 'Leave empty if backend does not require authentication',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
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
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _defaultTagsController,
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
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveSettings,
              child: const Text('Save settings'),
            ),
            const SizedBox(height: 16),
            const Divider(),
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
            const SizedBox(height: 16),
            const Text(
              'Share workflow',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Share any remote URL into SzuruCompanion and it will automatically queue the link with your preferred tags and safety rating.',
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Real-time Updates',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'This app uses Server-Sent Events (SSE) for real-time job updates. '
              'No polling is required - updates are pushed instantly from the server.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard(Job job) {
    final tags = job.allTags;
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

  Future<void> _saveSettings() async {
    if (_settingsFormKey.currentState?.validate() != true) return;
    final settings = context.read<SettingsModel>();
    await settings.saveSettings(
      backendUrl: _backendUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      useBackgroundService: _useBackgroundService,
      defaultTags: _defaultTagsController.text,
      defaultSafety: _selectedSafety,
      skipTagging: _skipTagging,
    );
    _syncSettingsFields();
    _showSnackBar('Settings saved');
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

extension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
