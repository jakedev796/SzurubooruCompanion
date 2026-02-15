import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';

/// Service for reading files from SAF (Storage Access Framework) content:// URIs.
/// 
/// On Android 11+ with scoped storage, files from SAF URIs cannot be accessed
/// directly with dart:io File. This service uses the saf_stream package to
/// read files from content:// URIs and copy them to temporary storage.
class SafFileReader {
  final SafStream _safStream = SafStream();

  /// Copies a file from a SAF content:// URI to a temporary file.
  /// 
  /// Returns the temporary File object that can be used with dart:io.
  /// The caller is responsible for deleting the temp file when done.
  /// 
  /// [contentUri] - The SAF content:// URI (e.g., content://com.android.externalstorage.documents/...)
  /// [fileName] - The name to use for the temporary file
  /// 
  /// Throws [SafFileReaderException] if the copy fails.
  Future<File> copyToTempFile(String contentUri, String fileName) async {
    try {
      debugPrint('SafFileReader: Copying $contentUri to temp file');
      
      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final tempPath = path.join(tempDir.path, 'saf_uploads');
      
      // Create subdirectory for SAF uploads
      final safTempDir = Directory(tempPath);
      if (!await safTempDir.exists()) {
        await safTempDir.create(recursive: true);
      }
      
      // Generate unique filename to avoid conflicts
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uniqueFileName = '${timestamp}_$fileName';
      final tempFilePath = path.join(tempPath, uniqueFileName);
      
      // Use saf_stream to copy the file to local storage
      await _safStream.copyToLocalFile(contentUri, tempFilePath);
      
      final tempFile = File(tempFilePath);
      
      // Verify the file was created
      if (!await tempFile.exists()) {
        throw SafFileReaderException(
          'Failed to copy file: temp file was not created',
          contentUri: contentUri,
        );
      }
      
      debugPrint('SafFileReader: Successfully copied to $tempFilePath');
      return tempFile;
    } on SafFileReaderException {
      rethrow;
    } catch (e) {
      debugPrint('SafFileReader: Error copying file: $e');
      throw SafFileReaderException(
        'Failed to copy file from SAF URI: $e',
        contentUri: contentUri,
      );
    }
  }

  /// Reads file bytes directly from a SAF content:// URI.
  /// 
  /// Returns the file contents as bytes.
  /// 
  /// [contentUri] - The SAF content:// URI
  /// 
  /// Throws [SafFileReaderException] if reading fails.
  Future<List<int>> readFileBytes(String contentUri) async {
    try {
      debugPrint('SafFileReader: Reading bytes from $contentUri');
      
      final bytes = await _safStream.readFileBytes(contentUri);
      
      debugPrint('SafFileReader: Read ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      debugPrint('SafFileReader: Error reading bytes: $e');
      throw SafFileReaderException(
        'Failed to read file bytes from SAF URI: $e',
        contentUri: contentUri,
      );
    }
  }

  /// Cleans up temporary files created by this service.
  /// 
  /// Call this periodically to remove old temp files.
  Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final safTempPath = path.join(tempDir.path, 'saf_uploads');
      final safTempDir = Directory(safTempPath);
      
      if (await safTempDir.exists()) {
        // Delete files older than 1 hour
        final now = DateTime.now();
        final files = await safTempDir.list().toList();
        
        for (final entity in files) {
          if (entity is File) {
            final stat = await entity.stat();
            final age = now.difference(stat.modified);
            
            if (age.inHours > 1) {
              await entity.delete();
              debugPrint('SafFileReader: Cleaned up old temp file: ${entity.path}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('SafFileReader: Error cleaning up temp files: $e');
    }
  }

  /// Deletes a temporary file.
  /// 
  /// Call this after uploading a file to free up space.
  Future<void> deleteTempFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        debugPrint('SafFileReader: Deleted temp file: ${file.path}');
      }
    } catch (e) {
      debugPrint('SafFileReader: Error deleting temp file: $e');
    }
  }
}

/// Exception thrown by SafFileReader operations.
class SafFileReaderException implements Exception {
  final String message;
  final String? contentUri;

  const SafFileReaderException(this.message, {this.contentUri});

  @override
  String toString() {
    if (contentUri != null) {
      return 'SafFileReaderException: $message (URI: $contentUri)';
    }
    return 'SafFileReaderException: $message';
  }
}
