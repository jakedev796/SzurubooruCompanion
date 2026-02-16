import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'backend_client.dart';
import 'folder_scanner.dart';
import '../models/scheduled_folder.dart';
import 'companion_foreground_service.dart';
import 'notification_service.dart';
import 'settings_model.dart';

const _channel = MethodChannel('com.szurubooru.szuruqueue/share');

/// Minimum sync interval (15 minutes)
const int kMinSyncIntervalSeconds = 900;

/// Maximum sync interval (7 days)
const int kMaxSyncIntervalSeconds = 604800;

/// Task name for background uploads from share intents
const String kUploadTask = 'upload-task';

/// Next run at clock-aligned boundary for [intervalSeconds].
/// E.g. 30 min -> next :00 or :30; 15 min -> next :00, :15, :30, :45.
DateTime getNextFolderSyncRunTime(int intervalSeconds) {
  final now = DateTime.now();
  final minuteOfDay = now.hour * 60 + now.minute;
  final intervalMinutes = (intervalSeconds ~/ 60).clamp(15, 10080);

  int nextSlotMinutes;
  if (intervalMinutes >= 10080) {
    nextSlotMinutes = minuteOfDay == 0 ? 0 : 10080;
  } else if (intervalMinutes >= 1440) {
    nextSlotMinutes = minuteOfDay == 0 ? 0 : 1440;
  } else {
    nextSlotMinutes =
        ((minuteOfDay / intervalMinutes).floor() + 1) * intervalMinutes;
  }

  var next = DateTime(
    now.year,
    now.month,
    now.day,
    0,
    0,
    0,
  ).add(Duration(minutes: nextSlotMinutes));
  if (next.isBefore(now) || next.difference(now).inSeconds < 60) {
    next = next.add(
      Duration(minutes: intervalMinutes >= 1440 ? 1440 : intervalMinutes),
    );
  }
  return next;
}

/// Current clock-aligned boundary start (epoch seconds). All folders run at this boundary.
int currentBoundaryStartSeconds(int intervalSeconds) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final interval = intervalSeconds.clamp(900, 604800);
  return (now ~/ interval) * interval;
}

/// True if folder should run this boundary (enabled and not yet run for current boundary).
bool isFolderDueForBoundary(ScheduledFolder folder, int currentBoundaryStart) {
  if (!folder.enabled) return false;
  return folder.lastRunTimestamp < currentBoundaryStart;
}

String formatNextFolderSync(DateTime next) {
  final now = DateTime.now();
  if (next.difference(now).inMinutes < 60) {
    return 'Next at ${next.hour}:${next.minute.toString().padLeft(2, '0')}';
  }
  return 'Next at ${next.month}/${next.day} ${next.hour}:${next.minute.toString().padLeft(2, '0')}';
}

/// Callback dispatcher for WorkManager background tasks.
/// Handles both alarm-triggered folder scans and share intent uploads.
/// Runs in a separate Dart isolate with MANAGE_EXTERNAL_STORAGE permission.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundIsolate] ======================================');
    debugPrint('[BackgroundIsolate] Task started: $task');
    debugPrint('[BackgroundIsolate] Time: ${DateTime.now()}');
    if (inputData != null) {
      debugPrint('[BackgroundIsolate] Input data: $inputData');
    }
    debugPrint('[BackgroundIsolate] ======================================');

    try {
      // Handle upload task from share intents
      if (task == kUploadTask && inputData != null) {
        final url = inputData['url'] as String?;
        final backendUrl = inputData['backendUrl'] as String?;
        final apiKey = inputData['apiKey'] as String? ?? '';
        final tags = (inputData['tags'] as List?)?.cast<String>() ?? [];
        final safety = inputData['safety'] as String? ?? 'unsafe';
        final skipTagging = inputData['skipTagging'] as bool? ?? false;
        final szuruUser = inputData['szuruUser'] as String? ?? '';

        if (url == null || backendUrl == null) {
          debugPrint(
            '[BackgroundIsolate] Upload task missing required parameters',
          );
          return Future.value(false);
        }

        try {
          final client = BackendClient(baseUrl: backendUrl, apiKey: apiKey);
          await client.enqueueFromUrl(
            url: url,
            tags: tags,
            safety: safety,
            skipTagging: skipTagging,
            szuruUser: szuruUser.isNotEmpty ? szuruUser : null,
          );
          await NotificationService.instance.showUploadSuccess(url);
          debugPrint('[BackgroundIsolate] Upload task completed: $url');
          return Future.value(true);
        } catch (e) {
          debugPrint('[BackgroundIsolate] Upload task error: $e');
          await NotificationService.instance.showUploadError(
            'Background enqueue failed: $e',
          );
          return Future.value(false);
        }
      }

      // Handle folder scan (triggered by AlarmManager)
      final outcome = await processScheduledFolders();
      debugPrint(
        '[BackgroundIsolate] Folder scan complete: uploaded=${outcome.uploaded}, success=${outcome.success}',
      );

      // Update notification with results
      final settings = SettingsModel();
      await settings.loadSettings();
      if (settings.showPersistentNotification) {
        final next = getNextFolderSyncRunTime(
          settings.folderSyncIntervalSeconds,
        );
        await updateCompanionNotification(
          statusBody: buildCompanionNotificationBody(
            connectionText: 'Next sync: ${formatNextFolderSync(next)}',
            folderSyncOn: true,
            bubbleOn: settings.showFloatingBubble,
          ),
        );
      }

      // Note: Next alarm is automatically rescheduled by FolderSyncAlarmReceiver
      // before this task runs, so we don't need to reschedule here

      debugPrint('[BackgroundIsolate] Task complete');
      return outcome.success;
    } catch (e, stackTrace) {
      debugPrint('[BackgroundIsolate] Task failed: $e');
      debugPrint('[BackgroundIsolate] Stack trace: $stackTrace');
      return false;
    }
  });
}

