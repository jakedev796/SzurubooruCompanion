import 'package:flutter/foundation.dart';

import '../models/browse_item.dart';
import 'backend_client.dart';

/// State management for the Discover feature.
/// Manages browsing, card stack, and filter state.
class DiscoverState extends ChangeNotifier {
  BackendClient? _client;

  // Card stack
  List<BrowseItem> _items = [];
  int _currentIndex = 0;

  // Available sites
  List<DiscoverSite> _availableSites = [];

  // Filter state
  List<String> _selectedSites = [];
  String _tags = '';
  String _excludeTags = '';
  String _rating = 'all';
  String _sort = 'newest';
  int _page = 1;

  // Loading states
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  bool _sitesLoaded = false;

  // Presets
  List<DiscoverPreset> _presets = [];

  // Public getters
  List<BrowseItem> get items => _items;
  int get currentIndex => _currentIndex;
  BrowseItem? get currentItem =>
      _currentIndex < _items.length ? _items[_currentIndex] : null;
  int get remainingItems => _items.length - _currentIndex;
  List<DiscoverSite> get availableSites => _availableSites;
  List<String> get selectedSites => _selectedSites;
  String get tags => _tags;
  String get excludeTags => _excludeTags;
  String get rating => _rating;
  String get sort => _sort;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  bool get sitesLoaded => _sitesLoaded;
  List<DiscoverPreset> get presets => _presets;
  bool get hasFiltersConfigured => _selectedSites.isNotEmpty;
  bool get hasItems => _items.isNotEmpty && _currentIndex < _items.length;
  Map<String, String>? get imageAuthHeaders => _client?.authHeaders;

  /// Update the backend client reference.
  void updateClient(BackendClient? client) {
    if (_client != client) {
      _client = client;
    }
  }

  /// Load available sites from the backend.
  Future<void> loadSites() async {
    if (_client == null) return;
    try {
      _availableSites = await _client!.fetchDiscoverSites();
      _sitesLoaded = true;

      // Auto-select all available sites if none selected
      if (_selectedSites.isEmpty && _availableSites.isNotEmpty) {
        _selectedSites = _availableSites
            .where((s) => s.isAvailable)
            .map((s) => s.name)
            .toList();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Discover] Failed to load sites: $e');
      _errorMessage = userFriendlyErrorMessage(e);
      notifyListeners();
    }
  }

