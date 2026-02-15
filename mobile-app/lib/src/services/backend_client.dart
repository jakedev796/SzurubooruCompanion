import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../models/job.dart';

/// SSE event types received from the backend
enum SseEventType {
  connected,
  jobUpdate,
  error,
  unknown,
}

/// Represents an SSE event from the backend
class SseEvent {
  final SseEventType type;
  final Map<String, dynamic>? data;

  SseEvent({required this.type, this.data});

  factory SseEvent.parse(String raw) {
    // Parse SSE format: "event: event_type\ndata: {...}\n\n"
    String? eventType;
    String? dataStr;

    for (final line in raw.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataStr = line.substring(5).trim();
      }
    }

    SseEventType type;
    switch (eventType) {
      case 'connected':
        type = SseEventType.connected;
        break;
      case 'job_update':
        type = SseEventType.jobUpdate;
        break;
      case 'error':
        type = SseEventType.error;
        break;
      default:
        type = SseEventType.unknown;
    }

    Map<String, dynamic>? data;
    if (dataStr != null && dataStr.isNotEmpty) {
      try {
        data = json.decode(dataStr) as Map<String, dynamic>;
      } catch (_) {
        data = {'raw': dataStr};
      }
    }

    return SseEvent(type: type, data: data);
  }
}

/// Job update data from SSE events
class JobUpdate {
  final String jobId;
  final String status;
  final int? progress;
  final String? error;
  final int? szuruPostId;
  final List<String>? tags;
  final DateTime timestamp;

  JobUpdate({
    required this.jobId,
    required this.status,
    this.progress,
    this.error,
    this.szuruPostId,
    this.tags,
    required this.timestamp,
  });

  factory JobUpdate.fromSseData(Map<String, dynamic> data) {
    return JobUpdate(
      jobId: data['job_id']?.toString() ?? '',
      status: data['status'] as String,
      progress: data['progress'] as int?,
      error: data['error'] as String?,
      szuruPostId: data['szuru_post_id'] as int?,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>(),
      timestamp: DateTime.parse(data['timestamp'] as String),
    );
  }
}

/// Connection state for SSE
enum SseConnectionState {
  disconnected,
  connecting,
  connected,
}

/// Backend client for communicating with the CCC API.
/// 
/// Handles:
/// - Job creation and retrieval
/// - Statistics fetching
/// - SSE streaming for real-time updates
/// - Optional API key authentication via X-API-Key header
class BackendClient {
  final Dio _dio;
  final String baseUrl;
  String _apiKey;
  
  // SSE connection state
  SseConnectionState _sseState = SseConnectionState.disconnected;
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSubscription;
  final _sseStateController = StreamController<SseConnectionState>.broadcast();
  final _jobUpdateController = StreamController<JobUpdate>.broadcast();

