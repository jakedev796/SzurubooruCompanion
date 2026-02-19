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
import '../theme/app_theme.dart';

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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),
                    // Hero image (mirrors setup screen)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: AppColors.border,
                            width: 1,
                          ),
                        ),
                        child: Image.asset(
                          'assets/images/reimu.jpg',
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Quote text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Text(
                            'Hello slacker,',
                            style: TextStyle(
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textMuted,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            'is it all right for you to slack around here?',
                            style: TextStyle(
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textMuted,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '— Reimu',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted.withOpacity(0.9),
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Card with login form
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Log in',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _isRestoreInProgress
                                    ? null
                                    : _handleRestoreFromBackup,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.textMuted,
                                  padding: const EdgeInsets.only(bottom: 12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(Icons.restore, size: 18),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Restore settings from backup'),
                                          Text(
                                            'Authentication details are not stored in backups.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textMuted
                                                  .withOpacity(0.8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextField(
                                controller: _usernameController,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                ),
                                enabled: !_isLoading,
                                autofocus: true,
                                onSubmitted: (_) => _handleLogin(),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _passwordController,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                ),
                                enabled: !_isLoading,
                                obscureText: true,
                                onSubmitted: (_) => _handleLogin(),
                              ),
                              const SizedBox(height: 16),
                              if (_errorMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: AppColors.red,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Text(
                                          'Log in',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