  /// Set filter configuration.
  void setFilters({
    List<String>? sites,
    String? tags,
    String? excludeTags,
    String? rating,
    String? sort,
  }) {
    bool changed = false;
    if (sites != null && !listEquals(sites, _selectedSites)) {
      _selectedSites = List.from(sites);
      changed = true;
    }
    if (tags != null && tags != _tags) {
      _tags = tags;
      changed = true;
    }
    if (excludeTags != null && excludeTags != _excludeTags) {
      _excludeTags = excludeTags;
      changed = true;
    }
    if (rating != null && rating != _rating) {
      _rating = rating;
      changed = true;
    }
    if (sort != null && sort != _sort) {
      _sort = sort;
      changed = true;
    }
    if (changed) {
      _items = [];
      _currentIndex = 0;
      _page = 1;
      _hasMore = true;
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Save filter values without resetting the browse state.
  /// Used when the filter sheet is dismissed without applying.
  void saveFilterDraft({
    List<String>? sites,
    String? tags,
    String? excludeTags,
    String? rating,
    String? sort,
  }) {
    if (sites != null) _selectedSites = List.from(sites);
    if (tags != null) _tags = tags;
    if (excludeTags != null) _excludeTags = excludeTags;
    if (rating != null) _rating = rating;
    if (sort != null) _sort = sort;
  }

  /// Normalize a single tag: trim and replace internal spaces with underscores.
  static String _normalizeTag(String tag) {
    return tag.trim().replaceAll(RegExp(r'\s+'), '_');
  }

  /// Combine include and exclude tags into a booru-compatible query string.
  /// Input is comma-separated (e.g. "1girl, blue eyes") and gets normalized
  /// to space-separated underscored format (e.g. "1girl blue_eyes").
  String _buildTagsQuery() {
    final parts = <String>[];
    if (_tags.trim().isNotEmpty) {
      for (final tag in _tags.split(',')) {
        final normalized = _normalizeTag(tag);
        if (normalized.isNotEmpty) parts.add(normalized);
      }
    }
    if (_excludeTags.trim().isNotEmpty) {
      for (final tag in _excludeTags.split(',')) {
        final normalized = _normalizeTag(tag);
        if (normalized.isNotEmpty) {
          parts.add(normalized.startsWith('-') ? normalized : '-$normalized');
        }
      }
    }
    return parts.join(' ');
  }

  /// Convert booru query format back to comma-separated display format.
  /// e.g. "1girl blue_eyes" → "1girl, blue eyes"
  static String _tagsToDisplay(String query) {
    return query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => t.replaceAll('_', ' '))
        .join(', ');
  }

  /// Browse with current filters (reset).
  /// Fetches a small initial batch for fast first-load, then prefetches more.
  Future<void> browse() async {
    if (_client == null || _selectedSites.isEmpty) return;
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _items = [];
    _currentIndex = 0;
    _page = 1;
    notifyListeners();

    try {
      final response = await _client!.discoverBrowse(
        sites: _selectedSites,
        tags: _buildTagsQuery(),
        rating: _rating,
        sort: _sort,
        page: _page,
        limit: 8,
      );

      _items = response.items;
      _hasMore = response.hasMore;
      _currentIndex = 0;
    } catch (e) {
      debugPrint('[Discover] Browse failed: $e');
      _errorMessage = userFriendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Prefetch next batch in background
    if (_hasMore && _items.isNotEmpty) {
      loadMore();
    }
  }

  /// Load more items (next page).
  Future<void> loadMore() async {
    if (_client == null || _selectedSites.isEmpty) return;
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      _page++;
      final response = await _client!.discoverBrowse(
        sites: _selectedSites,
        tags: _buildTagsQuery(),
        rating: _rating,
        sort: _sort,
        page: _page,
        limit: 20,
      );

      _items.addAll(response.items);
      _hasMore = response.hasMore;
    } catch (e) {
      debugPrint('[Discover] Load more failed: $e');
      _page--;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Handle swipe right (like) - creates a job.
  Future<String?> swipeRight(BrowseItem item) async {
    if (_client == null) return null;
    try {
      final jobId = await _client!.discoverMarkSeen(
        siteName: item.siteName,
        externalId: item.externalId,
        action: 'liked',
        postUrl: item.postUrl,
      );
      _advanceCard();
      return jobId;
    } catch (e) {
      debugPrint('[Discover] Swipe right failed: $e');
      _advanceCard();
      return null;
    }
  }

  /// Handle swipe left (skip).
  Future<void> swipeLeft(BrowseItem item) async {
    if (_client == null) return;
    try {
      await _client!.discoverMarkSeen(
        siteName: item.siteName,
        externalId: item.externalId,
        action: 'skipped',
      );
    } catch (e) {
      debugPrint('[Discover] Swipe left failed: $e');
    }
    _advanceCard();
  }

  /// Advance to the next card, prefetching if needed.
  void _advanceCard() {
    _currentIndex++;
    notifyListeners();

    if (remainingItems < 8 && _hasMore && !_isLoadingMore) {
      loadMore();
    }
  }

  /// Load presets from backend.
  Future<void> loadPresets() async {
    if (_client == null) return;
    try {
      _presets = await _client!.fetchDiscoverPresets();
      notifyListeners();
    } catch (e) {
      debugPrint('[Discover] Failed to load presets: $e');
    }
  }

  /// Apply the default preset if one exists and no filters are configured yet.
  void _applyDefaultPresetIfNeeded() {
    if (_selectedSites.isNotEmpty && _tags.isNotEmpty) return;
    final defaultPreset = _presets.where((p) => p.isDefault).firstOrNull;
    if (defaultPreset != null) {
      applyPreset(defaultPreset);
    }
  }

  /// Initialize: load sites, presets, and auto-apply default preset.
  Future<void> initialize() async {
    if (_client == null) return;
    await loadSites();
    await loadPresets();
    _applyDefaultPresetIfNeeded();
  }

  /// Toggle a preset as the default.
  Future<void> togglePresetDefault(String presetId) async {
    if (_client == null) return;
    try {
      await _client!.togglePresetDefault(presetId);
      await loadPresets();
    } catch (e) {
      debugPrint('[Discover] Failed to toggle preset default: $e');
    }
  }

  /// Apply a preset's filters.
  /// Tags are stored in normalized booru format; convert back to
  /// comma-separated display format for the UI fields.
  void applyPreset(DiscoverPreset preset) {
    _selectedSites = List.from(preset.sites);
    final allTags = preset.tags.trim().split(RegExp(r'\s+'));
    final positive =
        allTags.where((t) => t.isNotEmpty && !t.startsWith('-')).toList();
    final negative = allTags
        .where((t) => t.startsWith('-'))
        .map((t) => t.substring(1))
        .toList();
    _tags = _tagsToDisplay(positive.join(' '));
    _excludeTags = _tagsToDisplay(negative.join(' '));
    _rating = preset.rating;
    _sort = preset.sort;
    _items = [];
    _currentIndex = 0;
    _page = 1;
    _hasMore = true;
    _errorMessage = null;
    notifyListeners();
  }

  /// Save current filters as a preset.
  Future<DiscoverPreset?> saveCurrentAsPreset(String name) async {
    if (_client == null) return null;
    try {
      final preset = DiscoverPreset(
        id: '',
        name: name,
        sites: _selectedSites,
        tags: _buildTagsQuery(),
        rating: _rating,
        sort: _sort,
        isDefault: false,
      );
      final saved = await _client!.saveDiscoverPreset(preset);
      await loadPresets();
      return saved;
    } catch (e) {
      debugPrint('[Discover] Failed to save preset: $e');
      return null;
    }
  }

  /// Update an existing preset with current filter values.
  Future<void> updatePreset(DiscoverPreset existing) async {
    if (_client == null) return;
    try {
      final updated = DiscoverPreset(
        id: existing.id,
        name: existing.name,
        sites: _selectedSites,
        tags: _buildTagsQuery(),
        rating: _rating,
        sort: _sort,
        isDefault: existing.isDefault,
      );
      await _client!.updateDiscoverPreset(existing.id, updated);
      await loadPresets();
    } catch (e) {
      debugPrint('[Discover] Failed to update preset: $e');
    }
  }

  /// Delete a preset.
  Future<void> deletePreset(String presetId) async {
    if (_client == null) return;
    try {
      await _client!.deleteDiscoverPreset(presetId);
      await loadPresets();
    } catch (e) {
      debugPrint('[Discover] Failed to delete preset: $e');
    }
  }

  /// Build the proxy URL for an image.
  String? buildImageUrl(String sourceUrl) {
    if (_client == null || sourceUrl.isEmpty) return null;
    return _client!.buildImageProxyUrl(sourceUrl);
  }
}
