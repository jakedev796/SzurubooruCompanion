import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/job.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// Bottom-sheet content for job details: status, actions, sources, tags, metadata.
class JobDetailSheetContent extends StatefulWidget {
  const JobDetailSheetContent({
    super.key,
    required this.jobId,
    required this.scrollController,
    this.booruUrl,
    required this.onOpenPost,
  });

  final String jobId;
  final ScrollController scrollController;
  final String? booruUrl;
  final Future<void> Function(String?, int) onOpenPost;

  @override
  State<JobDetailSheetContent> createState() => _JobDetailSheetContentState();
}

List<String> _sortTags(List<String> tags) {
  final list = List<String>.from(tags);
  list.sort((a, b) {
    final aDigit = a.isNotEmpty && RegExp(r'^\d').hasMatch(a);
    final bDigit = b.isNotEmpty && RegExp(r'^\d').hasMatch(b);
    if (aDigit && !bDigit) return -1;
    if (!aDigit && bDigit) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return list;
}

class _JobDetailSheetContentState extends State<JobDetailSheetContent> {
  Job? _job;
  bool _loading = true;
  String? _actionLoading;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _fetchJob();
  }

  Future<void> _fetchJob() async {
    final appState = context.read<AppState>();
    final job = await appState.fetchJob(widget.jobId);
    if (mounted) {
      setState(() {
        _job = job;
        _loading = false;
      });
    }
  }

  Future<void> _runAction(Future<String?> Function() action, String name) async {
    setState(() {
      _actionError = null;
      _actionLoading = name;
    });
    try {
      final error = await action();
      if (!mounted) return;
      if (error != null) {
        setState(() => _actionError = error);
      } else {
        await _fetchJob();
      }
    } finally {
      if (mounted) setState(() => _actionLoading = null);
    }
  }

  Future<void> _deleteJob() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job'),
        content: const Text('Are you sure you want to delete this job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final appState = context.read<AppState>();
    final error = await appState.deleteJob(widget.jobId);
    if (!mounted) return;
    if (error != null) {
      setState(() => _actionError = error);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }

  static String _formatDate(DateTime? d) {
    if (d == null) return '-';
    final s = d.toIso8601String();
    final i = s.indexOf('.');
    return (i > 0 ? s.substring(0, i) : s).replaceFirst('T', ' ');
  }

  static const Color _tagSourceBg = Color(0x1E22D3EE);
  static const Color _tagSourceFg = Color(0xFF67E8F9);
  static const Color _tagAiBg = Color(0x33C41E3A);
  static const Color _tagAiFg = Color(0xFFF0A0A8);
  static const Color _tagOtherBg = Color(0x0FFFFFFF);
  static const Color _tagOtherFg = Color(0xFFA39D93);

  Widget _tagChip(String tag, String variant) {
    Color bg;
    Color fg;
    switch (variant) {
      case 'source':
        bg = _tagSourceBg;
        fg = _tagSourceFg;
        break;
      case 'ai':
        bg = _tagAiBg;
        fg = _tagAiFg;
        break;
      default:
        bg = _tagOtherBg;
        fg = _tagOtherFg;
    }
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withOpacity(0.35)),
      ),
      child: Text(tag, style: TextStyle(fontSize: 12, color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final job = _job;
    if (job == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Job not found',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    final appState = context.read<AppState>();
    final sources = job.sources;
    final statusColor = AppStatusColors.forStatus(job.status);

    final actionButtons = <Widget>[];
    void addButton(String label, Future<String?> Function() action, Color color, {IconData? icon, bool iconOnly = false}) {
      final button = ElevatedButton(
        onPressed: _actionLoading != null
            ? null
            : () => _runAction(action, label.toLowerCase()),
        style: ElevatedButton.styleFrom(backgroundColor: color),
        child: iconOnly && icon != null
            ? (_actionLoading == label.toLowerCase()
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, size: 18))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    _actionLoading == label.toLowerCase()
                        ? '${label}ing...'
                        : label,
                  ),
                ],
              ),
      );
      actionButtons.add(
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: iconOnly ? Tooltip(message: label, child: button) : button,
        ),
      );
    }

    final jobId = widget.jobId;
    switch (job.status.toLowerCase()) {
      case 'pending':
        addButton('Start', () => appState.startJob(jobId), AppColors.green);
        break;
      case 'downloading':
      case 'tagging':
      case 'uploading':
        addButton('Pause', () => appState.pauseJob(jobId), AppColors.orange);
        addButton('Stop', () => appState.stopJob(jobId), AppColors.red);
        break;
      case 'paused':
      case 'stopped':
        addButton('Resume', () => appState.resumeJob(jobId), AppColors.green);
        break;
      case 'failed':
        addButton('Retry', () => appState.retryJob(jobId), AppColors.yellow, icon: Icons.refresh, iconOnly: true);
        break;
    }

    final sortedTagsFromSource = _sortTags(job.tagsFromSource);
    final sortedTagsFromAi = _sortTags(job.tagsFromAi);
    final sourceLower = job.tagsFromSource.map((t) => t.toLowerCase()).toSet();
    final aiLower = job.tagsFromAi.map((t) => t.toLowerCase()).toSet();
    final seenLower = <String>{};
    final mergedForSzuru = <String>[
      ...job.tagsFromSource.where((t) => seenLower.add(t.toLowerCase())),
      ...job.tagsFromAi.where((t) => seenLower.add(t.toLowerCase())),
    ];
    final sortedTagsOnSzuru = _sortTags(mergedForSzuru);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Job ${job.id}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 22),
              onPressed: _actionLoading != null ? null : _deleteJob,
              tooltip: 'Delete job',
              style: IconButton.styleFrom(
                foregroundColor: AppColors.red,
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(36, 36),
              ),
            ),
          ],
        ),
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _actionError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ),
        if (actionButtons.isNotEmpty) ...[
          Wrap(children: actionButtons),
          const SizedBox(height: 16),
        ],
        _detailRow(
          'Status',
          Text(
            job.status,
            style: TextStyle(
              fontSize: 14,
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        _detailRow('Type', Text(job.jobType)),
        _detailRow(
          sources.length > 1 ? 'Sources' : 'URL',
          sources.isEmpty
              ? const Text('-', style: TextStyle(fontSize: 13))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: sources
                      .map((url) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () => _openUrl(url),
                              child: Text(
                                url,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
        ),
        _detailRow(
          'Filename',
          Text(
            job.originalFilename ?? '-',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        _detailRow(
          'Safety',
          Text(
            job.safetyDisplay,
            style: TextStyle(
              fontSize: 13,
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
        _detailRow(
          'Upload User',
          Text(job.dashboardUsername ?? '-', style: const TextStyle(fontSize: 13)),
        ),
        if (job.szuruPostId != null && widget.booruUrl != null)
          _detailRow(
            'Szuru Post ID',
            InkWell(
              onTap: () =>
                  widget.onOpenPost(widget.booruUrl, job.szuruPostId!),
              child: Text(
                'View post #${job.szuruPostId}',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (job.relatedPostIds != null && job.relatedPostIds!.isNotEmpty)
          _detailRow(
            'Related posts',
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: widget.booruUrl != null
                  ? job.relatedPostIds!
                      .map((id) => InkWell(
                            onTap: () =>
                                widget.onOpenPost(widget.booruUrl, id),
                            child: Text(
                              '#$id',
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ))
                      .toList()
                  : [
                      Text(
                        job.relatedPostIds!
                            .map((id) => '#$id')
                            .join(', '),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
            ),
          ),
        _detailRow(
          'Skip Tagging',
          Text(
            job.skipTagging ? 'Yes' : 'No',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (sortedTagsFromSource.isNotEmpty)
          _detailRow(
            'Tags from source',
            Wrap(
              children: sortedTagsFromSource
                  .map((t) => _tagChip(t, 'source'))
                  .toList(),
            ),
          ),
        if (sortedTagsFromAi.isNotEmpty)
          _detailRow(
            'Tags from AI',
            Wrap(
              children:
                  sortedTagsFromAi.map((t) => _tagChip(t, 'ai')).toList(),
            ),
          ),
        if (sortedTagsOnSzuru.isNotEmpty)
          _detailRow(
            'Tags (on Szurubooru)',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Combined from source, AI, and metadata. '
                    'Colors match origin above.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Wrap(
                  children: sortedTagsOnSzuru.map((t) {
                    final key = t.toLowerCase();
                    final variant = sourceLower.contains(key)
                        ? 'source'
                        : (aiLower.contains(key) ? 'ai' : 'other');
                    return _tagChip(t, variant);
                  }).toList(),
                ),
              ],
            ),
          ),
        _detailRow(
          'Error',
          Text(
            job.errorMessage ?? '-',
            style: TextStyle(
              fontSize: 13,
              color: job.errorMessage != null ? AppColors.red : null,
            ),
          ),
        ),
        _detailRow(
          'Retries',
          Text('${job.retryCount}', style: const TextStyle(fontSize: 13)),
        ),
        _detailRow(
          'Created',
          Text(_formatDate(job.createdAt), style: const TextStyle(fontSize: 13)),
        ),
        _detailRow(
          'Updated',
          Text(_formatDate(job.updatedAt), style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _detailRow(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }
}
