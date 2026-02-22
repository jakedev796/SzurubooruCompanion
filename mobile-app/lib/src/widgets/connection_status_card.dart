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
    this.onReconnect,
  });

  final SseConnectionState connectionState;
  final DateTime? lastUpdated;
  final VoidCallback? onReconnect;

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

    final canReconnect = onReconnect != null &&
        (connectionState == SseConnectionState.disconnected ||
            connectionState == SseConnectionState.connecting);

    Widget cardContent = Padding(
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
          if (connectionState == SseConnectionState.disconnected && onReconnect != null) ...[
            const SizedBox(height: 4),
            const Text(
              'Tap to reconnect',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );

    return Card(
      color: statusColor.withOpacity(0.1),
      child: canReconnect
          ? InkWell(
              onTap: onReconnect,
              borderRadius: BorderRadius.circular(12),
              child: cardContent,
            )
          : cardContent,
    );
  }
}
