import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/job.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

/// Compact job card for queue/overview list. Shows status, progress, tags, and optional post link.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    this.booruUrl,
    this.onTap,
    this.visibleTagCount = 4,
    this.onShowFullTagList,
  });

  final Job job;
  final String? booruUrl;
  final VoidCallback? onTap;
  final int visibleTagCount;
  final void Function(List<String> tags)? onShowFullTagList;

  @override
  Widget build(BuildContext context) {
    final tags = job.allTags;
    final status = job.status.toLowerCase();
    final showPostLink = (status == 'completed' || status == 'merged') &&
        job.szuruPostId != null &&
        booruUrl != null &&
        booruUrl!.isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      job.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppStatusColors.forStatus(job.status)
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      job.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppStatusColors.forStatus(job.status),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: job.progressValue / 100,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text('Progress: ${job.progressValue.toStringAsFixed(0)}%'),
              if (job.safetyDisplay.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Safety: ${job.safetyDisplay}',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: () {
                        final s = (job.post?.safety ?? job.safety)?.toLowerCase();
                        if (s == 'safe') return const Color(0xFF88D488);
                        if (s == 'sketchy') return const Color(0xFFF3D75F);
                        if (s == 'unsafe') return const Color(0xFFF3985F);
                        return AppColors.text;
                      }(),
                    ),
                  ),
                ),
              if (showPostLink)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        'View post${(job.relatedPostIds != null && job.relatedPostIds!.isNotEmpty) ? 's' : ''}:',
                        style: const TextStyle(fontSize: 13),
                      ),
                      ...{
                        if (job.szuruPostId != null) job.szuruPostId!,
                        ...(job.relatedPostIds ?? []),
                      }.map(
                        (id) => InkWell(
                          onTap: () => JobCard.openPostLink(context, booruUrl!, id),
                          child: Text(
                            '#$id',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (tags.isNotEmpty) _buildTagChips(context, tags),
              const SizedBox(height: 6),
              Text(
                'Updated ${relativeTime(job.updatedAt)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagChips(BuildContext context, List<String> tags) {
    final visible = tags.take(visibleTagCount).toList();
    final remaining = tags.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visible.map(
          (tag) => Chip(
            label: Text(tag, style: const TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
          ),
        ),
        if (remaining > 0 && onShowFullTagList != null)
          GestureDetector(
            onTap: () => onShowFullTagList!(tags),
            child: Chip(
              label: Text(
                '+$remaining',
                style: const TextStyle(fontSize: 12),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  static Future<void> openPostLink(
    BuildContext context,
    String booruUrl,
    int postId,
  ) async {
    final uri = Uri.parse('$booruUrl/post/$postId');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }
}
