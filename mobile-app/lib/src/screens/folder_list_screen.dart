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
        // Update background task state based on enabled folders
        _backgroundTaskEnabled = _folders.any((f) => f.enabled);
      });
    }
  }

  Future<void> _toggleBackgroundTask(bool enabled) async {
    if (enabled) {
      await scheduleFolderScanTask(
        frequency: const Duration(minutes: 15),
        requireNetwork: true,
        requireBatteryNotLow: true,
      );
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
      await scheduleFolderScanTask(
        frequency: const Duration(minutes: 15),
        requireNetwork: true,
        requireBatteryNotLow: true,
      );
      setState(() => _backgroundTaskEnabled = true);
    } else if (!hasEnabledFolders && _backgroundTaskEnabled) {
      await cancelFolderScanTask();
      setState(() => _backgroundTaskEnabled = false);
    }
  }

  String _formatNextRun(ScheduledFolder folder) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nextRun = folder.nextRunTimestamp;
    
    if (nextRun <= now) {
      return 'Due now';
    }
    
    final diff = nextRun - now;
    if (diff < 60) {
      return 'In $diff seconds';
    } else if (diff < 3600) {
      final mins = diff ~/ 60;
      return 'In $mins minute${mins == 1 ? '' : 's'}';
    } else if (diff < 86400) {
      final hours = diff ~/ 3600;
      return 'In $hours hour${hours == 1 ? '' : 's'}';
    } else {
      final days = diff ~/ 86400;
      return 'In $days day${days == 1 ? '' : 's'}';
    }
  }

  String _formatInterval(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      return '${seconds ~/ 60}m';
    } else if (seconds < 86400) {
      return '${seconds ~/ 3600}h';
    } else {
      return '${seconds ~/ 86400}d';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scheduled Folders'),
        actions: [
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
              : _buildFolderList(),
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

  Widget _buildFolderList() {
    return ListView.builder(
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: Icon(
              folder.enabled ? Icons.folder : Icons.folder_off,
              color: folder.enabled ? null : Theme.of(context).disabledColor,
            ),
            title: Text(folder.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Interval: ${_formatInterval(folder.intervalSeconds)}'),
                Text('Next run: ${_formatNextRun(folder)}'),
                if (folder.defaultTags?.isNotEmpty == true)
                  Text('Tags: ${folder.defaultTags!.join(", ")}'),
              ],
            ),
            isThreeLine: true,
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
      },
    );
  }
}
