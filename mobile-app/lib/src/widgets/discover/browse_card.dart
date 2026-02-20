import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/browse_item.dart';
import '../../theme/app_theme.dart';

/// A single card in the discover card stack showing an image preview.
class BrowseCard extends StatelessWidget {
  final BrowseItem item;
  final String? imageUrl;
  final Map<String, String>? imageHeaders;

  const BrowseCard({
    super.key,
    required this.item,
    this.imageUrl,
    this.imageHeaders,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          if (imageUrl != null && imageUrl!.isNotEmpty)
            Image.network(
              imageUrl!,
              headers: imageHeaders,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 48, color: AppColors.textMuted),
                    SizedBox(height: 8),
                    Text('Failed to load image',
                        style: TextStyle(color: AppColors.textMuted)),
                  ],
                ),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    color: AppColors.accent,
                  ),
                );
              },
            )
          else
            const Center(
              child: Icon(Icons.image_not_supported,
                  size: 48, color: AppColors.textMuted),
            ),

          // Bottom gradient overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Site name + rating badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.siteName,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _ratingColor(item.rating).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.rating,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (item.postUrl.isNotEmpty)
                        GestureDetector(
                          onTap: () => launchUrl(
                            Uri.parse(item.postUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Text(
                            '#${item.externalId}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Text(
                          '#${item.externalId}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    // Tag preview (first few tags)
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: item.tags
                          .take(5)
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _ratingColor(String rating) {
    switch (rating) {
      case 'safe':
        return AppColors.green;
      case 'sketchy':
        return AppColors.orange;
      case 'unsafe':
        return AppColors.red;
      default:
        return AppColors.textMuted;
    }
  }
}
