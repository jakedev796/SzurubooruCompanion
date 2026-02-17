/// Job model matching the CCC backend API schema.
///
/// Note: For completed jobs, the backend may also return a `post` mirror
/// with its own safety rating. When present, we prefer `post.safety` over
/// the job-level `safety` value for display purposes.
class SzuruPostMirror {
  final int id;
  final List<String> tags;
  final String? source;
  final String? safety;
  final List<int> relations;

  SzuruPostMirror({
    required this.id,
    required this.tags,
    this.source,
    this.safety,
    required this.relations,
  });

  factory SzuruPostMirror.fromJson(Map<String, dynamic> json) {
    return SzuruPostMirror(
      id: json['id'] as int,
      tags: Job._parseStringList(json['tags']),
      source: json['source'] as String?,
      safety: json['safety'] as String?,
      relations: Job._parseIntList(json['relations']) ?? const [],
    );
  }
}

/// Job model as returned by the backend.
class Job {
  final String id;
  final String status;
  final String jobType;
  final String? url;
  final String? originalFilename;
  final String? sourceOverride;
  final String? safety;
  final bool skipTagging;
  final int? szuruPostId;
  final List<int>? relatedPostIds;
  final String? errorMessage;
  final List<String> tagsApplied;
  final List<String> tagsFromSource;
  final List<String> tagsFromAi;
  final String? szuruUser;
  final String? dashboardUsername;
  final int retryCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SzuruPostMirror? post;

  Job({
    required this.id,
    required this.status,
    required this.jobType,
    this.url,
    this.originalFilename,
    this.sourceOverride,
    this.safety,
    this.skipTagging = false,
    this.szuruPostId,
    this.relatedPostIds,
    this.errorMessage,
    this.tagsApplied = const [],
    this.tagsFromSource = const [],
    this.tagsFromAi = const [],
    this.szuruUser,
    this.dashboardUsername,
    this.retryCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.post,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      jobType: json['job_type']?.toString() ?? 'url',
      url: json['url'] as String?,
      originalFilename: json['original_filename'] as String?,
      sourceOverride: json['source_override'] as String?,
      safety: json['safety'] as String?,
      skipTagging: json['skip_tagging'] == true || json['skip_tagging'] == 1,
      szuruPostId: json['szuru_post_id'] as int?,
      relatedPostIds: _parseIntList(json['related_post_ids']),
      errorMessage: json['error_message'] as String?,
      tagsApplied: _parseStringList(json['tags_applied']),
      tagsFromSource: _parseStringList(json['tags_from_source']),
      tagsFromAi: _parseStringList(json['tags_from_ai']),
      szuruUser: json['szuru_user'] as String?,
      dashboardUsername: json['dashboard_username'] as String?,
      retryCount: json['retry_count'] as int? ?? 0,
      createdAt: _parseDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(json['updated_at']) ?? DateTime.now(),
      post: json['post'] is Map<String, dynamic>
          ? SzuruPostMirror.fromJson(json['post'] as Map<String, dynamic>)
          : null,
    );
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return [];
  }

  static List<int>? _parseIntList(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.whereType<int>().toList();
    }
    return null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  /// Display name for the job - shows filename or URL
  String get displayName {
    if (originalFilename != null && originalFilename!.isNotEmpty) {
      return originalFilename!;
    }
    if (url != null && url!.isNotEmpty) {
      // Extract the last part of URL for display
      final parts = url!.split('/');
      if (parts.isNotEmpty) {
        return parts.last.split('?').first;
      }
      return url!;
    }
    return 'Job $id';
  }

  /// Progress value (0-100) - for URL jobs, we don't have real progress
  /// so we return 0 for pending, 25 for downloading, 50 for tagging,
  /// 75 for uploading, 100 for completed/merged
  double get progressValue {
    switch (status.toLowerCase()) {
      case 'pending':
        return 0.0;
      case 'downloading':
        return 25.0;
      case 'tagging':
        return 50.0;
      case 'uploading':
        return 75.0;
      case 'completed':
      case 'merged':
        return 100.0;
      case 'failed':
        return 0.0;
      case 'paused':
        return 50.0; // Paused shows partial progress
      case 'stopped':
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// All tags combined from different sources
  List<String> get allTags => [...tagsApplied, ...tagsFromSource, ...tagsFromAi];

  /// Source URL for the job
  List<String> get sources {
    if (sourceOverride != null && sourceOverride!.isNotEmpty) {
      return [sourceOverride!];
    }
    if (url != null && url!.isNotEmpty) {
      return [url!];
    }
    return [];
  }

  /// Whether this job has failed
  bool get hasFailed => status.toLowerCase() == 'failed' && 
      errorMessage != null && 
      errorMessage!.isNotEmpty;

  /// Whether this job is completed (successfully, merged, or failed)
  bool get isCompleted {
    final s = status.toLowerCase();
    return s == 'completed' || s == 'merged' || s == 'failed';
  }

  /// Whether this job is currently being processed (any active status)
  bool get isActive => ['downloading', 'tagging', 'uploading'].contains(status.toLowerCase());

  /// Whether this job is waiting to be processed
  bool get isWaiting => status.toLowerCase() == 'pending';

  /// Whether this job is paused
  bool get isPaused => status.toLowerCase() == 'paused';

  /// Whether this job is stopped
  bool get isStopped => status.toLowerCase() == 'stopped';

  /// Whether this job can be started (paused or stopped)
  bool get canStart => isPaused || isStopped;

  /// Whether this job can be paused (pending or actively processing)
  bool get canPause => status.toLowerCase() == 'pending' || 
      ['downloading', 'tagging', 'uploading'].contains(status.toLowerCase());

  /// Whether this job can be stopped (not completed or failed)
  bool get canStop => !isCompleted && !isStopped;

  /// Whether this job can be resumed (paused only)
  bool get canResume => isPaused;

  /// Status icon for display
  String get statusIcon {
    switch (status.toLowerCase()) {
      case 'pending':
        return '⏳';
      case 'downloading':
        return '📥';
      case 'tagging':
        return '🏷️';
      case 'uploading':
        return '📤';
      case 'completed':
        return '✅';
      case 'failed':
        return '❌';
      case 'paused':
        return '⏸️';
      case 'stopped':
        return '⏹️';
      default:
        return '❓';
    }
  }

  /// Safety rating display (text only, no status icons)
  String get safetyDisplay {
    final s = (post?.safety ?? safety)?.toLowerCase();
    switch (s) {
      case 'safe':
        return 'Safe';
      case 'sketchy':
        return 'Sketchy';
      case 'unsafe':
        return 'Unsafe';
      default:
        return 'Unsafe';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'job_type': jobType,
      'url': url,
      'original_filename': originalFilename,
      'source_override': sourceOverride,
      'safety': safety,
      'skip_tagging': skipTagging,
      'szuru_post_id': szuruPostId,
      'related_post_ids': relatedPostIds,
      'error_message': errorMessage,
      'tags_applied': tagsApplied,
      'tags_from_source': tagsFromSource,
      'tags_from_ai': tagsFromAi,
      'szuru_user': szuruUser,
      'dashboard_username': dashboardUsername,
      'retry_count': retryCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (post != null)
        'post': {
          'id': post!.id,
          'tags': post!.tags,
          'source': post!.source,
          'safety': post!.safety,
          'relations': post!.relations,
        },
    };
  }

  @override
  String toString() {
    return 'Job(id: $id, status: $status, type: $jobType, displayName: $displayName)';
  }
}
