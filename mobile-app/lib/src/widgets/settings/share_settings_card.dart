import 'package:flutter/material.dart';

import '../section_card.dart';

class ShareSettingsCard extends StatelessWidget {
  const ShareSettingsCard({
    super.key,
    required this.useBackgroundService,
    required this.defaultTagsController,
    required this.defaultTagsFocusNode,
    required this.selectedSafety,
    required this.skipTagging,
    required this.onUseBackgroundServiceChanged,
    required this.onSelectedSafetyChanged,
    required this.onSkipTaggingChanged,
    required this.onAutoSave,
  });

  final bool useBackgroundService;
  final TextEditingController defaultTagsController;
  final FocusNode defaultTagsFocusNode;
  final String selectedSafety;
  final bool skipTagging;
  final ValueChanged<bool> onUseBackgroundServiceChanged;
  final ValueChanged<String> onSelectedSafetyChanged;
  final ValueChanged<bool> onSkipTaggingChanged;
  final VoidCallback onAutoSave;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Share Settings',
      children: [
        SwitchListTile(
          title: const Text('Background processing'),
          subtitle: const Text(
            'Use WorkManager to queue shares without opening the UI',
          ),
          value: useBackgroundService,
          onChanged: (value) {
            onUseBackgroundServiceChanged(value);
            onAutoSave();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: defaultTagsController,
          focusNode: defaultTagsFocusNode,
          decoration: const InputDecoration(
            labelText: 'Default tags',
            hintText: 'tagme, favorite',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selectedSafety,
          decoration: const InputDecoration(
            labelText: 'Default safety',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'safe', child: Text('Safe')),
            DropdownMenuItem(value: 'sketchy', child: Text('Sketchy')),
            DropdownMenuItem(value: 'unsafe', child: Text('Unsafe')),
          ],
          onChanged: (value) {
            onSelectedSafetyChanged(value ?? 'unsafe');
            onAutoSave();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Skip auto-tagging'),
          subtitle: const Text(
            'Disable automatic tagging from source and AI',
          ),
          value: skipTagging,
          onChanged: (value) {
            onSkipTaggingChanged(value);
            onAutoSave();
          },
        ),
      ],
    );
  }
}
