import 'package:flutter/material.dart';

import '../../screens/folder_list_screen.dart';
import '../../theme/app_theme.dart';
import '../section_card.dart';

class FolderSettingsCard extends StatelessWidget {
  const FolderSettingsCard({
    super.key,
    required this.isSyncingFolders,
    required this.notifyOnFolderSync,
    required this.deleteMediaAfterSync,
    required this.showPersistentNotification,
    required this.folderSyncIntervalSeconds,
    required this.onSyncNow,
    required this.onNotifyOnFolderSyncChanged,
    required this.onDeleteMediaAfterSyncChanged,
    required this.onShowPersistentNotificationChanged,
    required this.onFolderSyncIntervalChanged,
    required this.onAutoSave,
  });

  final bool isSyncingFolders;
  final bool notifyOnFolderSync;
  final bool deleteMediaAfterSync;
  final bool showPersistentNotification;
  final int folderSyncIntervalSeconds;
  final VoidCallback onSyncNow;
  final ValueChanged<bool> onNotifyOnFolderSyncChanged;
  final ValueChanged<bool> onDeleteMediaAfterSyncChanged;
  final ValueChanged<bool> onShowPersistentNotificationChanged;
  final ValueChanged<int> onFolderSyncIntervalChanged;
  final VoidCallback onAutoSave;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Folder Settings',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
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
          onPressed: isSyncingFolders ? null : onSyncNow,
          icon: isSyncingFolders
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(isSyncingFolders ? 'Syncing...' : 'Sync Folders Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Notify on folder sync'),
          subtitle: const Text(
            'Show a notification when folder sync runs and how many files were uploaded',
          ),
          value: notifyOnFolderSync,
          onChanged: (value) {
            onNotifyOnFolderSyncChanged(value);
            onAutoSave();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Delete media after folder sync'),
          subtitle: const Text(
            'Remove source files after upload. We try to delete in background; if that fails, files are deleted when you next open the app.',
          ),
          value: deleteMediaAfterSync,
          onChanged: (value) {
            onDeleteMediaAfterSyncChanged(value);
            onAutoSave();
          },
        ),
        if (!deleteMediaAfterSync)
          const Padding(
            padding: EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Text(
              'When disabled, only new files added since the last sync will be uploaded. Previously synced files are skipped based on their modification time.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Show persistent status notification'),
          subtitle: const Text(
            'Keep a notification in the status bar when folder sync is on (connectivity status).',
          ),
          value: showPersistentNotification,
          onChanged: (value) {
            onShowPersistentNotificationChanged(value);
            onAutoSave();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: folderSyncIntervalSeconds,
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
              onFolderSyncIntervalChanged(value);
              onAutoSave();
            }
          },
        ),
      ],
    );
  }
}
