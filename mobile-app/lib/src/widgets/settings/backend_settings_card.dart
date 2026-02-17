import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth.dart';
import '../../services/backend_client.dart';
import '../../services/settings_model.dart';
import '../section_card.dart';

class BackendSettingsCard extends StatelessWidget {
  const BackendSettingsCard({
    super.key,
    required this.backendUrlController,
    required this.backendUrlFocusNode,
  });

  final TextEditingController backendUrlController;
  final FocusNode backendUrlFocusNode;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    return SectionCard(
      title: 'Backend Settings',
      initiallyExpanded: true,
      children: [
        TextFormField(
          controller: backendUrlController,
          focusNode: backendUrlFocusNode,
          decoration: const InputDecoration(
            labelText: 'Backend URL',
            hintText: 'https://your-bot.booru',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Backend URL is required';
            }
            if (!value.startsWith('http://') && !value.startsWith('https://')) {
              return 'URL must start with http:// or https://';
            }
            return null;
          },
        ),
        if (settings.isAuthenticated) ...[
          const SizedBox(height: 12),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text('Logged in as ${settings.username}'),
            subtitle: const Text('Tap to logout'),
            trailing: const Icon(Icons.logout),
            onTap: () => _handleLogout(context, settings),
          ),
        ],
      ],
    );
  }

  Future<void> _handleLogout(BuildContext context, SettingsModel settings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
          'Are you sure you want to logout? Your settings will be synced before logging out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final client = BackendClient(baseUrl: settings.backendUrl);
      final prefs = await SharedPreferences.getInstance();
      final authJson = prefs.getString('auth_tokens');
      if (authJson != null) {
        final tokens = AuthTokens.fromJson(jsonDecode(authJson));
        client.setAccessToken(tokens.accessToken);
        await client.savePreferences(await settings.getSyncablePreferences());
      }
    } catch (e) {
      debugPrint('Failed to sync preferences on logout: $e');
    }

    if (context.mounted) {
      await settings.setAuthState(false, '', null);
      if (context.mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }
}