// Note: _rescheduleNextAlarm() removed - now handled natively by FolderSyncAlarmReceiver
// The receiver reschedules the next alarm before running the task, ensuring
// periodic execution continues even if the task fails

/// Result of processScheduledFolders: success flag and total files uploaded
typedef FolderScanOutcome = ({bool success, int uploaded});

/// Process all scheduled folders in background (only due folders).
/// Runs only at clock-aligned boundaries for the effective interval (e.g. :00, :30 for 30 min).
/// Allows ±2 minute slack to account for WorkManager timing variability.
Future<FolderScanOutcome> processScheduledFolders() async {
  try {
    debugPrint('[FolderSync] processScheduledFolders() started');
    final settings = SettingsModel();
    await settings.loadSettings();

    final serverUrl = settings.backendUrl;
    final apiKey = settings.apiKey;

    if (serverUrl.isEmpty) {
      debugPrint(
        '[FolderSync] Server URL not configured, skipping folder scan',
      );
      return (success: true, uploaded: 0);
    }

    final intervalSeconds = settings.folderSyncIntervalSeconds.clamp(
      900,
      604800,
    );
    final boundaryStart = currentBoundaryStartSeconds(intervalSeconds);
    final intervalMinutes = (intervalSeconds ~/ 60).clamp(15, 10080);
    final now = DateTime.now();
    final minuteOfDay = now.hour * 60 + now.minute;

    // Calculate how close we are to the expected clock boundary
    // This is informational only - we rely on per-folder lastRunTimestamp to prevent duplicates
    final minuteInSlot = minuteOfDay % intervalMinutes;
    final minutesToNextBoundary =
        (intervalMinutes - minuteInSlot) % intervalMinutes;
    final minutesFromLastBoundary = minuteInSlot;

    debugPrint(
      '[FolderSync] Timing info: intervalMinutes=$intervalMinutes, '
      'minuteOfDay=$minuteOfDay, minutesFromLastBoundary=$minutesFromLastBoundary, '
      'minutesToNextBoundary=$minutesToNextBoundary, boundaryStart=$boundaryStart',
    );

    // Note: We don't enforce strict timing here. The per-folder lastRunTimestamp
    // check (via isFolderDueForBoundary) prevents duplicate syncs for the same folder.
    // This allows WorkManager to fire whenever it wants (accounting for battery optimization,
    // Doze mode, etc.) while still preventing duplicate work.

    final backendClient = BackendClient(baseUrl: serverUrl, apiKey: apiKey);

    final folders = await settings.getScheduledFolders();
    debugPrint('[FolderSync] Total folders configured: ${folders.length}');

    final dueFolders = folders
        .where((f) => isFolderDueForBoundary(f, boundaryStart))
        .toList();

    if (dueFolders.isEmpty) {
      debugPrint(
        '[FolderSync] No folders due for processing at boundary $boundaryStart',
      );
      for (final folder in folders) {
        debugPrint(
          '[FolderSync]   - ${folder.name}: enabled=${folder.enabled}, '
          'lastRun=${folder.lastRunTimestamp}, due=${isFolderDueForBoundary(folder, boundaryStart)}',
        );
      }
      return (success: true, uploaded: 0);
    }

    debugPrint(
      '[FolderSync] Processing ${dueFolders.length} due folders in background',
    );
    for (final folder in dueFolders) {
      debugPrint('[FolderSync]   - ${folder.name}: enabled=${folder.enabled}');
    }

    final scanner = FolderScanner(
      backendClient: backendClient,
      settings: settings,
    );

    int totalUploaded = 0;
    int totalErrors = 0;
    for (final folder in dueFolders) {
      try {
        debugPrint('[FolderSync] Processing folder: ${folder.name}');
        final result = await scanner.processFolder(folder);
        totalUploaded += result.filesUploaded;
        await settings.updateFolderLastRun(folder.id, boundaryStart);
        debugPrint(
          '[FolderSync] Folder ${folder.name}: found ${result.filesFound}, '
          'uploaded ${result.filesUploaded}',
        );
      } catch (e, stackTrace) {
        totalErrors++;
        debugPrint('[FolderSync] Error processing folder ${folder.name}: $e');
        debugPrint('[FolderSync] Stack trace: $stackTrace');
      }
    }

    await settings.setLastFolderSync(totalUploaded);
    debugPrint(
      '[FolderSync] Sync complete: $totalUploaded files uploaded, $totalErrors errors',
    );

    if (settings.notifyOnFolderSync && totalUploaded > 0) {
      await NotificationService.instance.showFolderSyncComplete(totalUploaded);
    }

    return (success: totalErrors == 0, uploaded: totalUploaded);
  } catch (e, stackTrace) {
    debugPrint('[FolderSync] Critical error in background folder scan: $e');
    debugPrint('[FolderSync] Stack trace: $stackTrace');
    return (success: false, uploaded: 0);
  }
}

