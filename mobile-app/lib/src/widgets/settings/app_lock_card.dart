import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../section_card.dart';
import '../../services/app_lock_model.dart';

/// Settings card for optional app lock (device PIN/pattern/password or fingerprint).
class AppLockCard extends StatelessWidget {
  const AppLockCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'App lock',
      children: [
        Consumer<AppLockModel>(
          builder: (context, model, _) {
            return SwitchListTile(
              title: const Text('Lock app with device lock'),
              subtitle: const Text(
                'Require device PIN, pattern, password, or fingerprint to open the app.',
              ),
              value: model.isEnabled,
              onChanged: (value) async {
                if (value) {
                  final supported = await model.isDeviceSupported();
                  if (!context.mounted) return;
                  if (!supported) {
                    await showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Device lock required'),
                        content: const Text(
                          'Set a device lock or add a fingerprint in system settings, then try again.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }
                }
                await model.setEnabled(value);
              },
            );
          },
        ),
      ],
    );
  }
}
