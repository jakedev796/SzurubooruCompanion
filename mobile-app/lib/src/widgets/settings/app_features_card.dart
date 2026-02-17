import 'package:flutter/material.dart';

import '../section_card.dart';

class AppFeaturesCard extends StatelessWidget {
  const AppFeaturesCard({
    super.key,
    required this.showFloatingBubble,
    required this.onShowFloatingBubbleChanged,
  });

  final bool showFloatingBubble;
  final Future<void> Function(bool value) onShowFloatingBubbleChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'App Features',
      children: [
        SwitchListTile(
          title: const Text('Floating bubble'),
          subtitle: const Text(
            'Show a floating bubble overlay. Tap it to queue whatever URL is in your clipboard.',
          ),
          value: showFloatingBubble,
          onChanged: (value) async {
            onShowFloatingBubbleChanged(value);
          },
        ),
      ],
    );
  }
}
