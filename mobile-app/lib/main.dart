import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/screens/login_screen.dart';
import 'src/screens/main_screen.dart';
import 'src/screens/setup_screen.dart';
import 'src/services/app_state.dart';
import 'src/services/background_task.dart';
import 'src/services/notification_service.dart';
import 'src/services/sse_background_service.dart';
import 'src/services/settings_model.dart';
import 'src/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
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
        
        // Restart SSE service if foreground service should be running
        // This handles the case where the app process was killed and restarted
        // (e.g., when app was fully closed/swiped away)
        final hasFoldersEnabled = folders.any((f) => f.enabled);
        final shouldHaveForegroundService = hasFoldersEnabled || settingsModel.showFloatingBubble;
        if (shouldHaveForegroundService && settingsModel.isConfigured && settingsModel.canMakeApiCalls) {
          // Restart SSE service if it's not already running
          // The foreground service keeps the process alive, but if Android killed it,
          // we need to restart SSE when the app process comes back
          if (!SseBackgroundService.instance.isRunning) {
            SseBackgroundService.instance.start().catchError((e) {
              debugPrint('[AppRoot] Error restarting SSE service: $e');
            });
          }
        }
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
        ChangeNotifierProxyProvider<SettingsModel, AppState>(
          create: (context) => AppState(_settings!),
          update: (context, settings, previous) =>
              previous ?? AppState(settings),
        ),
      ],
      child: const SzuruCompanionApp(),
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

