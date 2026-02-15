import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:saf/saf.dart';
import 'package:path/path.dart' as path;
import '../models/scheduled_folder.dart';
import 'backend_client.dart';
import 'saf_file_reader.dart';
import 'settings_model.dart';

/// Supported media file extensions
const Set<String> kSupportedExtensions = {
  // Images
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.svg',
  // Videos
  '.mp4', '.webm', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.m4v',
};

/// Service for scanning folders and uploading media files
class FolderScanner {
  final BackendClient _backendClient;
  final SettingsModel _settings;
  final SafFileReader _safFileReader;

  FolderScanner({
    required BackendClient backendClient,
    required SettingsModel settings,
    SafFileReader? safFileReader,
  })  : _backendClient = backendClient,
        _settings = settings,
        _safFileReader = safFileReader ?? SafFileReader();

  /// Check if a file is a supported media file
  bool isMediaFile(String fileName) {
    final ext = path.extension(fileName).toLowerCase();
    return kSupportedExtensions.contains(ext);
  }

  /// Scan a folder and return list of media file URIs
  Future<List<String>> scanFolder(ScheduledFolder folder) async {
    try {
      final saf = Saf(folder.uri);
      
      // Get all file URIs from the directory
      // Note: SAF returns content:// URIs, not file paths
      final fileUris = await saf.getFilesPath();
      
      if (fileUris == null) {
        debugPrint('Failed to get directory content for ${folder.name}');
        return [];
      }

      // Filter for supported media files
      final mediaFiles = fileUris
          .where((fileUri) => isMediaFile(fileUri))
          .toList();

      debugPrint('Found ${mediaFiles.length} media files in ${folder.name}');
      return mediaFiles;
    } catch (e) {
      debugPrint('Error scanning folder ${folder.name}: $e');
      return [];
    }
  }

  /// Upload a single file from a scheduled folder using SAF URI
  /// 
  /// [contentUri] - The SAF content:// URI of the file to upload
  /// [folder] - The scheduled folder configuration
  Future<String?> uploadFile(
    String contentUri,
    ScheduledFolder folder,
  ) async {
    File? tempFile;
    try {
      // Extract filename from URI for logging and temp file naming
      final fileName = _extractFileName(contentUri);
      debugPrint('Uploading file: $fileName from URI: $contentUri');

      // Copy file from SAF URI to temp location
      tempFile = await _safFileReader.copyToTempFile(contentUri, fileName);
      
      // Verify temp file exists
      if (!await tempFile.exists()) {
        debugPrint('Temp file does not exist: ${tempFile.path}');
        return null;
      }

      // Upload the temp file using existing backend client
      final jobId = await _backendClient.enqueueFromFile(
        file: tempFile,
        source: 'folder:${folder.name}',
        tags: folder.defaultTags,
        safety: folder.defaultSafety,
        skipTagging: folder.skipTagging,
      );

      if (jobId != null) {
        debugPrint('Uploaded $fileName as job $jobId');
      }
      return jobId;
    } on SafFileReaderException catch (e) {
      debugPrint('SAF error uploading file $contentUri: $e');
      return null;
    } catch (e) {
      debugPrint('Error uploading file $contentUri: $e');
      return null;
    } finally {
      // Clean up temp file
      if (tempFile != null) {
        await _safFileReader.deleteTempFile(tempFile);
      }
    }
  }

  /// Extract filename from a SAF content:// URI
  /// 
  /// SAF URIs typically encode the filename in the last segment
  String _extractFileName(String contentUri) {
    try {
      // Try to get the last segment after the last slash or encoded segment
      final uri = Uri.parse(contentUri);
      
      // For content:// URIs, the last path segment often contains encoded filename
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final lastSegment = pathSegments.last;
        // Decode if it's URL encoded
        final decoded = Uri.decodeComponent(lastSegment);
        // Some SAF URIs have format like "primary:DCIM/photo.jpg"
        if (decoded.contains(':')) {
          final parts = decoded.split(':');
          if (parts.length > 1) {
            // Return the part after the colon, which is usually the path/filename
            final pathPart = parts.last;
            // Get just the filename if it contains path separators
            return pathPart.split('/').last;
          }
        }
        return decoded;
      }
      
      // Fallback: use timestamp-based name
      return 'file_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('Error extracting filename from URI: $e');
      return 'file_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Process a scheduled folder - scan and upload all media files
  Future<ScanResult> processFolder(ScheduledFolder folder) async {
    final startTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Clean up old temp files before processing
    await _safFileReader.cleanupTempFiles();
    
    // Scan folder for media files
    final mediaFiles = await scanFolder(folder);
    
    if (mediaFiles.isEmpty) {
      return ScanResult(
        folderId: folder.id,
        filesFound: 0,
        filesUploaded: 0,
        jobIds: [],
        timestamp: startTime,
      );
    }

    // Upload each file
    final jobIds = <String>[];
    int uploaded = 0;
    
    for (final contentUri in mediaFiles) {
      final jobId = await uploadFile(contentUri, folder);
      if (jobId != null) {
        jobIds.add(jobId);
        uploaded++;
      }
    }

    // Update last run timestamp
    await _settings.updateFolderLastRun(folder.id, startTime);

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
      debugPrint('No folders due for processing');
      return [];
    }

    debugPrint('Processing ${dueFolders.length} due folders');
    
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
