import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/job.dart';
import '../models/auth.dart';

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
  final List<int>? relatedPostIds;
  final List<String>? tags;
  final DateTime timestamp;

  JobUpdate({
    required this.jobId,
    required this.status,
    this.progress,
    this.error,
    this.szuruPostId,
    this.relatedPostIds,
    this.tags,
    required this.timestamp,
  });

  factory JobUpdate.fromSseData(Map<String, dynamic> data) {
    List<int>? relatedIds;
    final raw = data['related_post_ids'];
    if (raw is List) {
      relatedIds = raw.whereType<int>().toList();
    }
    return JobUpdate(
      jobId: data['job_id']?.toString() ?? data['id']?.toString() ?? '',
      status: data['status'] as String,
      progress: data['progress'] as int?,
      error: data['error'] as String?,
      szuruPostId: data['szuru_post_id'] as int?,
      relatedPostIds: (relatedIds == null || relatedIds.isEmpty) ? null : relatedIds,
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
/// - JWT Bearer token authentication
class BackendClient {
  final Dio _dio;
  final String baseUrl;
  String? _accessToken;

  // SSE connection state
  SseConnectionState _sseState = SseConnectionState.disconnected;
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSubscription;
  final _sseStateController = StreamController<SseConnectionState>.broadcast();
  final _jobUpdateController = StreamController<JobUpdate>.broadcast();

  BackendClient({
    required this.baseUrl,
  })  : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'Content-Type': 'application/json',
            },
          ),
        ) {
    // Apply stored JWT before requests so clients that never called setAccessToken still work
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final path = options.path;
        if (path.contains('/api/auth/login') || path.contains('/api/auth/refresh')) {
          return handler.next(options);
        }
        if (options.headers.containsKey('Authorization')) {
          return handler.next(options);
        }
        final prefs = await SharedPreferences.getInstance();
        final authJson = prefs.getString('auth_tokens');
        if (authJson != null) {
          try {
            final tokens = AuthTokens.fromJson(jsonDecode(authJson) as Map<String, dynamic>);
            _accessToken = tokens.accessToken;
            options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
          } catch (_) {}
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final prefs = await SharedPreferences.getInstance();
          final authJson = prefs.getString('auth_tokens');
          if (authJson != null) {
            try {
              final tokens = AuthTokens.fromJson(jsonDecode(authJson));
              final newAccessToken = await refreshAccessToken(tokens.refreshToken);

              if (newAccessToken != null) {
                setAccessToken(newAccessToken);
                await prefs.setString('auth_tokens', jsonEncode(AuthTokens(
                  accessToken: newAccessToken,
                  refreshToken: tokens.refreshToken,
                ).toJson()));

                // Retry request
                final options = error.requestOptions;
                options.headers['Authorization'] = 'Bearer $newAccessToken';
                final response = await _dio.fetch(options);
                return handler.resolve(response);
              }
            } catch (_) {
              // If refresh fails, clear auth and reject error
            }

            await prefs.remove('auth_tokens');
            setAccessToken(null);
          }
        }
        return handler.reject(error);
      },
    ));
  }

  /// Stream of SSE connection state changes
  Stream<SseConnectionState> get sseStateStream => _sseStateController.stream;
  
  /// Stream of job updates from SSE
  Stream<JobUpdate> get jobUpdateStream => _jobUpdateController.stream;
  
  /// Current SSE connection state
  SseConnectionState get sseState => _sseState;

  /// Update the base URL for the backend
  void updateBaseUrl(String newBaseUrl) {
    _dio.options.baseUrl = newBaseUrl;
  }

  /// Login with username/password and return JWT tokens
  Future<LoginResponse> login(String username, String password) async {
    final response = await _dio.post('/api/auth/login',
      data: {'username': username, 'password': password},
      options: Options(headers: {}),  // Don't send API key or Bearer for login
    );
    return LoginResponse.fromJson(response.data);
  }

  /// Refresh access token using stored refresh token
  Future<String?> refreshAccessToken(String refreshToken) async {
    try {
      final response = await _dio.post('/api/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {}),  // Don't send existing auth headers
      );
      return response.data['access_token'];
    } catch (e) {
      return null;
    }
  }

  /// Set access token for JWT authentication
  void setAccessToken(String? token) {
    _accessToken = token;
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  /// Fetch client preferences from backend
  Future<Map<String, dynamic>> fetchPreferences() async {
    final response = await _dio.get('/api/preferences/mobile-android');
    return response.data['preferences'];
  }

  /// Save client preferences to backend
  Future<void> savePreferences(Map<String, dynamic> prefs) async {
    await _dio.put('/api/preferences/mobile-android',
      data: {'preferences': prefs}
    );
  }

  /// Connect to the SSE endpoint and start receiving real-time updates.
  /// 
  /// Returns a stream of SSE events. The connection will automatically
  /// reconnect on disconnect if [autoReconnect] is true.
  Stream<SseEvent> connectSse({bool autoReconnect = true}) {
    final controller = StreamController<SseEvent>();
    
    void connect() {
      if (_sseStateController.isClosed) return;
      _sseState = SseConnectionState.connecting;
      if (!_sseStateController.isClosed) _sseStateController.add(_sseState);
      
      _sseClient = http.Client();
      final request = http.Request('GET', Uri.parse('$baseUrl/api/events'));
      if (_accessToken != null && _accessToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }
      
      _sseClient!.send(request).then((response) {
        if (response.statusCode != 200) {
          if (!controller.isClosed) controller.addError(BackendException(
            'SSE connection failed: HTTP ${response.statusCode}',
            statusCode: response.statusCode,
          ));
          _sseState = SseConnectionState.disconnected;
          if (!_sseStateController.isClosed) _sseStateController.add(_sseState);
          return;
        }
        
        _sseState = SseConnectionState.connected;
        if (!_sseStateController.isClosed) _sseStateController.add(_sseState);
        
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
              if (!controller.isClosed) controller.add(event);
              
              if (event.type == SseEventType.jobUpdate && event.data != null && !_jobUpdateController.isClosed) {
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
            if (!controller.isClosed) controller.addError(const BackendException('Connection error'));
            _sseState = SseConnectionState.disconnected;
            if (!_sseStateController.isClosed) _sseStateController.add(_sseState);
            if (autoReconnect && !_sseStateController.isClosed) {
              Future.delayed(const Duration(seconds: 3), connect);
            }
          },
          onDone: () {
            _sseState = SseConnectionState.disconnected;
            if (!_sseStateController.isClosed) _sseStateController.add(_sseState);
            if (autoReconnect && !_sseStateController.isClosed) {
              Future.delayed(const Duration(seconds: 3), connect);
            }
          },
        );
      }).catchError((error) {
        if (!controller.isClosed) controller.addError(const BackendException('Connection error'));
        _sseState = SseConnectionState.disconnected;
        if (!_sseStateController.isClosed) _sseStateController.add(_sseState);
        if (autoReconnect && !_sseStateController.isClosed) {
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
    if (!_sseStateController.isClosed) _sseStateController.add(_sseState);
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
        _friendlyLabelForStatusCode(e.response?.statusCode),
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
        _friendlyLabelForStatusCode(e.response?.statusCode),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Fetch job statistics from the backend.
  /// 
  /// Backend endpoint: GET /api/config
  /// Response: { auth_required?, booru_url? }
  Future<Map<String, dynamic>> fetchConfig() async {
    try {
      final response = await _dio.get('/api/config');
      if (response.data is! Map<String, dynamic>) {
        return {};
      }
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw BackendException(
        _friendlyLabelForStatusCode(e.response?.statusCode),
        statusCode: e.response?.statusCode,
      );
    }
  }

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
        _friendlyLabelForStatusCode(e.response?.statusCode),
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
        _friendlyLabelForStatusCode(e.response?.statusCode),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Upload a file to the backend for processing.
  /// 
  /// Backend endpoint: POST /api/jobs/upload
  /// Uses multipart form data to upload the file.
  /// Returns (jobId, null) on success, (null, errorMessage) on failure.
  Future<({String? jobId, String? error})> enqueueFromFile({
    required File file,
    String? source,
    List<String>? tags,
    String? safety,
    bool? skipTagging,
  }) async {
    final uri = Uri.parse('$baseUrl/api/jobs/upload');
    final request = http.MultipartRequest('POST', uri);
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
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
      debugPrint('[BackendClient] Sending upload request to: $uri');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('[BackendClient] Upload response: ${response.statusCode}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final jobId = data['id']?.toString();
        debugPrint('[BackendClient] Upload successful, jobId: $jobId');
        return (jobId: jobId, error: null);
      } else {
        debugPrint('[BackendClient] Upload failed: ${response.statusCode} - ${response.body}');
        String message = _friendlyLabelForStatusCode(response.statusCode);
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>?;
          if (data != null) {
            final msg = data['error'] ?? data['message'] ?? data['detail'];
            if (msg != null && msg.toString().isNotEmpty) {
              message = msg.toString();
            }
          }
        } catch (_) {}
        return (jobId: null, error: message);
      }
    } catch (e, stackTrace) {
      debugPrint('[BackendClient] Exception during upload: $e');
      debugPrint('[BackendClient] Stack trace: $stackTrace');
      return (jobId: null, error: e.toString());
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
        _friendlyLabelForStatusCode(e.response?.statusCode),
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
        _friendlyLabelForStatusCode(e.response?.statusCode),
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
        _friendlyLabelForStatusCode(e.response?.statusCode),
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
        _friendlyLabelForStatusCode(e.response?.statusCode),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Retry a failed job.
  ///
  /// Backend endpoint: POST /api/jobs/{job_id}/retry
  Future<Job> retryJob(String jobId) async {
    try {
      final response = await _dio.post('/api/jobs/$jobId/retry');

      if (response.data is! Map<String, dynamic>) {
        throw const BackendException('Invalid response from server');
      }

      return Job.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw BackendException(
        _friendlyLabelForStatusCode(e.response?.statusCode),
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
        _friendlyLabelForStatusCode(e.response?.statusCode),
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Check if the backend is reachable (no auth required).
  ///
  /// Uses the public health endpoint.
  Future<bool> checkConnection() async {
    try {
      await _dio.get('/api/health', options: Options(headers: {}));
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

/// Returns a short label for an HTTP status code for display to the user.
String _friendlyLabelForStatusCode(int? code) {
  if (code == null) return 'Connection error';
  switch (code) {
    case 400:
      return 'Bad request ($code)';
    case 401:
      return 'Unauthorized ($code)';
    case 403:
      return 'Forbidden ($code)';
    case 404:
      return 'Not found ($code)';
    case 500:
      return 'Server error ($code)';
    case 502:
      return 'Bad gateway ($code)';
    case 503:
      return 'Service unavailable ($code)';
    default:
      if (code >= 400 && code < 500) return 'Client error ($code)';
      if (code >= 500) return 'Server error ($code)';
      return 'Error ($code)';
  }
}

/// Converts any error from backend/API calls into a short user-facing message.
String userFriendlyErrorMessage(Object error) {
  if (error is BackendException) return error.message;
  return 'Something went wrong';
}
