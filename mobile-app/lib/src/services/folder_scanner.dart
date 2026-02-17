import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/scheduled_folder.dart';
import 'backend_client.dart';
import 'notification_service.dart';
import 'settings_model.dart';

/// Supported media file extensions
const Set<String> kSupportedExtensions = {
  // Images
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.svg',
  // Videos
  '.mp4', '.webm', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.m4v',
};

/// Service for scanning folders and uploading media files using direct File I/O
/// Requires MANAGE_EXTERNAL_STORAGE permission
class FolderScanner {
  final BackendClient _backendClient;
  final SettingsModel _settings;

  FolderScanner({
    required BackendClient backendClient,
    required SettingsModel settings,
  })  : _backendClient = backendClient,
        _settings = settings;

  /// Check if a file is a supported media file
  bool isMediaFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return kSupportedExtensions.contains(ext);
  }

  /// Convert relative folder URI to absolute path
  String _toAbsolutePath(String uri) {
    if (uri.startsWith('/')) {
      return uri;
    }
    // Relative path like "Pictures/Twitter" → "/storage/emulated/0/Pictures/Twitter"
    return '/storage/emulated/0/$uri';
  }

  /// Scan a folder and return list of media file paths using direct File I/O.
  /// With MANAGE_EXTERNAL_STORAGE permission, we can access files directly.
  Future<List<String>> scanFolder(ScheduledFolder folder) async {
    debugPrint('[FolderScanner] scanFolder() started for ${folder.name}');
    try {
      final folderPath = _toAbsolutePath(folder.uri);
      debugPrint('[FolderScanner] Scanning directory: $folderPath');

      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        debugPrint('[FolderScanner] ERROR: Directory does not exist: $folderPath');
        return [];
      }

      // Recursively scan for media files
      final mediaFiles = <String>[];
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File && isMediaFile(entity.path)) {
          mediaFiles.add(entity.path);
        }
      }

      debugPrint('[FolderScanner] Found ${mediaFiles.length} media files in ${folder.name}');
      return mediaFiles;
    } catch (e, stackTrace) {
      debugPrint('[FolderScanner] Error scanning folder ${folder.name}: $e');
      debugPrint('[FolderScanner] Stack trace: $stackTrace');
      return [];
    }
  }

  /// Upload a single file from a scheduled folder using direct File I/O.
  /// [deleteAfterUpload] - If true and upload succeeds, delete the source file.
  /// [enqueueDeleteForLater] - If true and upload succeeds, queue file path for deletion when app opens.
  Future<String?> uploadFile(
    String filePath,
    ScheduledFolder folder, {
    bool deleteAfterUpload = false,
    bool enqueueDeleteForLater = false,
  }) async {
    try {
      final file = File(filePath);
      final fileName = path.basename(filePath);
      debugPrint('[FolderScanner] uploadFile() - fileName: $fileName, filePath: $filePath');

      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      debugPrint('[FolderScanner] File exists: $exists, size: $size bytes');

      if (!exists) {
        debugPrint('[FolderScanner] ERROR: File does not exist: $filePath');
        return null;
      }

      debugPrint('[FolderScanner] Calling backendClient.enqueueFromFile...');
      final result = await _backendClient.enqueueFromFile(
        file: file,
        source: 'folder:${folder.name}',
        tags: folder.defaultTags,
        safety: folder.defaultSafety,
        skipTagging: folder.skipTagging,
        szuruUser: _settings.szuruUser.isNotEmpty ? _settings.szuruUser : null,
      );
      debugPrint('[FolderScanner] backendClient returned jobId: ${result.jobId}, error: ${result.error}');

      if (result.error != null) {
        debugPrint('[FolderScanner] Upload failed: ${result.error}');
        await NotificationService.instance.showUploadError(
          '$fileName: ${result.error}',
        );
        return null;
      }

      final jobId = result.jobId;
      if (jobId != null) {
        debugPrint('[FolderScanner] Upload successful: jobId=$jobId');

        // Handle file deletion after successful upload
        if (deleteAfterUpload) {
          try {
            await file.delete();
            debugPrint('[FolderScanner] Deleted source file after upload: $filePath');
          } catch (e) {
            debugPrint('[FolderScanner] Failed to delete file: $e');
          }
        } else if (enqueueDeleteForLater) {
          try {
            await file.delete();
            debugPrint('[FolderScanner] Deleted source file after upload (background): $filePath');
          } catch (e) {
            debugPrint('[FolderScanner] Failed to delete file, queuing for later: $e');
            await _settings.addPendingDeleteUri(filePath);
            debugPrint('[FolderScanner] Queued file for deletion when app opens: $filePath');
          }
        }
      } else {
        debugPrint('[FolderScanner] Upload returned null jobId');
      }

      return jobId;
    } catch (e, stackTrace) {
      debugPrint('[FolderScanner] Error uploading file $filePath: $e');
      debugPrint('[FolderScanner] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Delete a file by path (used for cleanup after upload)
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[FolderScanner] Deleted file: $filePath');
        return true;
      }
      debugPrint('[FolderScanner] File does not exist, cannot delete: $filePath');
      return false;
    } catch (e) {
      debugPrint('[FolderScanner] Error deleting file $filePath: $e');
      return false;
    }
  }

  /// Process a scheduled folder - scan and upload all media files.
  /// [allowDelete] - If true and settings say so, delete source files after upload.
  Future<ScanResult> processFolder(ScheduledFolder folder, {bool allowDelete = false}) async {
    debugPrint('[FolderScanner] processFolder() started for: ${folder.name}');
    final startTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final deleteAfterUpload = _settings.deleteMediaAfterSync && allowDelete;
    final enqueueDeleteForLater = _settings.deleteMediaAfterSync && !allowDelete;

    debugPrint('[FolderScanner] Settings: deleteAfterUpload=$deleteAfterUpload, enqueueDeleteForLater=$enqueueDeleteForLater');

    debugPrint('[FolderScanner] Scanning folder: ${folder.name} at URI: ${folder.uri}');
    final mediaFiles = await scanFolder(folder);
    debugPrint('[FolderScanner] Scan complete: found ${mediaFiles.length} media files');

    if (mediaFiles.isEmpty) {
      debugPrint('[FolderScanner] No media files found in ${folder.name}');
      return ScanResult(
        folderId: folder.id,
        filesFound: 0,
        filesUploaded: 0,
        jobIds: [],
        timestamp: startTime,
      );
    }

    final jobIds = <String>[];
    int uploaded = 0;

    debugPrint('[FolderScanner] Starting upload of ${mediaFiles.length} files from ${folder.name}');
    for (int i = 0; i < mediaFiles.length; i++) {
      final filePath = mediaFiles[i];
      debugPrint('[FolderScanner] Uploading file ${i + 1}/${mediaFiles.length}: $filePath');

      try {
        final jobId = await uploadFile(
          filePath,
          folder,
          deleteAfterUpload: deleteAfterUpload,
          enqueueDeleteForLater: enqueueDeleteForLater,
        );
        if (jobId != null) {
          jobIds.add(jobId);
          uploaded++;
          debugPrint('[FolderScanner] Upload successful: jobId=$jobId');
        } else {
          debugPrint('[FolderScanner] Upload returned null jobId');
        }
      } catch (e, stackTrace) {
        debugPrint('[FolderScanner] Error uploading file: $e');
        debugPrint('[FolderScanner] Stack trace: $stackTrace');
      }
    }

    debugPrint('[FolderScanner] Upload complete: ${uploaded}/${mediaFiles.length} files uploaded');

    // Update last run timestamp
    debugPrint('[FolderScanner] Updating last run timestamp to $startTime');
    await _settings.updateFolderLastRun(folder.id, startTime);

    debugPrint('[FolderScanner] processFolder() complete for ${folder.name}');
    return ScanResult(
      folderId: folder.id,
      filesFound: mediaFiles.length,
      filesUploaded: uploaded,
      jobIds: jobIds,
      timestamp: startTime,
    );
  }

  /// Process all due folders
  Future<List<ScanResult>> processDueFolders() async {
    final folders = await _settings.getScheduledFolders();
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final dueFolders = folders.where((f) => f.isDue(currentTimestamp)).toList();

    if (dueFolders.isEmpty) {
      debugPrint('[FolderScanner] No folders due for processing');
      return [];
    }

    debugPrint('[FolderScanner] Processing ${dueFolders.length} due folders');

    final results = <ScanResult>[];
    for (final folder in dueFolders) {
      final result = await processFolder(folder);
      results.add(result);
    }

    return results;
  }
}

/// Result of a folder scan operation
class ScanResult {
  final String folderId;
  final int filesFound;
  final int filesUploaded;
  final List<String> jobIds;
  final int timestamp;

  ScanResult({
    required this.folderId,
    required this.filesFound,
    required this.filesUploaded,
    required this.jobIds,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'folderId': folderId,
      'filesFound': filesFound,
      'filesUploaded': filesUploaded,
      'jobIds': jobIds,
      'timestamp': timestamp,
    };
  }

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      folderId: json['folderId'] as String,
      filesFound: json['filesFound'] as int,
      filesUploaded: json['filesUploaded'] as int,
      jobIds: (json['jobIds'] as List<dynamic>).map((e) => e as String).toList(),
      timestamp: json['timestamp'] as int,
    );
  }
}
