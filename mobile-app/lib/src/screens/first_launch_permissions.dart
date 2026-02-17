import 'package:battery_optimization_helper/battery_optimization_helper.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/floating_bubble_service.dart';
import '../services/notification_service.dart';
import '../services/storage_permission.dart';

const _keyStep = 'first_launch_permission_step';

/// Runs the first-launch permission prompt sequence if not yet completed.
/// Each dialog explains why we need the permission; Grant opens Android settings, Cancel skips (no re-prompt).
Future<void> runFirstLaunchPermissionFlowIfNeeded(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final step = prefs.getInt(_keyStep) ?? 0;
  if (step >= 4) return;
  if (!context.mounted) return;

  await _showStepDialog(context, step, prefs);
}

Future<void> _showStepDialog(BuildContext context, int step, SharedPreferences prefs) async {
  if (step >= 4) return;

  final (title, body, onGrant) = switch (step) {
    0 => (
        'Battery optimization',
        'To run folder sync and background uploads reliably, this app needs to be exempt from battery optimization.\n\n'
            'Granting this allows the app to work when the screen is off.',
        () async {
          await BatteryOptimizationHelper.ensureOptimizationDisabledDetailed(
            openSettingsIfDirectRequestNotPossible: true,
          );
        },
      ),
    1 => (
        'Display over other apps',
        'The floating bubble lets you queue a URL from your clipboard without opening the app.\n\n'
            'This permission is required to show the bubble on top of other apps.',
        () async {
          await requestOverlayPermission();
        },
      ),
    2 => (
        'Notifications',
        'The app uses notifications to show upload status, folder sync results, and connection status.\n\n'
            'Granting notification permission allows these alerts.',
        () async {
          await NotificationService.instance.requestNotificationPermission();
        },
      ),
    3 => (
        'Storage access',
        'Folder sync uploads files from chosen folders in the background.\n\n'
            'All files access is required to read and upload those files.',
        () async {
          await StoragePermissionService.requestStoragePermission();
        },
      ),
    _ => throw StateError('Invalid step'),
  };

  if (!context.mounted) return;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Grant'),
        ),
      ],
    ),
  );

  if (result == true) {
    await onGrant();
  }

  await prefs.setInt(_keyStep, step + 1);
  if (step + 1 < 4 && context.mounted) {
    await Future.delayed(const Duration(milliseconds: 400));
    if (context.mounted) await _showStepDialog(context, step + 1, prefs);
  }
}
