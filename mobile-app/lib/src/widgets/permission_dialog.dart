import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Custom permission request dialog that explains WHY a permission is needed
class PermissionDialog extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onGrant;
  final VoidCallback onCancel;

  const PermissionDialog({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onGrant,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        description,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 16,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textMuted,
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: onGrant,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Grant'),
        ),
      ],
    );
  }

  /// Show notification permission dialog
  static Future<bool> showNotificationDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionDialog(
        title: 'Notification Permission',
        description: 'Notifications are needed to alert you when folder sync completes, when jobs finish uploading, or when errors occur. This helps you stay informed about your uploads without constantly checking the app.',
        icon: Icons.notifications,
        onGrant: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
    return result ?? false;
  }

  /// Show storage permission dialog
  static Future<bool> showStorageDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionDialog(
        title: 'Storage Permission',
        description: 'Storage permission is required for background folder sync to automatically scan and upload media files from your device. Without this permission, the app cannot access your media folders.',
        icon: Icons.folder,
        onGrant: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
    return result ?? false;
  }

  /// Show overlay permission dialog
  static Future<bool> showOverlayDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionDialog(
        title: 'Overlay Permission',
        description: 'Overlay permission allows the app to display a floating bubble that lets you quickly share media to Szurubooru from any app. This is optional but provides convenient quick-share functionality.',
        icon: Icons.bubble_chart,
        onGrant: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
    return result ?? false;
  }

  /// Show battery optimization dialog
  static Future<bool> showBatteryOptimizationDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionDialog(
        title: 'Battery Optimization',
        description: 'Disabling battery optimization ensures that background folder sync can run reliably without being killed by Android. This is important for scheduled automatic uploads to work consistently.',
        icon: Icons.battery_charging_full,
        onGrant: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
    return result ?? false;
  }
}
