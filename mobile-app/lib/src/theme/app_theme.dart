import 'package:flutter/material.dart';

/// Styling-aligned palette: soft black with warm red accent.
class AppColors {
  AppColors._();

  static const Color bg = Color(0xFF1C1917);
  static const Color bgCard = Color(0xFF252220);
  static const Color border = Color(0xFF3D3632);
  static const Color text = Color(0xFFE8E2DC);
  static const Color textMuted = Color(0xFFA39D93);
  static const Color accent = Color(0xFFC41E3A);
  static const Color accentHover = Color(0xFFE53E5A);
  static const Color green = Color(0xFF4ADE80);
  static const Color red = Color(0xFFF87171);
  static const Color yellow = Color(0xFFFACC15);
  static const Color orange = Color(0xFFFB923C);
  static const Color purple = Color(0xFFC4B5FD);
}

/// Status colors for job badges and indicators.
class AppStatusColors {
  AppStatusColors._();

  static Color forStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppColors.yellow;
      case 'downloading':
      case 'tagging':
      case 'uploading':
        return AppColors.accent;
      case 'completed':
        return AppColors.green;
      case 'merged':
        return AppColors.purple;
      case 'failed':
      case 'stopped':
        return AppColors.red;
      case 'paused':
        return AppColors.yellow;
      default:
        return AppColors.textMuted;
    }
  }
}

ThemeData get appDarkTheme {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentHover,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.textMuted,
    onSecondary: AppColors.bg,
    surface: AppColors.bgCard,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.textMuted,
    outline: AppColors.border,
    error: AppColors.red,
    onError: Colors.white,
    surfaceContainerHighest: AppColors.bgCard,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgCard,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      color: AppColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      hintStyle: const TextStyle(color: AppColors.textMuted),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(AppColors.bgCard),
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 8)),
      ),
      textStyle: const TextStyle(color: AppColors.text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(AppColors.bgCard),
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 4)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bgCard,
      indicatorColor: AppColors.accent.withOpacity(0.2),
      iconTheme: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return const IconThemeData(color: AppColors.accent);
        }
        return const IconThemeData(color: AppColors.textMuted);
      }),
      labelTextStyle: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return const TextStyle(color: AppColors.accent);
        }
        return const TextStyle(color: AppColors.textMuted);
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bgCard,
      contentTextStyle: const TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.border,
      circularTrackColor: AppColors.border,
    ),
  );
}