/// Initialize background task scheduler
/// Registers the callback dispatcher for WorkManager isolate execution
Future<void> initializeBackgroundTasks() async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);
  debugPrint('[BackgroundTask] WorkManager callback dispatcher initialized');
  debugPrint('[BackgroundTask] Using AlarmManager for scheduling');
}

/// Check if we have exact alarm permission (Android 12+)
Future<bool> canScheduleExactAlarms() async {
  try {
    final result = await _channel.invokeMethod<bool>('canScheduleExactAlarms');
    return result ?? false;
  } catch (e) {
    debugPrint('[BackgroundTask] Error checking exact alarm permission: $e');
    return false;
  }
}

/// Request exact alarm permission (Android 12+)
Future<void> requestExactAlarmPermission() async {
  try {
    await _channel.invokeMethod('requestExactAlarmPermission');
  } catch (e) {
    debugPrint('[BackgroundTask] Error requesting exact alarm permission: $e');
  }
}

/// Schedule folder sync using AlarmManager for reliable exact-time execution.
/// Uses setExactAndAllowWhileIdle() to fire even in Doze mode.
Future<void> scheduleFolderScanTask() async {
  try {
    final settings = SettingsModel();
    await settings.loadSettings();
    final folders = await settings.getScheduledFolders();
    final hasFoldersEnabled = folders.any((f) => f.enabled);
    
    if (!hasFoldersEnabled) {
      debugPrint('[BackgroundTask] No enabled folders, skipping schedule');
      return;
    }
    
    final intervalSeconds = settings.folderSyncIntervalSeconds.clamp(
      kMinSyncIntervalSeconds,
      kMaxSyncIntervalSeconds,
    );

    debugPrint('[BackgroundTask] ========================================');
    debugPrint('[BackgroundTask] Scheduling folder sync with AlarmManager');
    debugPrint('[BackgroundTask] Interval: ${intervalSeconds}s');

    // Check for exact alarm permission on Android 12+
    final canSchedule = await canScheduleExactAlarms();
    if (!canSchedule) {
      debugPrint('[BackgroundTask] WARNING: Cannot schedule exact alarms!');
      debugPrint('[BackgroundTask] Requesting permission...');
      await requestExactAlarmPermission();
      return;
    }

    // Cancel any existing alarm first
    await cancelFolderScanTask();
    debugPrint('[BackgroundTask] Cancelled existing alarm');

    // Schedule the alarm via native code
    try {
      await _channel.invokeMethod('scheduleAlarmManagerSync', {
        'intervalSeconds': intervalSeconds,
      });
      debugPrint('[BackgroundTask] AlarmManager sync scheduled');
    } catch (e) {
      debugPrint('[BackgroundTask] Error scheduling alarm: $e');
      return;
    }

    if (settings.showPersistentNotification) {
      final granted = await NotificationService.instance
          .requestNotificationPermission();
      if (granted != false) {
        debugPrint('[BackgroundTask] Starting foreground service...');
        await startCompanionForegroundService(
          folderSyncEnabled: true,
          bubbleEnabled: settings.showFloatingBubble,
          statusBody: buildCompanionNotificationBody(
            folderSyncOn: true,
            bubbleOn: settings.showFloatingBubble,
          ),
        );
        debugPrint('[BackgroundTask] Foreground service started');
      } else {
        debugPrint('[BackgroundTask] WARNING: Notification permission not granted!');
      }
    }

    final nextSync = getNextFolderSyncRunTime(intervalSeconds);
    debugPrint('[BackgroundTask] Next sync scheduled for: ${nextSync.toString()}');
    debugPrint('[BackgroundTask] ========================================');
  } catch (e, stackTrace) {
    debugPrint('[BackgroundTask] Error in scheduleFolderScanTask: $e');
    debugPrint('[BackgroundTask] Stack trace: $stackTrace');
  }
}

