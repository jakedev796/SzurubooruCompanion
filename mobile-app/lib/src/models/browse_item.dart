class BrowseItem {
  final String siteName;
  final String externalId;
  final String postUrl;
  final String thumbnailUrl;
  final String previewUrl;
  final String fileUrl;
  final List<String> tags;
  final String rating;
  final int? width;
  final int? height;
  final String? source;

  const BrowseItem({
    required this.siteName,
    required this.externalId,
    required this.postUrl,
    required this.thumbnailUrl,
    required this.previewUrl,
    required this.fileUrl,
    required this.tags,
    required this.rating,
    this.width,
    this.height,
    this.source,
  });

  factory BrowseItem.fromJson(Map<String, dynamic> json) {
    return BrowseItem(
      siteName: json['site_name'] as String? ?? '',
      externalId: json['external_id'] as String? ?? '',
      postUrl: json['post_url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String? ?? '',
      previewUrl: json['preview_url'] as String? ?? '',
      fileUrl: json['file_url'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [],
      rating: json['rating'] as String? ?? 'unsafe',
      width: json['width'] as int?,
      height: json['height'] as int?,
      source: json['source'] as String?,
    );
  }
}

class BrowseResponse {
  final List<BrowseItem> items;
  final bool hasMore;
  final int page;

  const BrowseResponse({
    required this.items,
    required this.hasMore,
    required this.page,
  });

  factory BrowseResponse.fromJson(Map<String, dynamic> json) {
    return BrowseResponse(
      items: (json['items'] as List<dynamic>?)
              ?.map(
                  (item) => BrowseItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      hasMore: json['has_more'] as bool? ?? false,
      page: json['page'] as int? ?? 1,
    );
  }
}

class DiscoverSite {
  final String name;
  final bool hasCredentials;
  final bool requiresCredentials;

  const DiscoverSite({
    required this.name,
    required this.hasCredentials,
    required this.requiresCredentials,
  });

  factory DiscoverSite.fromJson(Map<String, dynamic> json) {
    return DiscoverSite(
      name: json['name'] as String? ?? '',
      hasCredentials: json['has_credentials'] as bool? ?? false,
      requiresCredentials: json['requires_credentials'] as bool? ?? false,
    );
  }

  /// Whether this site is usable (no credentials needed or credentials are configured)
  bool get isAvailable => !requiresCredentials || hasCredentials;
}

class DiscoverPreset {
  final String id;
  final String name;
  final List<String> sites;
  final String tags;
  final String rating;
  final String sort;
  final bool isDefault;

  const DiscoverPreset({
    required this.id,
    required this.name,
    required this.sites,
    required this.tags,
    required this.rating,
    this.sort = 'newest',
    required this.isDefault,
  });

  factory DiscoverPreset.fromJson(Map<String, dynamic> json) {
    return DiscoverPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sites: (json['sites'] as List<dynamic>?)
              ?.map((s) => s.toString())
              .toList() ??
          [],
      tags: json['tags'] as String? ?? '',
      rating: json['rating'] as String? ?? 'all',
      sort: json['sort'] as String? ?? 'newest',
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'sites': sites,
        'tags': tags,
        'rating': rating,
        'sort': sort,
        'is_default': isDefault,
      };
}
