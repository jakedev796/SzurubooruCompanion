import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/discover_state.dart';
import '../theme/app_theme.dart';
import '../widgets/discover/browse_card.dart';
import '../widgets/discover/filter_sheet.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;

  static const double _swipeThreshold = 100.0;
  static const double _maxRotation = 0.3;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final discover = context.read<DiscoverState>();
      if (!discover.sitesLoaded) {
        discover.initialize();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DiscoverState>(
      builder: (context, discover, child) {
        if (!discover.sitesLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            _buildFilterBar(discover),
            Expanded(child: _buildBody(discover)),
            if (discover.hasItems) _buildActionButtons(discover),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(DiscoverState discover) {
    final sitesLabel = discover.selectedSites.isEmpty
        ? ''
        : discover.selectedSites.length == 1
            ? discover.selectedSites.first
            : '${discover.selectedSites.length} sites';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (sitesLabel.isNotEmpty)
            Chip(
              label: Text(sitesLabel),
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.accent.withValues(alpha: 0.2),
            ),
          if (discover.tags.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Chip(
                label: Text(
                  discover.tags,
                  overflow: TextOverflow.ellipsis,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Filters',
            onPressed: () => _showFilterSheet(discover),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(DiscoverState discover) {
    if (discover.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.red),
              const SizedBox(height: 12),
              Text(
                discover.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: discover.browse,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (discover.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!discover.hasFiltersConfigured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.explore_outlined,
                  size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text(
                'Configure filters to start discovering',
                style: TextStyle(fontSize: 16, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showFilterSheet(discover),
                icon: const Icon(Icons.tune),
                label: const Text('Set Filters'),
              ),
            ],
          ),
        ),
      );
    }

    if (!discover.hasItems) {
      // Still loading more results — show spinner instead of "no results"
      if (discover.isLoadingMore) {
        return const Center(child: CircularProgressIndicator());
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off,
                  size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                discover.items.isEmpty
                    ? 'No results found'
                    : 'No more results',
                style:
                    const TextStyle(fontSize: 16, color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                discover.items.isEmpty
                    ? 'Try different tags or site'
                    : 'Try adjusting your filters',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: discover.browse,
                child: const Text('Search Again'),
              ),
            ],
          ),
        ),
      );
    }

    return _buildCardStack(discover);
  }

  Widget _buildCardStack(DiscoverState discover) {
    final currentItem = discover.currentItem;
    if (currentItem == null) return const SizedBox.shrink();

    final nextIndex = discover.currentIndex + 1;
    final hasNext = nextIndex < discover.items.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Next card (behind, slightly smaller)
          if (hasNext)
            Transform.scale(
              scale: 0.95,
              child: Opacity(
                opacity: 0.6,
                child: BrowseCard(
                  item: discover.items[nextIndex],
                  imageUrl: discover
                      .buildImageUrl(discover.items[nextIndex].previewUrl),
                  imageHeaders: _buildAuthHeaders(discover),
                ),
              ),
            ),

          // Current card (top, draggable)
          GestureDetector(
            onPanStart: (_) => _onDragStart(),
            onPanUpdate: (details) => _onDragUpdate(details),
            onPanEnd: (details) => _onDragEnd(details, discover),
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final offset = _isDragging
                    ? _dragOffset
                    : Offset.lerp(_dragOffset, Offset.zero,
                            _animController.value) ??
                        Offset.zero;
                final rotation =
                    (offset.dx / MediaQuery.of(context).size.width) *
                        _maxRotation;

                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translate(offset.dx, offset.dy, 0.0)
                    ..rotateZ(rotation),
                  child: Stack(
                    children: [
                      child!,
                      // Like/skip indicators
                      if (offset.dx.abs() > 30)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: offset.dx > 0
                                    ? AppColors.green
                                    : AppColors.red,
                                width: 3,
                              ),
                            ),
                            child: Align(
                              alignment: offset.dx > 0
                                  ? Alignment.topLeft
                                  : Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Transform.rotate(
                                  angle: offset.dx > 0 ? -0.3 : 0.3,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: offset.dx > 0
                                            ? AppColors.green
                                            : AppColors.red,
                                        width: 2,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      offset.dx > 0 ? 'LIKE' : 'SKIP',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: offset.dx > 0
                                            ? AppColors.green
                                            : AppColors.red,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
              child: BrowseCard(
                item: currentItem,
                imageUrl: discover.buildImageUrl(currentItem.previewUrl),
                imageHeaders: _buildAuthHeaders(discover),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(DiscoverState discover) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.close,
            color: AppColors.red,
            size: 56,
            onPressed: () {
              final item = discover.currentItem;
              if (item != null) discover.swipeLeft(item);
            },
          ),
          Text(
            '${discover.remainingItems} left',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
          ),
          _ActionButton(
            icon: Icons.favorite,
            color: AppColors.green,
            size: 56,
            onPressed: () {
              final item = discover.currentItem;
              if (item != null) {
                discover.swipeRight(item);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Job created'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Map<String, String>? _buildAuthHeaders(DiscoverState discover) {
    return discover.imageAuthHeaders;
  }

  void _showFilterSheet(DiscoverState discover) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DiscoverFilterSheet(
        discoverState: discover,
        onApply: () => discover.browse(),
      ),
    );
  }

  void _onDragStart() {
    _isDragging = true;
    _animController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
    });
  }

  void _onDragEnd(DragEndDetails details, DiscoverState discover) {
    _isDragging = false;
    final item = discover.currentItem;

    if (_dragOffset.dx.abs() > _swipeThreshold && item != null) {
      if (_dragOffset.dx > 0) {
        discover.swipeRight(item);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Job created'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        discover.swipeLeft(item);
      }
      _dragOffset = Offset.zero;
      setState(() {});
    } else {
      _animController.forward(from: 0).then((_) {
        if (mounted) {
          setState(() => _dragOffset = Offset.zero);
        }
      });
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor: color.withValues(alpha: 0.15),
          side: BorderSide(color: color, width: 2),
        ),
        child: Icon(icon, color: color, size: size * 0.45),
      ),
    );
  }
}
