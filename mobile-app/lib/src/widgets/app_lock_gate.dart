import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/app_lock_screen.dart';
import '../services/app_lock_model.dart';
import '../theme/app_theme.dart';

/// When app lock is enabled on Android, shows [AppLockScreen] until the user
/// passes system auth; on resume from background, requires auth again.
/// On Darwin/Windows the gate is a no-op (child shown regardless).
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  AppLifecycleState? _lastLifecycleState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final model = context.read<AppLockModel>();
    if (model.isEnabled &&
        _lastLifecycleState == AppLifecycleState.resumed &&
        state == AppLifecycleState.paused) {
      setState(() => _unlocked = false);
    }
    _lastLifecycleState = state;
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppLockModel>();
    if (!model.isLoaded) {
      return MaterialApp(
        theme: appDarkTheme,
        darkTheme: appDarkTheme,
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid && model.isEnabled && !_unlocked) {
      return MaterialApp(
        theme: appDarkTheme,
        darkTheme: appDarkTheme,
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: AppLockScreen(
          onUnlocked: () => setState(() => _unlocked = true),
        ),
      );
    }
    return widget.child;
  }
}
