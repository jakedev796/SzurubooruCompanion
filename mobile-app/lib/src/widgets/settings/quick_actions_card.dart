import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/backend_client.dart';
import '../section_card.dart';

/// Top-of-settings card giving one-tap access to actions that used to live
/// buried in folder settings: reconnect to CCC and run folder sync now.
class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({
    super.key,
    required this.isSyncingFolders,
    required this.onSyncNow,
  });

  final bool isSyncingFolders;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final state = appState.sseConnectionState;
    final (statusText, statusColor, statusIcon) = switch (state) {
      SseConnectionState.connected => ('Connected', Colors.green, Icons.check_circle),
      SseConnectionState.connecting => ('Connecting…', Colors.amber, Icons.sync),
      SseConnectionState.disconnected => ('Disconnected', Colors.redAccent, Icons.error_outline),
    };

    return SectionCard(
      title: 'Quick Actions',
      children: [
        Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 18),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: state == SseConnectionState.connecting
                    ? null
                    : () => appState.reconnect(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isSyncingFolders ? null : onSyncNow,
                icon: isSyncingFolders
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(isSyncingFolders ? 'Syncing…' : 'Sync Now'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
