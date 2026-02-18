import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../section_card.dart';
import '../../services/notification_service.dart';
import '../../services/update_service.dart';

class AboutCard extends StatefulWidget {
  const AboutCard({
    super.key,
    required this.onShowMessage,
  });

  final void Function(String message) onShowMessage;

  @override
  State<AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<AboutCard> {
  String _versionText = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _versionText = '${info.version} (${info.buildNumber})');
  }

  Future<void> _checkForUpdates() async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    try {
      final updateService = await UpdateService.getInstance();
      final result = await updateService.checkAndNotifyUpdate(
        ignoreSkipped: true,
        isManualCheck: true,
      );
      if (!mounted) return;
      if (result == UpdateService.checkResultNoUpdate) {
        widget.onShowMessage('Already up to date.');
      } else if (result == UpdateService.checkResultError) {
        widget.onShowMessage('Could not check for updates.');
      } else if (result == UpdateService.checkResultUpdateAvailable) {
        final pending = updateService.getPendingUpdate();
        if (pending != null) await _showUpdateDialog(pending, updateService);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdateDialog(RemoteVersion remote, UpdateService updateService) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update ${remote.versionName} available'),
        content: SingleChildScrollView(
          child: Text(remote.changelog.isNotEmpty ? remote.changelog : 'Tap Download to get the update.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Skip this version'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'download'),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'skip') {
      updateService.markVersionSkipped(remote.versionCode);
      widget.onShowMessage('Skipped version ${remote.versionName}.');
    } else {
      await NotificationService.instance.showUpdateAvailable(
        versionName: remote.versionName,
        changelog: remote.changelog,
      );
      widget.onShowMessage('Tap the notification to download.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'About',
      initiallyExpanded: false,
      children: [
        if (_versionText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Version $_versionText'),
          ),
        ListTile(
          title: const Text('Check for updates'),
          subtitle: _checking ? const Text('Checking...') : null,
          enabled: !_checking,
          onTap: _checking ? null : _checkForUpdates,
        ),
      ],
    );
  }
}
