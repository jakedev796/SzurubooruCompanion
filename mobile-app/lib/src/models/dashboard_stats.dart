/// Result of GET /api/stats for dashboard overview.
class DashboardStats {
  const DashboardStats({
    required this.byStatus,
    this.totalJobs,
    this.averageJobDurationSeconds,
    this.jobsLast24h,
  });

  final Map<String, int> byStatus;
  final int? totalJobs;
  final double? averageJobDurationSeconds;
  final int? jobsLast24h;

  static const List<String> _statusKeys = [
    'pending', 'downloading', 'tagging', 'uploading', 'completed', 'merged', 'failed',
  ];

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final byStatusRaw = json['by_status'] as Map<String, dynamic>?;
    final byStatus = <String, int>{};
    for (final k in _statusKeys) {
      byStatus[k] = 0;
    }
    if (byStatusRaw != null) {
      for (final e in byStatusRaw.entries) {
        final v = e.value;
        byStatus[e.key] = v is int ? v : (v is num ? v.toInt() : 0);
      }
    }
    final totalJobs = json['total_jobs'] as int?;
    final avgSec = json['average_job_duration_seconds'];
    final averageJobDurationSeconds =
        avgSec is num ? avgSec.toDouble() : (avgSec != null ? double.tryParse(avgSec.toString()) : null);
    final jobsLast24h = json['jobs_last_24h'] as int?;
    return DashboardStats(
      byStatus: byStatus,
      totalJobs: totalJobs,
      averageJobDurationSeconds: averageJobDurationSeconds,
      jobsLast24h: jobsLast24h,
    );
  }
}
