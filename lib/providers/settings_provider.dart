import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../services/storage_service.dart';

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final themeModeRaw =
        await StorageService.getConfig(AppSettings.storageThemeMode);
    final seedColorRaw =
        await StorageService.getConfig(AppSettings.storageSeedColor);
    final fontScaleRaw =
        await StorageService.getConfig(AppSettings.storageFontScale);
    final usePtyRaw =
        await StorageService.getConfig(AppSettings.storageUsePty);

    return AppSettings(
      themeMode: AppSettings.themeModeFromString(themeModeRaw),
      seedColorKey: seedColorRaw ?? 'blue',
      fontScale: AppSettings.fontScaleFromString(fontScaleRaw),
      usePty: usePtyRaw == 'true',
    );
  }

  Future<void> updateThemeMode(ThemeMode value) async {
    final current = state.valueOrNull ?? const AppSettings();
    await StorageService.setConfig(
      AppSettings.storageThemeMode,
      AppSettings.themeModeToString(value),
    );
    state = AsyncData(current.copyWith(themeMode: value));
  }

  Future<void> updateSeedColor(String value) async {
    final current = state.valueOrNull ?? const AppSettings();
    await StorageService.setConfig(AppSettings.storageSeedColor, value);
    state = AsyncData(current.copyWith(seedColorKey: value));
  }

  Future<void> updateFontScale(double value) async {
    final current = state.valueOrNull ?? const AppSettings();
    await StorageService.setConfig(
      AppSettings.storageFontScale,
      value.toString(),
    );
    state = AsyncData(current.copyWith(fontScale: value));
  }

  Future<void> updateUsePty(bool value) async {
    final current = state.valueOrNull ?? const AppSettings();
    await StorageService.setConfig(
      AppSettings.storageUsePty,
      value.toString(),
    );
    state = AsyncData(current.copyWith(usePty: value));
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
