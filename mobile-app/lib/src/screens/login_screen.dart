import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:provider/provider.dart';

import '../models/auth.dart';
import '../services/backend_client.dart';
import '../services/floating_bubble_service.dart';
import '../services/settings_model.dart';
import '../services/storage_permission.dart';

/// Login screen for JWT authentication (Step 2 of 2)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isRestoreInProgress = false;

  Future<void> _promptPermissionsBeforeRestore(
      Map<String, bool> permissionsNeeded) async {
    if (!mounted) return;

    if (permissionsNeeded['needsOverlayPermission'] == true) {
      final hasOverlay = await canDrawOverlays();
      if (!hasOverlay && mounted) {
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Overlay Permission'),
            content: const Text(
              'Your backup has the floating bubble enabled. '
              'Grant "Display over other apps" permission to use it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Grant'),
              ),
            ],
          ),
        );
        if (shouldRequest == true && mounted) {
          await requestOverlayPermission();
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    }

    if (!mounted) return;
    if (permissionsNeeded['needsStoragePermission'] == true) {
      final hasStorage = await StoragePermissionService.hasStoragePermission();
      if (!hasStorage && mounted) {
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Storage Permission'),
            content: const Text(
              'Your backup has folder sync enabled. '
              'Grant "All files access" permission for background sync to work?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Grant'),
              ),
            ],
          ),
        );
        if (shouldRequest == true && mounted) {
          await StoragePermissionService.requestStoragePermission();
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
  }

  Future<void> _handleRestoreFromBackup() async {
    if (_isRestoreInProgress || _isLoading) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.single;
      String? backupJson;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        backupJson = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        final f = File(file.path!);
        if (await f.exists()) {
          backupJson = await f.readAsString();
        }
      }
      if (backupJson == null || backupJson.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read backup file')),
          );
        }
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Settings'),
          content: const Text(
            'This will replace your current settings (including backend URL) with the backup. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() {
        _isRestoreInProgress = true;
        _errorMessage = null;
      });

      final settings = context.read<SettingsModel>();
      final permissionsNeeded =
          settings.checkPermissionsNeededFromBackupContent(backupJson);
      await _promptPermissionsBeforeRestore(permissionsNeeded);
      if (!mounted) return;

      final success =
          await settings.restoreSettingsFromJsonString(backupJson);
      if (!mounted) return;

      if (success) {
        try {
          final rootContext = context;
          await showDialog<void>(
            context: rootContext,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Settings Restored'),
              content: const Text(
                'Settings have been restored from backup. '
                'Tap Restart to apply changes, then log in again.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await Future.delayed(const Duration(milliseconds: 400));
                    if (rootContext.mounted) {
                      Phoenix.rebirth(rootContext);
                    }
                  },
                  child: const Text('Restart'),
                ),
              ],
            ),
          );
        } catch (e) {
          debugPrint('[LoginRestore] Restore success dialog error: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Settings restored. Restart the app to apply, then log in.',
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to restore settings')),
        );
      }
    } catch (e) {
      debugPrint('[LoginRestore] Restore flow error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore failed')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoreInProgress = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Username and password are required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settings = context.read<SettingsModel>();
      final client = BackendClient(baseUrl: settings.backendUrl);

      // Login and get tokens
      final response = await client.login(username, password);
      final tokens = AuthTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      );

      if (!mounted) return;

      // Set auth state and store tokens
      await settings.setAuthState(true, response.user['username'], tokens);

      // Set access token on client
      client.setAccessToken(tokens.accessToken);

      // Fetch and apply synced preferences
      try {
        final prefs = await client.fetchPreferences();
        await settings.applySyncedPreferences(prefs);
      } catch (e) {
        debugPrint('Failed to fetch preferences: $e');
        // Don't fail login if preference sync fails
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Login failed: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        automaticallyImplyLeading: false, // Remove back button
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Step 2 of 2: Login',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _isRestoreInProgress ? null : _handleRestoreFromBackup,
              icon: const Icon(Icons.restore),
              label: const Text('Restore settings from backup'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
              autofocus: true,
              onSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
              obscureText: true,
              onSubmitted: (_) => _handleLogin(),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}
