import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'backend_client.dart';
import 'folder_scanner.dart';
import 'notification_service.dart';
import 'settings_model.dart';

/// Task name for the periodic folder scan
const String kFolderScanTask = 'folder_scan_task';

/// Task name for background uploads from share intents
const String kUploadTask = 'upload-task';

/// Callback dispatcher for background tasks
/// Handles both folder scan tasks and upload tasks
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('Background task started: $task');
    
    // Handle folder scan task
    if (task == kFolderScanTask) {
      return await processScheduledFolders();
    }
    
    // Handle upload task from share intents
    if (task == kUploadTask && inputData != null) {
      final url = inputData['url'] as String?;
      final backendUrl = inputData['backendUrl'] as String?;
      final apiKey = inputData['apiKey'] as String? ?? '';
      final tags = (inputData['tags'] as List?)?.cast<String>() ?? [];
      final safety = inputData['safety'] as String? ?? 'unsafe';
      final skipTagging = inputData['skipTagging'] as bool? ?? false;

      if (url == null || backendUrl == null) {
        debugPrint('Upload task missing required parameters: url or backendUrl');
        return Future.value(false);
      }

      try {
        final client = BackendClient(baseUrl: backendUrl, apiKey: apiKey);
        final result = await client.enqueueFromUrl(
          url: url,
          tags: tags,
          safety: safety,
          skipTagging: skipTagging,
        );

        if (result != null) {
          await NotificationService.instance.showUploadSuccess(url);
          debugPrint('Upload task completed successfully for: $url');
          return Future.value(true);
        } else {
          await NotificationService.instance.showUploadError(
            'Background enqueue failed',
          );
          debugPrint('Upload task failed: enqueueFromUrl returned null');
          return Future.value(false);
        }
      } catch (e) {
        debugPrint('Upload task error: $e');
        await NotificationService.instance.showUploadError(
          'Background enqueue failed: $e',
        );
        return Future.value(false);
      }
    }
    
    debugPrint('Unknown task: $task');
    return Future.value(true);
  });
}

/// Process all scheduled folders in background
Future<bool> processScheduledFolders() async {
  try {
    // Get scheduled folders first (this also loads settings)
    final settings = SettingsModel();
    await settings.loadSettings();
    
    // Use settings model values (consistent key names)
    final serverUrl = settings.backendUrl;
    final apiKey = settings.apiKey;
    
    if (serverUrl.isEmpty) {
      debugPrint('Server URL not configured, skipping folder scan');
      return true; // Not an error, just not configured
    }

    // Initialize backend client
    final backendClient = BackendClient(
      baseUrl: serverUrl,
      apiKey: apiKey,
    );

    final folders = await settings.getScheduledFolders();
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Filter due folders
    final dueFolders = folders.where((f) => f.isDue(currentTimestamp)).toList();
    
    if (dueFolders.isEmpty) {
      debugPrint('No folders due for processing');
      return true;
    }

    debugPrint('Processing ${dueFolders.length} due folders in background');
    
    // Initialize folder scanner
    final scanner = FolderScanner(
      backendClient: backendClient,
      settings: settings,
    );

    // Process each due folder
    for (final folder in dueFolders) {
      try {
        final result = await scanner.processFolder(folder);
        debugPrint(
          'Folder ${folder.name}: found ${result.filesFound}, '
          'uploaded ${result.filesUploaded}'
        );
      } catch (e) {
        debugPrint('Error processing folder ${folder.name}: $e');
        // Continue with other folders
      }
    }

    return true;
  } catch (e) {
    debugPrint('Error in background folder scan: $e');
    return false;
  }
}

/// Initialize background task scheduler
Future<void> initializeBackgroundTasks() async {
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: kDebugMode,
  );
}

/// Schedule periodic folder scan task
/// 
/// [frequency] - How often to run the scan (minimum 15 minutes on Android)
/// [constraints] - Optional constraints for when the task can run
Future<void> scheduleFolderScanTask({
  Duration frequency = const Duration(minutes: 15),
  bool requireCharging = false,
  bool requireNetwork = true,
  bool requireBatteryNotLow = true,
}) async {
  await Workmanager().registerPeriodicTask(
    kFolderScanTask,
    kFolderScanTask,
    frequency: frequency,
    constraints: Constraints(
      networkType: requireNetwork ? NetworkType.connected : NetworkType.not_required,
      requiresCharging: requireCharging,
      requiresBatteryNotLow: requireBatteryNotLow,
    ),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
  
  debugPrint('Scheduled periodic folder scan task with frequency: $frequency');
}

/// Cancel the periodic folder scan task
Future<void> cancelFolderScanTask() async {
  await Workmanager().cancelByUniqueName(kFolderScanTask);
  debugPrint('Cancelled folder scan task');
}

/// Manually trigger a folder scan (for testing or manual refresh)
Future<List<ScanResult>> triggerManualScan() async {
  try {
    // Get scheduled folders first (this also loads settings)
    final settings = SettingsModel();
    await settings.loadSettings();
    
    // Use settings model values (consistent key names)
    final serverUrl = settings.backendUrl;
    final apiKey = settings.apiKey;
    
    if (serverUrl.isEmpty) {
      debugPrint('Server URL not configured');
      return [];
    }

    // Initialize backend client
    final backendClient = BackendClient(
      baseUrl: serverUrl,
      apiKey: apiKey,
    );

    final folders = await settings.getScheduledFolders();
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Filter due folders
    final dueFolders = folders.where((f) => f.isDue(currentTimestamp)).toList();
    
    if (dueFolders.isEmpty) {
      debugPrint('No folders due for processing');
      return [];
    }

    debugPrint('Manually processing ${dueFolders.length} due folders');
    
    // Initialize folder scanner
    final scanner = FolderScanner(
      backendClient: backendClient,
      settings: settings,
    );

    // Process each due folder
    final results = <ScanResult>[];
    for (final folder in dueFolders) {
      try {
        final result = await scanner.processFolder(folder);
        results.add(result);
        debugPrint(
          'Folder ${folder.name}: found ${result.filesFound}, '
          'uploaded ${result.filesUploaded}'
        );
      } catch (e) {
        debugPrint('Error processing folder ${folder.name}: $e');
        // Continue with other folders
      }
    }

    return results;
  } catch (e) {
    debugPrint('Error in manual folder scan: $e');
    return [];
  }
}
