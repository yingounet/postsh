import 'package:flutter/material.dart';

/// 应用设置：主题、字体、PTY 等。
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.seedColorKey = 'blue',
    this.fontScale = 1.0,
    this.usePty = false,
  });

  final ThemeMode themeMode;
  final String seedColorKey;
  final double fontScale;
  final bool usePty;

  static const String storageThemeMode = 'theme_mode';
  static const String storageSeedColor = 'seed_color';
  static const String storageFontScale = 'font_scale';
  static const String storageUsePty = 'use_pty';

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? seedColorKey,
    double? fontScale,
    bool? usePty,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColorKey: seedColorKey ?? this.seedColorKey,
      fontScale: fontScale ?? this.fontScale,
      usePty: usePty ?? this.usePty,
    );
  }

  static ThemeMode themeModeFromString(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String themeModeToString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static double fontScaleFromString(String? v) {
    final d = double.tryParse(v ?? '');
    if (d != null && d >= 0.8 && d <= 1.5) return d;
    return 1.0;
  }

  static Color seedColorFromKey(String key) {
    switch (key) {
      case 'green':
        return Colors.green;
      case 'purple':
        return Colors.purple;
      case 'orange':
        return Colors.orange;
      case 'blue':
      default:
        return Colors.blue;
    }
  }
}
