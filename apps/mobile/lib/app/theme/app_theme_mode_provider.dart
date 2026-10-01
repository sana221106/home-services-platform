import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap/providers.dart';

/// User-selectable appearance (§44). The app ships Light and Dark themes with
/// no hard-coded colours, so this only chooses which palette to build.
enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  String get storageKey => switch (this) {
    AppThemeMode.system => 'theme.system',
    AppThemeMode.light => 'theme.light',
    AppThemeMode.dark => 'theme.dark',
  };

  static AppThemeMode fromStorage(String? raw) {
    for (final mode in AppThemeMode.values) {
      if (mode.storageKey == raw) return mode;
    }
    return AppThemeMode.system;
  }
}

@immutable
class ThemeModeState {
  const ThemeModeState({required this.mode});

  final AppThemeMode mode;

  ThemeMode get materialThemeMode => switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  ThemeModeState copyWith({AppThemeMode? mode}) =>
      ThemeModeState(mode: mode ?? this.mode);

  @override
  bool operator ==(Object other) =>
      other is ThemeModeState && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

/// Owns the appearance choice and persists it.
class ThemeModeController extends Notifier<ThemeModeState> {
  static const String storageKey = 'theme_mode';

  @override
  ThemeModeState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return ThemeModeState(
      mode: AppThemeModeX.fromStorage(prefs.getString(storageKey)),
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode);
    await ref
        .read(sharedPreferencesProvider)
        .setString(storageKey, mode.storageKey);
  }
}

final NotifierProvider<ThemeModeController, ThemeModeState> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeModeState>(
      ThemeModeController.new,
      name: 'themeMode',
    );