  BackendClient({
    required this.baseUrl,
    String apiKey = '',
  }) : _apiKey = apiKey,
       _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 10),
           headers: {
             'Content-Type': 'application/json',
             if (apiKey.isNotEmpty) 'X-API-Key': apiKey,
           },
         ),
       );

  /// Stream of SSE connection state changes
  Stream<SseConnectionState> get sseStateStream => _sseStateController.stream;
  
  /// Stream of job updates from SSE
  Stream<JobUpdate> get jobUpdateStream => _jobUpdateController.stream;
  
  /// Current SSE connection state
  SseConnectionState get sseState => _sseState;

  /// Update the API key for authentication.
  /// If apiKey is empty, the X-API-Key header will be removed.
  void updateApiKey(String apiKey) {
    _apiKey = apiKey;
    if (apiKey.isNotEmpty) {
      _dio.options.headers['X-API-Key'] = apiKey;
    } else {
      _dio.options.headers.remove('X-API-Key');
    }
  }

  /// Update the base URL for the backend
  void updateBaseUrl(String newBaseUrl) {
    _dio.options.baseUrl = newBaseUrl;
  }

  /// Connect to the SSE endpoint and start receiving real-time updates.
  /// 
  /// Returns a stream of SSE events. The connection will automatically
  /// reconnect on disconnect if [autoReconnect] is true.
  Stream<SseEvent> connectSse({bool autoReconnect = true}) {
    final controller = StreamController<SseEvent>();
    
    void connect() {
      _sseState = SseConnectionState.connecting;
      _sseStateController.add(_sseState);
      
      _sseClient = http.Client();
      final request = http.Request('GET', Uri.parse('$baseUrl/api/events'));
      
      // Add API key header if available
      if (_apiKey.isNotEmpty) {
        request.headers['X-API-Key'] = _apiKey;
      }
      
      _sseClient!.send(request).then((response) {
        if (response.statusCode != 200) {
          controller.addError(BackendException(
            'SSE connection failed: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          ));
          _sseState = SseConnectionState.disconnected;
          _sseStateController.add(_sseState);
          return;
        }
        
        _sseState = SseConnectionState.connected;
        _sseStateController.add(_sseState);
        
        // Buffer for incomplete SSE events
        final buffer = StringBuffer();
        
        response.stream.transform(utf8.decoder).listen(
          (chunk) {
            buffer.write(chunk);
            
            // Process complete events (ending with \n\n)
            String content = buffer.toString();
            while (content.contains('\n\n')) {
              final index = content.indexOf('\n\n');
              final eventStr = content.substring(0, index);
              content = content.substring(index + 2);
              
              // Skip comments (heartbeats)
              if (eventStr.startsWith(':')) {
                continue;
              }
              
              final event = SseEvent.parse(eventStr);
              controller.add(event);
              
              // Also emit job updates to the dedicated stream
              if (event.type == SseEventType.jobUpdate && event.data != null) {
                try {
                  final jobUpdate = JobUpdate.fromSseData(event.data!);
                  _jobUpdateController.add(jobUpdate);
                } catch (_) {
                  // Ignore parse errors for job updates
                }
              }
            }
            
            // Keep incomplete data in buffer
            buffer.clear();
            buffer.write(content);
          },
          onError: (error) {
            controller.addError(BackendException('SSE stream error: $error'));
            _sseState = SseConnectionState.disconnected;
            _sseStateController.add(_sseState);
            
            if (autoReconnect && !controller.isClosed) {
              Future.delayed(const Duration(seconds: 3), connect);
            }
          },
          onDone: () {
            _sseState = SseConnectionState.disconnected;
            _sseStateController.add(_sseState);
            
            if (autoReconnect && !controller.isClosed) {
              Future.delayed(const Duration(seconds: 3), connect);
            }
          },
        );
      }).catchError((error) {
        controller.addError(BackendException('SSE connection error: $error'));
        _sseState = SseConnectionState.disconnected;
        _sseStateController.add(_sseState);
        
        if (autoReconnect && !controller.isClosed) {
          Future.delayed(const Duration(seconds: 3), connect);
        }
      });
    }
    
    connect();
    
    controller.onCancel = () {
      disconnectSse();
    };
    
    return controller.stream;
  }

  /// Disconnect from the SSE endpoint
  void disconnectSse() {
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _sseClient?.close();
    _sseClient = null;
    _sseState = SseConnectionState.disconnected;
    _sseStateController.add(_sseState);
  }

  /// Dispose of resources
  void dispose() {
    disconnectSse();
    _sseStateController.close();
    _jobUpdateController.close();
  }

  /// Fetch jobs from the backend with optional filtering.
  /// 
  /// Backend endpoint: GET /api/jobs
  /// Query params: status, limit, offset
  /// Response: { results: [...], total, offset, limit }
  Future<List<Job>> fetchJobs({
    String? status,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
      };
      
      if (status != null && status != 'all') {
        queryParams['status'] = status;
      }

      final response = await _dio.get(
        '/api/jobs',
        queryParameters: queryParams,
      );

      if (response.data is! Map<String, dynamic>) {
        return [];
      }

      final payload = response.data as Map<String, dynamic>;
      final results = payload['results'] as List<dynamic>?;

      if (results == null) {
        return [];
      }

      return results
          .cast<Map<String, dynamic>>()
          .map(Job.fromJson)
          .toList();
    } on DioException catch (e) {
      throw BackendException(
        'Failed to fetch jobs: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Fetch a single job by ID.
  /// 
  /// Backend endpoint: GET /api/jobs/{job_id}
  Future<Job?> fetchJob(String jobId) async {
    try {
      final response = await _dio.get('/api/jobs/$jobId');

      if (response.data is! Map<String, dynamic>) {
        return null;
      }

      return Job.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw BackendException(
        'Failed to fetch job: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Fetch job statistics from the backend.
  /// 
  /// Backend endpoint: GET /api/stats
  /// Response: { total_jobs, by_status: { pending, downloading, tagging, uploading, completed, failed }, daily_uploads }
  Future<Map<String, int>> fetchStats() async {
    try {
      final response = await _dio.get('/api/stats');

      if (response.data is! Map<String, dynamic>) {
        return const {'pending': 0, 'downloading': 0, 'tagging': 0, 'uploading': 0, 'completed': 0, 'failed': 0};
      }

      final data = response.data as Map<String, dynamic>;
      final byStatus = data['by_status'] as Map<String, dynamic>?;

      if (byStatus == null) {
        return const {'pending': 0, 'downloading': 0, 'tagging': 0, 'uploading': 0, 'completed': 0, 'failed': 0};
      }

      return {
        'pending': (byStatus['pending'] as int?) ?? 0,
        'downloading': (byStatus['downloading'] as int?) ?? 0,
        'tagging': (byStatus['tagging'] as int?) ?? 0,
        'uploading': (byStatus['uploading'] as int?) ?? 0,
        'completed': (byStatus['completed'] as int?) ?? 0,
        'failed': (byStatus['failed'] as int?) ?? 0,
      };
    } on DioException catch (e) {
      throw BackendException(
        'Failed to fetch stats: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Create a new job from a URL.
  /// 
  /// Backend endpoint: POST /api/jobs
  /// Request body: { url, source?, tags?, safety?, skip_tagging? }
  /// Response: { id, status, job_type, url, ... }
  Future<Job> enqueueFromUrl({
    required String url,
    String? source,
    List<String>? tags,
    String? safety,
    bool? skipTagging,
  }) async {
    try {
      final payload = <String, dynamic>{
        'url': url,
      };

      if (source != null && source.isNotEmpty) {
        payload['source'] = source;
      }

      if (tags != null && tags.isNotEmpty) {
        payload['tags'] = tags;
      }

      if (safety != null && safety.isNotEmpty) {
        payload['safety'] = safety;
      }

      if (skipTagging != null) {
        payload['skip_tagging'] = skipTagging;
      }

      final response = await _dio.post('/api/jobs', data: payload);

      if (response.data is! Map<String, dynamic>) {
        throw const BackendException('Invalid response from server');
      }

      return Job.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw BackendException(
        'Failed to enqueue job: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Upload a file to the backend for processing.
  /// 
  /// Backend endpoint: POST /api/jobs/upload
  /// Uses multipart form data to upload the file.
  /// Returns the created job ID on success, null on failure.
  Future<String?> enqueueFromFile({
    required File file,
    String? source,
    List<String>? tags,
    String? safety,
    bool? skipTagging,
  }) async {
    final uri = Uri.parse('$baseUrl/api/jobs/upload');
    final request = http.MultipartRequest('POST', uri);

    // Add API key header if available
    if (_apiKey.isNotEmpty) {
      request.headers['X-API-Key'] = _apiKey;
    }

    // Add file
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    // Add optional fields
    if (source != null && source.isNotEmpty) {
      request.fields['source'] = source;
    }
    if (tags != null && tags.isNotEmpty) {
      request.fields['tags'] = tags.join(',');
    }
    if (safety != null && safety.isNotEmpty) {
      request.fields['safety'] = safety;
    }
    if (skipTagging != null) {
      request.fields['skip_tagging'] = skipTagging.toString();
    }

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['id']?.toString();
      } else {
        print('Failed to upload file: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  /// Start a pending job.
  /// 
  /// Backend endpoint: POST /api/jobs/{job_id}/start
  Future<Job> startJob(String jobId) async {
    try {
      final response = await _dio.post('/api/jobs/$jobId/start');

      if (response.data is! Map<String, dynamic>) {
        throw const BackendException('Invalid response from server');
      }

      return Job.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw BackendException(
        'Failed to start job: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Pause a running job.
  /// 
  /// Backend endpoint: POST /api/jobs/{job_id}/pause
  Future<Job> pauseJob(String jobId) async {
    try {
      final response = await _dio.post('/api/jobs/$jobId/pause');

      if (response.data is! Map<String, dynamic>) {
        throw const BackendException('Invalid response from server');
      }

      return Job.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw BackendException(
        'Failed to pause job: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Stop a job.
  /// 
  /// Backend endpoint: POST /api/jobs/{job_id}/stop
  Future<Job> stopJob(String jobId) async {
    try {
      final response = await _dio.post('/api/jobs/$jobId/stop');

      if (response.data is! Map<String, dynamic>) {
        throw const BackendException('Invalid response from server');
      }

      return Job.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw BackendException(
        'Failed to stop job: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Resume a paused or stopped job.
  /// 
  /// Backend endpoint: POST /api/jobs/{job_id}/resume
  Future<Job> resumeJob(String jobId) async {
    try {
      final response = await _dio.post('/api/jobs/$jobId/resume');

      if (response.data is! Map<String, dynamic>) {
        throw const BackendException('Invalid response from server');
      }

      return Job.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw BackendException(
        'Failed to resume job: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Delete a job.
  /// 
  /// Backend endpoint: DELETE /api/jobs/{job_id}
  Future<bool> deleteJob(String jobId) async {
    try {
      final response = await _dio.delete('/api/jobs/$jobId');
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      throw BackendException(
        'Failed to delete job: ${e.message}',
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Check if the backend is reachable and API key is valid.
  /// 
  /// Uses the stats endpoint as a health check.
  Future<bool> checkConnection() async {
    try {
      await _dio.get('/api/stats');
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Exception thrown by BackendClient for API errors.
class BackendException implements Exception {
  final String message;
  final int? statusCode;

  const BackendException(this.message, {this.statusCode});

  @override
  String toString() => 'BackendException: $message${statusCode != null ? ' (status: $statusCode)' : ''}';
}
