import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/screens/login_screen.dart';
import 'src/screens/main_screen.dart';
import 'src/screens/setup_screen.dart';
import 'src/services/app_lock_model.dart';
import 'src/services/app_state.dart';
import 'src/services/background_task.dart';
import 'src/services/discover_state.dart';
import 'src/services/notification_service.dart';
import 'src/services/settings_model.dart';
import 'src/services/update_service.dart';
import 'src/theme/app_theme.dart';
import 'src/widgets/app_lock_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init(
    onNotificationResponse: (response) {
      final payload = response.payload;
      if (payload == 'update_available' || payload == 'ready_to_install') {
        UpdateService.getInstance().then((s) => s.handleNotificationTap(payload));
      }
    },
  );
  await initializeBackgroundTasks();

  runApp(
    Phoenix(
      child: const _AppRoot(),
    ),
  );
}

/// Loads settings and builds the provider tree. Rebuilt on Phoenix.rebirth() so
/// restore gets a fresh load from storage.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  SettingsModel? _settings;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _runUpdateCheckAndBackendNotice() async {
    if (!mounted) return;
    try {
      final updateService = await UpdateService.getInstance();
      await updateService.saveCurrentVersionToPrefs();
      if (updateService.hasPendingUpdate) {
        final pending = updateService.getPendingUpdate();
        if (pending != null) {
          await NotificationService.instance.showUpdateAvailable(
            versionName: pending.versionName,
            changelog: pending.changelog,
          );
        }
      } else {
        final pending = updateService.getPendingUpdate();
        if (pending != null) {
          updateService.clearPendingUpdate();
        }
        await updateService.checkAndNotifyUpdate(ignoreSkipped: false);
      }
      if (!mounted) return;
      if (updateService.shouldShowBackendUpdateNotice) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backend update'),
            content: const Text(
              'You may need to run updates against the backend infrastructure to keep everything working.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) updateService.markBackendUpdateNoticeShown();
      }
    } catch (e) {
      debugPrint('[AppRoot] Update check error: $e');
    }
  }

  Future<void> _load() async {
    try {
      final settingsModel = SettingsModel();
      await settingsModel.loadSettings();
      if (mounted) {
        setState(() {
          _settings = settingsModel;
          _loadError = null;
        });
        final prefs = await SharedPreferences.getInstance();
        if (!prefs.containsKey('notification_permission_requested')) {
          await NotificationService.instance.requestNotificationPermission();
          await prefs.setBool('notification_permission_requested', true);
        }
        final folders = await settingsModel.getScheduledFolders();
        if (folders.any((f) => f.enabled)) {
          scheduleFolderScanTask().catchError((e) {
            debugPrint('[AppRoot] Error scheduling folder scan: $e');
          });
        }
        if (mounted) _runUpdateCheckAndBackendNotice();
      }
    } catch (e, stackTrace) {
      debugPrint('[AppRoot] Error loading settings: $e');
      debugPrint('[AppRoot] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return MaterialApp(
        theme: appDarkTheme,
        darkTheme: appDarkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load settings: $_loadError'),
            ),
          ),
        ),
      );
    }
    if (_settings == null) {
      return MaterialApp(
        theme: appDarkTheme,
        darkTheme: appDarkTheme,
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsModel>.value(value: _settings!),
        ChangeNotifierProvider<AppLockModel>(create: (_) => AppLockModel()),
        ChangeNotifierProxyProvider<SettingsModel, AppState>(
          create: (context) => AppState(_settings!),
          update: (context, settings, previous) =>
              previous ?? AppState(settings),
        ),
        ChangeNotifierProxyProvider<AppState, DiscoverState>(
          create: (_) => DiscoverState(),
          update: (_, appState, previous) {
            final state = previous ?? DiscoverState();
            if (appState.settings.isConfigured &&
                appState.settings.isAuthenticated) {
              state.updateClient(appState.backendClient);
            }
            return state;
          },
        ),
      ],
      child: const AppLockGate(child: SzuruCompanionApp()),
    );
  }
}

class SzuruCompanionApp extends StatelessWidget {
  const SzuruCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();

    // Determine initial route based on auth state
    String initialRoute = '/';
    if (settings.backendUrl.isEmpty) {
      initialRoute = '/setup';
    } else if (!settings.isAuthenticated) {
      initialRoute = '/login';
    }

    return MaterialApp(
      title: 'SzuruCompanion',
      debugShowCheckedModeBanner: false,
      theme: appDarkTheme,
      darkTheme: appDarkTheme,
      themeMode: ThemeMode.dark,
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const MainScreen(),
        '/setup': (context) => const SetupScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

