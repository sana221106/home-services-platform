import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap/app_bootstrap.dart';

/// User-selectable language (§22, §38). `system` defers to the device, which is
/// the default so the app opens in the customer's own language without being
/// asked.
enum AppLanguage { system, arabic, english }

extension AppLanguageX on AppLanguage {
  String get storageKey => switch (this) {
    AppLanguage.system => 'language.system',
    AppLanguage.arabic => 'language.ar',
    AppLanguage.english => 'language.en',
  };

  /// The backend `preferred_language` value, or null for `system` which leaves
  /// the stored preference untouched.
  String? get backendCode => switch (this) {
    AppLanguage.system => null,
    AppLanguage.arabic => 'ar',
    AppLanguage.english => 'en',
  };

  static AppLanguage fromStorage(String? raw) {
    for (final AppLanguage value in AppLanguage.values) {
      if (value.storageKey == raw) return value;
    }
    return AppLanguage.system;
  }

  static AppLanguage fromBackendCode(String? code) => switch (code) {
    'ar' => AppLanguage.arabic,
    'en' => AppLanguage.english,
    _ => AppLanguage.system,
  };
}

@immutable
class AppLocaleState {
  const AppLocaleState({required this.language});

  final AppLanguage language;

  /// Null hands control back to the device via the router's locale resolution.
  Locale? get locale => switch (language) {
    AppLanguage.system => null,
    AppLanguage.arabic => const Locale('ar'),
    AppLanguage.english => const Locale('en'),
  };

  AppLocaleState copyWith({AppLanguage? language}) =>
      AppLocaleState(language: language ?? this.language);

  @override
  bool operator ==(Object other) =>
      other is AppLocaleState && other.language == language;

  @override
  int get hashCode => language.hashCode;
}

/// Owns the language choice and persists it.
class AppLocaleController extends Notifier<AppLocaleState> {
  static const String storageKey = 'app_language';

  @override
  AppLocaleState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppLocaleState(
      language: AppLanguageX.fromStorage(prefs.getString(storageKey)),
    );
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (language == state.language) return;
    state = state.copyWith(language: language);
    await ref
        .read(sharedPreferencesProvider)
        .setString(storageKey, language.storageKey);
  }
}

final NotifierProvider<AppLocaleController, AppLocaleState> localeProvider =
    NotifierProvider<AppLocaleController, AppLocaleState>(
      AppLocaleController.new,
      name: 'locale',
    );
