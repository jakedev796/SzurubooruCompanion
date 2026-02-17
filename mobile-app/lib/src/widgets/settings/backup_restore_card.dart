import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:provider/provider.dart';

import '../../services/settings_model.dart';
import '../../theme/app_theme.dart';
import '../section_card.dart';

class BackupRestoreCard extends StatelessWidget {
  const BackupRestoreCard({
    super.key,
    required this.isRestoreInProgress,
    required this.onShowSnackBar,
    required this.onRestore,
  });

  final bool isRestoreInProgress;
  final void Function(String message) onShowSnackBar;
  final Future<bool> Function(String backupJson) onRestore;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsModel>();
    return SectionCard(
      title: 'Backup & Restore',
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
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
                  if (directoryPath == null || !context.mounted) return;
                  final filePath = await settings.backupSettingsToDirectory(directoryPath);
                  if (context.mounted) {
                    onShowSnackBar(
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
                onPressed: isRestoreInProgress
                    ? null
                    : () async {
                        try {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['json'],
                            allowMultiple: false,
                            withData: true,
                          );
                          if (result == null || result.files.isEmpty || !context.mounted) return;
                          final file = result.files.single;
                          String? backupJson;
                          if (file.bytes != null && file.bytes!.isNotEmpty) {
                            backupJson = String.fromCharCodes(file.bytes!);
                          } else if (file.path != null) {
                            final f = File(file.path!);
                            if (await f.exists()) backupJson = await f.readAsString();
                          }
                          if (backupJson == null || backupJson.isEmpty) {
                            if (context.mounted) onShowSnackBar('Could not read backup file');
                            return;
                          }
                          if (!context.mounted) return;
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
                          if (confirmed != true || !context.mounted) return;

                          final success = await onRestore(backupJson);

                          if (!context.mounted) return;
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
                              debugPrint('[BackupRestore] Restore success dialog error: $e');
                              if (context.mounted) onShowSnackBar('Settings restored. Restart the app to apply.');
                            }
                          } else {
                            if (context.mounted) onShowSnackBar('Failed to restore settings');
                          }
                        } catch (e) {
                          debugPrint('[Settings] Restore flow error: $e');
                          if (context.mounted) onShowSnackBar('Restore failed');
                        }
                      },
                icon: const Icon(Icons.restore),
                label: const Text('Restore'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
