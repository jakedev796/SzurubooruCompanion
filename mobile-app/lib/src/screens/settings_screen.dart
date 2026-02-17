import 'dart:async';
import 'dart:convert';

import 'package:battery_optimization_helper/battery_optimization_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth.dart';
import '../services/backend_client.dart';
import '../services/background_task.dart';
import '../services/companion_foreground_service.dart';
import '../services/floating_bubble_service.dart';
import '../services/settings_model.dart';
import '../services/storage_permission.dart';
import '../theme/app_theme.dart';
import '../widgets/settings/app_features_card.dart';
import '../widgets/settings/backup_restore_card.dart';
import '../widgets/settings/backend_settings_card.dart';
import '../widgets/settings/folder_settings_card.dart';
import '../widgets/settings/share_settings_card.dart';

/// Settings screen for the Szuru Companion app
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final GlobalKey<FormState> _settingsFormKey = GlobalKey<FormState>();
  final TextEditingController _backendUrlController = TextEditingController();
  final TextEditingController _defaultTagsController = TextEditingController();
  final FocusNode _backendUrlFocusNode = FocusNode();
  final FocusNode _defaultTagsFocusNode = FocusNode();

  String _selectedSafety = 'unsafe';
  bool _useBackgroundService = true;
  bool _skipTagging = false;
  bool _notifyOnFolderSync = false;
  bool _deleteMediaAfterSync = false;
  bool _showPersistentNotification = true;
  bool _showFloatingBubble = false;
  int _folderSyncIntervalSeconds = 900;
  bool _isSyncingFolders = false;
  bool _isRestoreInProgress = false;
  bool _settingsInitialized = false;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _backendUrlFocusNode.addListener(_handleBackendUrlFocusChange);
    _defaultTagsFocusNode.addListener(_handleDefaultTagsFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSettingsFields();
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _backendUrlController.dispose();
    _defaultTagsController.dispose();
    _backendUrlFocusNode.dispose();
    _defaultTagsFocusNode.dispose();
    super.dispose();
  }

  void _handleBackendUrlFocusChange() {
    if (!_backendUrlFocusNode.hasFocus) {
      _autoSaveSettings(validate: true);
    }
  }

  void _handleDefaultTagsFocusChange() {
    if (!_defaultTagsFocusNode.hasFocus) {
      _autoSaveSettings(validate: false);
    }
  }

  void _syncSettingsFields() {
    if (!mounted) return;
    final settings = context.read<SettingsModel>();
    setState(() {
      if (!_settingsInitialized) {
        _backendUrlController.text = settings.backendUrl;
        _defaultTagsController.text = settings.defaultTags;
        _settingsInitialized = true;
      }
      _selectedSafety = settings.defaultSafety;
      _skipTagging = settings.skipTagging;
      _useBackgroundService = settings.useBackgroundService;
      _notifyOnFolderSync = settings.notifyOnFolderSync;
      _deleteMediaAfterSync = settings.deleteMediaAfterSync;
      _showPersistentNotification = settings.showPersistentNotification;
      _showFloatingBubble = settings.showFloatingBubble;
      _folderSyncIntervalSeconds = settings.folderSyncIntervalSeconds;
    });
  }

  Future<void> _autoSaveSettings({bool validate = true}) async {
    if (validate && _settingsFormKey.currentState?.validate() != true) return;
    if (!mounted) return;

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      await _saveSettingsInternal(validate: validate, checkPermissions: false);
    });
  }

  Future<void> _saveSettings() async {
    _autoSaveTimer?.cancel();
    await _saveSettingsInternal(validate: true, checkPermissions: true);
  }

  Future<void> _saveSettingsInternal({bool validate = true, bool checkPermissions = true}) async {
    try {
      if (validate && _settingsFormKey.currentState?.validate() != true) return;
      if (!mounted) return;

      final settings = context.read<SettingsModel>();
      final folders = await settings.getScheduledFolders();
      final hasFoldersEnabled = folders.isNotEmpty && folders.any((f) => f.enabled == true);

      // Check storage permission if folders are enabled (skip for auto-save)
      if (checkPermissions && hasFoldersEnabled) {
        final hasPermission = await StoragePermissionService.hasStoragePermission();
        if (!mounted) return;
        if (!hasPermission) {
          final shouldRequest = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Storage Permission Required'),
              content: const Text(
                'You have enabled folders for background sync, but the app doesn\'t have '
                '"All files access" permission.\n\n'
                'Background folder sync will not work without this permission.\n\n'
                'Would you like to grant it now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Grant Permission'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (shouldRequest == true) {
            await StoragePermissionService.requestStoragePermission();
            await Future.delayed(const Duration(milliseconds: 500));
            if (!mounted) return;
          }
        }
      }

      // Handle floating bubble permission before saving (skip for auto-save)
      if (checkPermissions && _showFloatingBubble) {
        final hasOverlay = await canDrawOverlays();
        if (!mounted) return;
        if (!hasOverlay) {
          final shouldRequest = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Overlay Permission Required'),
              content: const Text(
                'The floating bubble needs "Display over other apps" permission '
                'to appear on top of other apps.\n\n'
                'Would you like to grant it now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Grant Permission'),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (shouldRequest == true) {
            await requestOverlayPermission();
            await Future.delayed(const Duration(milliseconds: 800));
            if (!mounted) return;
            final granted = await canDrawOverlays();
            if (mounted) {
              if (granted) {
                setState(() { _showFloatingBubble = true; });
                _showSnackBar('Overlay permission granted - floating bubble enabled');
                final folderSyncEnabledNow = hasFoldersEnabled && _showPersistentNotification;
                if (folderSyncEnabledNow) {
                  await startCompanionForegroundService(
                    folderSyncEnabled: true,
                    bubbleEnabled: true,
                    statusBody: buildCompanionNotificationBody(
                      folderSyncOn: true,
                      bubbleOn: true,
                    ),
                  );
                } else {
                  await startCompanionForegroundService(
                    folderSyncEnabled: false,
                    bubbleEnabled: true,
                    statusBody: buildCompanionNotificationBody(bubbleOn: true),
                  );
                }
              } else {
                setState(() { _showFloatingBubble = false; });
                _showSnackBar('Overlay permission not granted - bubble disabled');
              }
            }
          } else if (mounted) {
            setState(() { _showFloatingBubble = false; });
          }
        }
      }

      if (!mounted) return;
      await settings.saveSettings(
        backendUrl: _backendUrlController.text.trim(),
        useBackgroundService: _useBackgroundService,
        defaultTags: _defaultTagsController.text,
        defaultSafety: _selectedSafety,
        skipTagging: _skipTagging,
        notifyOnFolderSync: _notifyOnFolderSync,
        deleteMediaAfterSync: _deleteMediaAfterSync,
        showPersistentNotification: _showPersistentNotification,
        showFloatingBubble: _showFloatingBubble,
        folderSyncIntervalSeconds: _folderSyncIntervalSeconds,
      );
      if (!mounted) return;

      // Sync settings to backend if authenticated
      if (settings.isAuthenticated) {
        try {
          final client = BackendClient(baseUrl: settings.backendUrl);
          final prefs = await SharedPreferences.getInstance();
          final authJson = prefs.getString('auth_tokens');
          if (authJson != null) {
            final tokens = AuthTokens.fromJson(jsonDecode(authJson));
            client.setAccessToken(tokens.accessToken);
            await client.savePreferences(await settings.getSyncablePreferences());
            debugPrint('[Settings] Settings synced to backend');
          }
        } catch (e) {
          debugPrint('[Settings] Failed to sync settings to backend: $e');
          // Don't fail the save if backend sync fails
        }
      }

      final folderSyncEnabled = hasFoldersEnabled && _showPersistentNotification;
      if (folderSyncEnabled) {
        await startCompanionForegroundService(
          folderSyncEnabled: true,
          bubbleEnabled: _showFloatingBubble && folderSyncEnabled,
          statusBody: buildCompanionNotificationBody(
            folderSyncOn: true,
            bubbleOn: _showFloatingBubble && folderSyncEnabled,
          ),
        );
        if (!mounted) return;
        await stopFloatingBubbleService();
      } else {
        if (_showFloatingBubble) {
          final hasOverlay = await canDrawOverlays();
          if (hasOverlay) {
            await startCompanionForegroundService(
              folderSyncEnabled: false,
              bubbleEnabled: true,
              statusBody: buildCompanionNotificationBody(bubbleOn: true),
            );
          }
        } else {
          await stopCompanionForegroundService();
        }
        if (!mounted) return;
        await stopFloatingBubbleService();
      }
      if (!mounted) return;

      if (hasFoldersEnabled) {
        try {
          await scheduleFolderScanTask();
        } catch (e) {
          debugPrint('[Settings] Error scheduling folder scan in save: $e');
        }
      } else {
        try {
          await cancelFolderScanTask();
        } catch (e) {
          debugPrint('[Settings] Error cancelling folder scan in save: $e');
        }
      }
      if (!mounted) return;

      if (_showFloatingBubble) {
        await _applyBubbleAndNotificationFromState();
      }
      if (!mounted) return;

      _syncSettingsFields();
      if (mounted) _showSnackBar('Settings saved');
    } catch (e) {
      debugPrint('[Settings] Save error: $e');
      if (mounted) _showSnackBar('Error saving settings: ${e.toString()}');
    }
  }

  /// Apply bubble/notification state using the single companion foreground service.
  /// Do not start the standalone FloatingBubbleService or we get a duplicate bubble.
  Future<void> _applyBubbleAndNotificationFromState() async {
    if (!_showFloatingBubble) {
      await stopFloatingBubbleService();
      return;
    }

    final hasOverlay = await canDrawOverlays();
    if (!hasOverlay) {
      if (mounted) _showSnackBar('Floating bubble disabled: overlay permission not granted');
      return;
    }

    final folders = await context.read<SettingsModel>().getScheduledFolders();
    if (!mounted) return;
    final hasFoldersEnabled = folders.any((f) => f.enabled == true);
    final folderSyncEnabled = hasFoldersEnabled && _showPersistentNotification;
    if (folderSyncEnabled) {
      await startCompanionForegroundService(
        folderSyncEnabled: true,
        bubbleEnabled: true,
        statusBody: buildCompanionNotificationBody(
          folderSyncOn: true,
          bubbleOn: true,
        ),
      );
    } else {
      await startCompanionForegroundService(
        folderSyncEnabled: false,
        bubbleEnabled: true,
        statusBody: buildCompanionNotificationBody(bubbleOn: true),
      );
    }
    await stopFloatingBubbleService();
  }

  Future<void> _runFolderSync() async {
    if (_isSyncingFolders) return;
    if (!mounted) return;

    setState(() => _isSyncingFolders = true);

    try {
      final outcome = await triggerManualScanAll();
      if (mounted) {
        if (outcome.uploaded > 0) {
          _showSnackBar('Folder sync completed: ${outcome.uploaded} files uploaded');
        } else {
          _showSnackBar('Folder sync completed: no new files found');
        }
      }
    } catch (e) {
      debugPrint('[Settings] Folder sync error: $e');
      if (mounted) {
        _showSnackBar('Folder sync failed: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingFolders = false);
      }
    }
  }

  Future<void> _promptPermissionsBeforeRestore(Map<String, bool> permissionsNeeded) async {
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
          if (!mounted) return;
          final granted = await canDrawOverlays();
          if (granted && mounted) {
            _showSnackBar('Overlay permission granted');
          }
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
          if (!mounted) return;
          final granted = await StoragePermissionService.hasStoragePermission();
          if (granted && mounted) {
            _showSnackBar('Storage permission granted');
          }
        }
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _settingsFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BackendSettingsCard(
              backendUrlController: _backendUrlController,
              backendUrlFocusNode: _backendUrlFocusNode,
            ),
            ShareSettingsCard(
              useBackgroundService: _useBackgroundService,
              defaultTagsController: _defaultTagsController,
              defaultTagsFocusNode: _defaultTagsFocusNode,
              selectedSafety: _selectedSafety,
              skipTagging: _skipTagging,
              onUseBackgroundServiceChanged: (value) => setState(() => _useBackgroundService = value),
              onSelectedSafetyChanged: (value) => setState(() => _selectedSafety = value),
              onSkipTaggingChanged: (value) => setState(() => _skipTagging = value),
              onAutoSave: () => _autoSaveSettings(validate: false),
            ),
            FolderSettingsCard(
              isSyncingFolders: _isSyncingFolders,
              notifyOnFolderSync: _notifyOnFolderSync,
              deleteMediaAfterSync: _deleteMediaAfterSync,
              showPersistentNotification: _showPersistentNotification,
              folderSyncIntervalSeconds: _folderSyncIntervalSeconds,
              onSyncNow: _runFolderSync,
              onNotifyOnFolderSyncChanged: (value) => setState(() => _notifyOnFolderSync = value),
              onDeleteMediaAfterSyncChanged: (value) => setState(() => _deleteMediaAfterSync = value),
              onShowPersistentNotificationChanged: (value) => setState(() => _showPersistentNotification = value),
              onFolderSyncIntervalChanged: (value) => setState(() => _folderSyncIntervalSeconds = value),
              onAutoSave: () => _autoSaveSettings(validate: false),
            ),
            AppFeaturesCard(
              showFloatingBubble: _showFloatingBubble,
              onShowFloatingBubbleChanged: (value) async {
                setState(() => _showFloatingBubble = value);
                await _saveSettingsInternal(validate: false, checkPermissions: true);
                if (mounted && _showFloatingBubble) {
                  await _applyBubbleAndNotificationFromState();
                }
              },
            ),
            BackupRestoreCard(
              isRestoreInProgress: _isRestoreInProgress,
              onShowSnackBar: _showSnackBar,
              onRestore: (backupJson) async {
                final permissionsNeeded = context.read<SettingsModel>().checkPermissionsNeededFromBackupContent(backupJson);
                if (!mounted) return false;
                setState(() => _isRestoreInProgress = true);
                try {
                  await _promptPermissionsBeforeRestore(permissionsNeeded);
                  if (!mounted) return false;
                  final success = await context.read<SettingsModel>().restoreSettingsFromJsonString(backupJson);
                  return success;
                } finally {
                  if (mounted) setState(() => _isRestoreInProgress = false);
                }
              },
            ),

            // Save Settings Button
            ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Save settings', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            // App Health Section
            const Text(
              'App health',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const AppHealthSection(),
          ],
        ),
      ),
    );
  }
}

