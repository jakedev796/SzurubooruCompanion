import 'dart:convert';

/// Represents a folder scheduled for periodic uploads
class ScheduledFolder {
  final String id;
  final String name;
  final String uri; // Folder path (relative under external storage or absolute)
  final int intervalSeconds; // Upload interval in seconds
  final int lastRunTimestamp; // Unix timestamp of last run
  final bool enabled;
  final List<String>? defaultTags;
  final String? defaultSafety;
  final bool skipTagging;

  ScheduledFolder({
    required this.id,
    required this.name,
    required this.uri,
    required this.intervalSeconds,
    this.lastRunTimestamp = 0,
    this.enabled = true,
    this.defaultTags,
    this.defaultSafety,
    this.skipTagging = false,
  });

  /// Calculate next run time as Unix timestamp
  int get nextRunTimestamp => lastRunTimestamp + intervalSeconds;

  /// Check if the folder is due for processing
  bool isDue(int currentTimestamp) {
    if (!enabled) return false;
    return currentTimestamp >= nextRunTimestamp;
  }

  factory ScheduledFolder.fromJson(Map<String, dynamic> json) {
    return ScheduledFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      uri: json['uri'] as String,
      intervalSeconds: json['intervalSeconds'] as int,
      lastRunTimestamp: json['lastRunTimestamp'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      defaultTags: (json['defaultTags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      defaultSafety: json['defaultSafety'] as String?,
      skipTagging: json['skipTagging'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'uri': uri,
      'intervalSeconds': intervalSeconds,
      'lastRunTimestamp': lastRunTimestamp,
      'enabled': enabled,
      'defaultTags': defaultTags,
      'defaultSafety': defaultSafety,
      'skipTagging': skipTagging,
    };
  }

  ScheduledFolder copyWith({
    String? id,
    String? name,
    String? uri,
    int? intervalSeconds,
    int? lastRunTimestamp,
    bool? enabled,
    List<String>? defaultTags,
    String? defaultSafety,
    bool? skipTagging,
  }) {
    return ScheduledFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      uri: uri ?? this.uri,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      lastRunTimestamp: lastRunTimestamp ?? this.lastRunTimestamp,
      enabled: enabled ?? this.enabled,
      defaultTags: defaultTags ?? this.defaultTags,
      defaultSafety: defaultSafety ?? this.defaultSafety,
      skipTagging: skipTagging ?? this.skipTagging,
    );
  }

  @override
  String toString() {
    return 'ScheduledFolder(id: $id, name: $name, intervalSeconds: $intervalSeconds, enabled: $enabled)';
  }
}
