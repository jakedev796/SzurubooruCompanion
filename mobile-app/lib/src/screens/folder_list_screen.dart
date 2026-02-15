import 'package:battery_optimization_helper/battery_optimization_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scheduled_folder.dart';
import '../services/settings_model.dart';
import '../services/background_task.dart';
import '../theme/app_theme.dart';
import 'folder_config_screen.dart';

/// Screen for displaying and managing scheduled folders
class FolderListScreen extends StatefulWidget {
  const FolderListScreen({super.key});

  @override
  State<FolderListScreen> createState() => _FolderListScreenState();
}

class _FolderListScreenState extends State<FolderListScreen> {
  List<ScheduledFolder> _folders = [];
  bool _isLoading = true;
  bool _backgroundTaskEnabled = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    
    final settings = context.read<SettingsModel>();
    final folders = await settings.getScheduledFolders();
    
    if (mounted) {
      setState(() {
        _folders = folders;
        _isLoading = false;
        _backgroundTaskEnabled = _folders.any((f) => f.enabled);
      });
      if (_folders.any((f) => f.enabled)) {
        await scheduleFolderScanTask();
      }
    }
  }

  Future<void> _toggleBackgroundTask(bool enabled) async {
    if (enabled) {
      await scheduleFolderScanTask();
      if (mounted) await _maybePromptBatteryOptimization();
    } else {
      await cancelFolderScanTask();
    }

    setState(() => _backgroundTaskEnabled = enabled);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled
              ? 'Background scanning enabled'
              : 'Background scanning disabled'),
        ),
      );
    }
  }

  Future<void> _maybePromptBatteryOptimization() async {
    final snapshot = await BatteryOptimizationHelper.getBatteryRestrictionSnapshot();
    if (!snapshot.isSupported || !snapshot.isBatteryOptimizationEnabled) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Battery optimization'),
        content: const Text(
          'For reliable folder sync in the background, disable battery optimization for SzuruCompanion. '
          'Otherwise sync may be delayed or skipped when the app is not open.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _requestBatteryOptimizationOff();
            },
            child: const Text('Fix'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFolder(ScheduledFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Are you sure you want to delete "${folder.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final settings = context.read<SettingsModel>();
      await settings.removeScheduledFolder(folder.id);
      await _loadFolders();
    }
  }

  Future<void> _requestBatteryOptimizationOff() async {
    final outcome = await BatteryOptimizationHelper.ensureOptimizationDisabledDetailed(
      openSettingsIfDirectRequestNotPossible: true,
    );
    if (!mounted) return;
    final message = switch (outcome.status) {
      OptimizationOutcomeStatus.alreadyDisabled => 'App is already allowed to run in background.',
      OptimizationOutcomeStatus.disabledAfterPrompt => 'Battery optimization disabled for this app.',
      OptimizationOutcomeStatus.settingsOpened => 'Please disable battery optimization for SzuruCompanion.',
      OptimizationOutcomeStatus.unsupported => 'Battery optimization settings are not available on this device.',
      OptimizationOutcomeStatus.failed => 'Could not open battery settings.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    try {
      final outcome = await triggerManualScanAll();
      if (mounted) {
        if (outcome.uploaded > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                outcome.uploaded == 1
                    ? '1 file uploaded'
                    : '${outcome.uploaded} files uploaded',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No files to sync')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _toggleFolderEnabled(ScheduledFolder folder) async {
    final settings = context.read<SettingsModel>();
    final newEnabledState = !folder.enabled;
    
    await settings.updateScheduledFolder(folder.copyWith(
      enabled: newEnabledState,
    ));
    
    // Update background task state based on enabled folders
    await _loadFolders();
    
    // If this was the first enabled folder, ensure background task is scheduled
    // If no folders are enabled, cancel the background task
    final hasEnabledFolders = _folders.any((f) => f.enabled);
    if (hasEnabledFolders && !_backgroundTaskEnabled) {
      await scheduleFolderScanTask();
      setState(() => _backgroundTaskEnabled = true);
      if (mounted) await _maybePromptBatteryOptimization();
    } else if (!hasEnabledFolders && _backgroundTaskEnabled) {
      await cancelFolderScanTask();
      setState(() => _backgroundTaskEnabled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scheduled Folders'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync now',
            onPressed: _isSyncing ? null : _syncNow,
          ),
          Switch(
            value: _backgroundTaskEnabled,
            onChanged: _toggleBackgroundTask,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
              ? _buildEmptyState()
              : _buildFolderList(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FolderConfigScreen(),
            ),
          );
          await _loadFolders();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off,
            size: 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No scheduled folders',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add a folder for automatic uploads',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildFolderList(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final intervalSeconds = settings.folderSyncIntervalSeconds;
    final nextRun = getNextFolderSyncRunTime(intervalSeconds);
    final nextRunText = formatNextFolderSync(nextRun);

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        if (_folders.any((f) => f.enabled))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Next sync: $nextRunText',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ...List.generate(_folders.length, (index) {
          final folder = _folders[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: Icon(
                folder.enabled ? Icons.folder : Icons.folder_off,
                color: folder.enabled ? null : Theme.of(context).disabledColor,
              ),
              title: Text(folder.name),
              subtitle: folder.defaultTags?.isNotEmpty == true
                  ? Text('Tags: ${folder.defaultTags!.join(", ")}')
                  : null,
              trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: folder.enabled,
                  onChanged: (_) => _toggleFolderEnabled(folder),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _deleteFolder(folder),
                ),
              ],
            ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FolderConfigScreen(folder: folder),
                  ),
                );
                await _loadFolders();
              },
            ),
          );
        }),
      ],
    );
  }
}