/// Widget showing app health status (permissions, battery optimization, etc.)
class AppHealthSection extends StatefulWidget {
  const AppHealthSection({super.key});

  @override
  State<AppHealthSection> createState() => _AppHealthSectionState();
}

class _AppHealthSectionState extends State<AppHealthSection> {
  BatteryRestrictionSnapshot? _snapshot;
  bool _loading = true;
  bool _hasStoragePermission = false;
  bool _hasOverlayPermission = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsModel>();
    _load(settings);
  }

  Future<void> _load(SettingsModel settings, {bool afterReturningFromSettings = false}) async {
    if (afterReturningFromSettings) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
    }
    final snapshot = await BatteryOptimizationHelper.getBatteryRestrictionSnapshot();
    final hasStorage = await StoragePermissionService.hasStoragePermission();
    final hasOverlay = await canDrawOverlays();
    if (mounted) {
      setState(() {
        _snapshot = snapshot;
        _hasStoragePermission = hasStorage;
        _hasOverlayPermission = hasOverlay;
        _loading = false;
      });
    }
  }

  Future<void> _fixBatteryOptimization() async {
    final outcome = await BatteryOptimizationHelper.ensureOptimizationDisabledDetailed(
      openSettingsIfDirectRequestNotPossible: true,
    );
    if (!mounted) return;
    final message = switch (outcome.status) {
      OptimizationOutcomeStatus.alreadyDisabled => 'Already allowed.',
      OptimizationOutcomeStatus.disabledAfterPrompt => 'Battery optimization disabled.',
      OptimizationOutcomeStatus.settingsOpened => 'Please disable battery optimization for this app.',
      OptimizationOutcomeStatus.unsupported => 'Not available on this device.',
      OptimizationOutcomeStatus.failed => 'Could not open settings.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
    if (mounted) _load(context.read<SettingsModel>(), afterReturningFromSettings: true);
  }

  Future<void> _requestStoragePermission() async {
    final hasPermission = await StoragePermissionService.hasStoragePermission();
    if (hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission already granted'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // Show explanation dialog first
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage Permission Required'),
        content: const Text(
          'SzuruCompanion needs "All files access" permission to sync folders in the background.\n\n'
          'This allows the app to automatically upload media files even when the app is closed.\n\n'
          'You\'ll be taken to Android settings where you need to toggle ON the permission for SzuruCompanion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );

    if (shouldRequest == true && mounted) {
      try {
        await StoragePermissionService.requestStoragePermission();
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _load(context.read<SettingsModel>(), afterReturningFromSettings: true);
      } catch (e) {
        debugPrint('[AppHealth] _requestStoragePermission error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not complete storage permission flow'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            ),
          );
        }
      }
    }
  }

  Future<void> _requestOverlayPermission() async {
    final hasPermission = await canDrawOverlays();
    if (hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Overlay permission already granted'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Overlay Permission Required'),
        content: const Text(
          'The floating bubble needs "Display over other apps" permission.\n\n'
          'This allows the bubble overlay to appear on top of other apps for quick sharing.\n\n'
          'You\'ll be taken to Android settings where you need to toggle ON the permission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );

    if (shouldRequest == true && mounted) {
      try {
        await requestOverlayPermission();
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _load(context.read<SettingsModel>(), afterReturningFromSettings: true);
      } catch (e) {
        debugPrint('[AppHealth] _requestOverlayPermission error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not complete overlay permission flow'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Column(
      children: [
        // Storage Permission
        Card(
          child: ListTile(
            leading: Icon(
              _hasStoragePermission ? Icons.check_circle : Icons.cancel,
              color: _hasStoragePermission ? AppColors.green : AppColors.red,
            ),
            title: const Text('Storage permission'),
            subtitle: Text(
              _hasStoragePermission
                  ? 'All files access granted – folder sync enabled.'
                  : 'Not granted – folder sync will not work.',
            ),
            trailing: _hasStoragePermission
                ? null
                : TextButton(
                    onPressed: _requestStoragePermission,
                    child: const Text('Grant'),
                  ),
            onTap: _hasStoragePermission ? null : _requestStoragePermission,
          ),
        ),
        const SizedBox(height: 8),
        // Overlay Permission
        Card(
          child: ListTile(
            leading: Icon(
              _hasOverlayPermission ? Icons.check_circle : Icons.cancel,
              color: _hasOverlayPermission ? AppColors.green : AppColors.red,
            ),
            title: const Text('Overlay permission'),
            subtitle: Text(
              _hasOverlayPermission
                  ? 'Display over other apps granted – floating bubble is available.'
                  : 'Not granted – floating bubble will not work.',
            ),
            trailing: _hasOverlayPermission
                ? null
                : TextButton(
                    onPressed: _requestOverlayPermission,
                    child: const Text('Grant'),
                  ),
            onTap: _hasOverlayPermission ? null : _requestOverlayPermission,
          ),
        ),
        const SizedBox(height: 8),
        // Battery Optimization
        if (_snapshot != null && _snapshot!.isSupported)
          Card(
            child: ListTile(
              leading: Icon(
                _snapshot!.isBatteryOptimizationEnabled ? Icons.cancel : Icons.check_circle,
                color: _snapshot!.isBatteryOptimizationEnabled ? AppColors.red : AppColors.green,
              ),
              title: const Text('Battery optimization'),
              subtitle: Text(
                _snapshot!.isBatteryOptimizationEnabled
                    ? 'On – folder sync may not run reliably.'
                    : 'Off – folder sync can run reliably.',
              ),
              trailing: _snapshot!.isBatteryOptimizationEnabled
                  ? TextButton(
                      onPressed: _fixBatteryOptimization,
                      child: const Text('Fix'),
                    )
                  : null,
              onTap: _snapshot!.isBatteryOptimizationEnabled ? _fixBatteryOptimization : null,
            ),
          ),
      ],
    );
  }
}
