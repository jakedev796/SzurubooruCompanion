import 'package:flutter/material.dart';

import '../../services/discover_state.dart';
import '../../theme/app_theme.dart';

/// Bottom sheet for configuring discover filters.
class DiscoverFilterSheet extends StatefulWidget {
  final DiscoverState discoverState;
  final VoidCallback onApply;

  const DiscoverFilterSheet({
    super.key,
    required this.discoverState,
    required this.onApply,
  });

  @override
  State<DiscoverFilterSheet> createState() => _DiscoverFilterSheetState();
}

class _DiscoverFilterSheetState extends State<DiscoverFilterSheet> {
  late List<String> _selectedSites;
  late TextEditingController _tagsController;
  late TextEditingController _excludeTagsController;
  late String _selectedRating;
  late String _selectedSort;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _selectedSites = List.from(widget.discoverState.selectedSites);
    _tagsController =
        TextEditingController(text: widget.discoverState.tags);
    _excludeTagsController =
        TextEditingController(text: widget.discoverState.excludeTags);
    _selectedRating = widget.discoverState.rating;
    _selectedSort = widget.discoverState.sort;
  }

  @override
  void dispose() {
    // Persist filter values so they survive dismiss-without-apply
    if (!_applied) {
      widget.discoverState.saveFilterDraft(
        sites: _selectedSites,
        tags: _tagsController.text.trim(),
        excludeTags: _excludeTagsController.text.trim(),
        rating: _selectedRating,
        sort: _selectedSort,
      );
    }
    _tagsController.dispose();
    _excludeTagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sites = widget.discoverState.availableSites;
    final presets = widget.discoverState.presets;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          controller: scrollController,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Discover Filters',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: _applyAndClose,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Site selection (multi-select)
            const Text('Sites',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sites.map((site) {
                final isSelected = _selectedSites.contains(site.name);
                final isAvailable = site.isAvailable;
                return FilterChip(
                  label: Text(site.name),
                  selected: isSelected,
                  onSelected: isAvailable
                      ? (selected) {
                          setState(() {
                            if (selected) {
                              _selectedSites.add(site.name);
                            } else {
                              _selectedSites.remove(site.name);
                            }
                          });
                        }
                      : null,
                  avatar: isAvailable
                      ? null
                      : const Icon(Icons.lock, size: 14),
                  tooltip: isAvailable
                      ? null
                      : 'Credentials required - configure in dashboard',
                  selectedColor: AppColors.accent.withValues(alpha: 0.3),
                  checkmarkColor: AppColors.accent,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Tags
            const Text('Tags',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                hintText: 'e.g. 1girl, blue eyes, long hair',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _applyAndClose(),
            ),
            const SizedBox(height: 12),

            // Exclude tags
            const Text('Exclude Tags',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _excludeTagsController,
              decoration: const InputDecoration(
                hintText: 'e.g. ai generated, low quality',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _applyAndClose(),
            ),
            const SizedBox(height: 16),

            // Rating
            const Text('Rating',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'safe', label: Text('Safe')),
                ButtonSegment(value: 'sketchy', label: Text('Sketchy')),
                ButtonSegment(value: 'unsafe', label: Text('Unsafe')),
              ],
              selected: {_selectedRating},
              onSelectionChanged: (selected) {
                setState(() => _selectedRating = selected.first);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(height: 16),

            // Sort
            const Text('Sort',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              const noRandomSites = {'yandere'};
              final allNoRandom = _selectedSites.isNotEmpty &&
                  _selectedSites.every(noRandomSites.contains);
              final someNoRandom = !allNoRandom &&
                  _selectedSites.any(noRandomSites.contains);

              // If all selected sites lack random, force off random
              final effectiveSort =
                  allNoRandom && _selectedSort == 'random'
                      ? 'newest'
                      : _selectedSort;
              if (effectiveSort != _selectedSort) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _selectedSort = effectiveSort);
                });
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: [
                      const ButtonSegment(
                          value: 'newest', label: Text('Newest')),
                      const ButtonSegment(
                          value: 'score', label: Text('Top')),
                      ButtonSegment(
                        value: 'random',
                        label: Text('Random'),
                        enabled: !allNoRandom,
                      ),
                    ],
                    selected: {effectiveSort},
                    onSelectionChanged: (selected) {
                      setState(() => _selectedSort = selected.first);
                    },
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  if (someNoRandom && _selectedSort == 'random')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Yandere does not reliably support random sort and will default to newest',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ),
                ],
              );
            }),

            // Presets
            if (presets.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('Presets',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              ...presets.map((preset) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(preset.name),
                    subtitle: Text(
                      '${preset.sites.join(", ")} - ${preset.tags.isEmpty ? "(no tags)" : preset.tags}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            preset.isDefault
                                ? Icons.star
                                : Icons.star_outline,
                            size: 20,
                            color: preset.isDefault
                                ? AppColors.accent
                                : null,
                          ),
                          tooltip: preset.isDefault
                              ? 'Remove default'
                              : 'Set as default',
                          onPressed: () async {
                            await widget.discoverState
                                .togglePresetDefault(preset.id);
                            if (mounted) setState(() {});
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_arrow, size: 20),
                          tooltip: 'Load preset',
                          onPressed: () {
                            widget.discoverState.applyPreset(preset);
                            widget.onApply();
                            Navigator.pop(context);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.save_outlined, size: 20),
                          tooltip: 'Overwrite with current filters',
                          onPressed: () async {
                            widget.discoverState.setFilters(
                              sites: _selectedSites,
                              tags: _tagsController.text.trim(),
                              excludeTags:
                                  _excludeTagsController.text.trim(),
                              rating: _selectedRating,
                              sort: _selectedSort,
                            );
                            await widget.discoverState
                                .updatePreset(preset);
                            if (mounted) setState(() {});
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Delete preset',
                          onPressed: () async {
                            await widget.discoverState
                                .deletePreset(preset.id);
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                  )),
            ],

            // Save as preset button
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _savePreset,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Save as Preset'),
            ),
          ],
        ),
      ),
    );
  }

  void _applyAndClose() {
    _applied = true;
    widget.discoverState.setFilters(
      sites: _selectedSites,
      tags: _tagsController.text.trim(),
      excludeTags: _excludeTagsController.text.trim(),
      rating: _selectedRating,
      sort: _selectedSort,
    );
    widget.onApply();
    Navigator.pop(context);
  }

  void _savePreset() {
    showDialog(
      context: context,
      builder: (context) {
        final nameController = TextEditingController();
        return AlertDialog(
          title: const Text('Save Preset'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  widget.discoverState.setFilters(
                    sites: _selectedSites,
                    tags: _tagsController.text.trim(),
                    excludeTags: _excludeTagsController.text.trim(),
                    rating: _selectedRating,
                    sort: _selectedSort,
                  );
                  await widget.discoverState.saveCurrentAsPreset(name);
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) setState(() {});
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
