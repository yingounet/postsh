import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_settings.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';

class PostShApp extends ConsumerWidget {
  const PostShApp({super.key});

  static ThemeData _themeFor(AppSettings s, Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppSettings.seedColorFromKey(s.seedColorKey),
      brightness: brightness,
    );
    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontSizeFactor: s.fontScale),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull ?? const AppSettings();

    return MaterialApp(
      title: 'PostSH',
      theme: _themeFor(settings, Brightness.light),
      darkTheme: _themeFor(settings, Brightness.dark),
      themeMode: settings.themeMode,
      home: const HomeScreen(),
    );
  }
}