/// Cancel the AlarmManager folder sync
Future<void> cancelFolderScanTask() async {
  debugPrint('[BackgroundTask] Cancelling AlarmManager sync');
  try {
    await _channel.invokeMethod('cancelAlarmManagerSync');
  } catch (e) {
    debugPrint('[BackgroundTask] Error cancelling alarm: $e');
  }
  await stopCompanionForegroundService();
  debugPrint('[BackgroundTask] AlarmManager sync cancelled');
}

/// Debug: Print detailed status of background sync
Future<void> debugBackgroundSyncStatus() async {
  debugPrint('[BackgroundTask] ========== BACKGROUND SYNC STATUS ==========');

  final settings = SettingsModel();
  await settings.loadSettings();

  final folders = await settings.getScheduledFolders();
  final enabledFolders = folders.where((f) => f.enabled).toList();

  debugPrint('[BackgroundTask] Enabled folders: ${enabledFolders.length}');
  for (final folder in enabledFolders) {
    final next = getNextFolderSyncRunTime(settings.folderSyncIntervalSeconds);
    debugPrint('[BackgroundTask]   - ${folder.name}: lastRun=${folder.lastRunTimestamp}');
    debugPrint('[BackgroundTask]     Next sync: ${next.toString()}');
  }

  debugPrint('[BackgroundTask] Persistent notification: ${settings.showPersistentNotification}');
  debugPrint('[BackgroundTask] Folder sync interval: ${settings.folderSyncIntervalSeconds}s');
  debugPrint('[BackgroundTask] Scheduling method: AlarmManager + WorkManager hybrid');
  debugPrint('[BackgroundTask] ============================================');
}

/// Manually trigger a folder scan (only folders that are due)
Future<List<ScanResult>> triggerManualScan() async {
  return _runFolderScan(onlyDue: true, allowDelete: false);
}

/// Manually trigger a folder scan for all enabled folders (ignores due time).
/// When [allowDelete] is true, source files may be deleted after upload if setting is on.
Future<FolderScanOutcome> triggerManualScanAll({
  bool allowDelete = true,
}) async {
  final settings = SettingsModel();
  await settings.loadSettings();
  final results = await _runFolderScan(
    onlyDue: false,
    allowDelete: allowDelete,
  );
  final totalUploaded = results.fold<int>(0, (s, r) => s + r.filesUploaded);
  if (settings.notifyOnFolderSync && totalUploaded > 0) {
    await NotificationService.instance.showFolderSyncComplete(totalUploaded);
  }
  return (success: true, uploaded: totalUploaded);
}

Future<List<ScanResult>> _runFolderScan({
  required bool onlyDue,
  bool allowDelete = false,
}) async {
  try {
    final settings = SettingsModel();
    await settings.loadSettings();

    final serverUrl = settings.backendUrl;
    final apiKey = settings.apiKey;

    if (serverUrl.isEmpty) {
      debugPrint('Server URL not configured');
      return [];
    }

    final backendClient = BackendClient(baseUrl: serverUrl, apiKey: apiKey);

    final folders = await settings.getScheduledFolders();
    final intervalSeconds = settings.folderSyncIntervalSeconds.clamp(
      900,
      604800,
    );
    final boundaryStart = currentBoundaryStartSeconds(intervalSeconds);
    final toProcess = onlyDue
        ? folders
              .where((f) => isFolderDueForBoundary(f, boundaryStart))
              .toList()
        : folders.where((f) => f.enabled).toList();

    if (toProcess.isEmpty) {
      debugPrint(
        onlyDue ? 'No folders due for processing' : 'No enabled folders',
      );
      return [];
    }

    debugPrint('Manually processing ${toProcess.length} folders');

    final scanner = FolderScanner(
      backendClient: backendClient,
      settings: settings,
    );

    final results = <ScanResult>[];
    for (final folder in toProcess) {
      try {
        final result = await scanner.processFolder(
          folder,
          allowDelete: allowDelete,
        );
        results.add(result);
        debugPrint(
          'Folder ${folder.name}: found ${result.filesFound}, '
          'uploaded ${result.filesUploaded}',
        );
      } catch (e) {
        debugPrint('Error processing folder ${folder.name}: $e');
      }
    }

    return results;
  } catch (e) {
    debugPrint('Error in manual folder scan: $e');
    return [];
  }
}
