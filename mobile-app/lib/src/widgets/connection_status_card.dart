import 'package:flutter/material.dart';

import '../services/backend_client.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

/// Card showing SSE connection status and last update time.
class ConnectionStatusCard extends StatelessWidget {
  const ConnectionStatusCard({
    super.key,
    required this.connectionState,
    this.lastUpdated,
  });

  final SseConnectionState connectionState;
  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    switch (connectionState) {
      case SseConnectionState.connected:
        statusText = 'Connected - Real-time updates active';
        statusIcon = Icons.check_circle;
        statusColor = AppColors.green;
        break;
      case SseConnectionState.connecting:
        statusText = 'Connecting...';
        statusIcon = Icons.sync;
        statusColor = AppColors.orange;
        break;
      case SseConnectionState.disconnected:
        statusText = 'Disconnected';
        statusIcon = Icons.cloud_off;
        statusColor = AppColors.textMuted;
        break;
    }

    return Card(
      color: statusColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (lastUpdated != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last update: ${relativeTime(lastUpdated!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
