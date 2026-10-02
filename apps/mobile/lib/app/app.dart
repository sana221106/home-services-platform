import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'localization/app_localizations.dart';
import 'localization/locale_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_provider.dart';

/// Root widget.
///
/// Everything above this line is framework wiring; the only app-level decision
/// here is that appearance is a user setting rather than a build constant.
class HomeServicesApp extends ConsumerWidget {
  const HomeServicesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeModeState themeState = ref.watch(themeModeProvider);
    final AppLocaleState localeState = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Home Services',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeState.materialThemeMode,
      themeAnimationDuration: const Duration(milliseconds: 220),
      // A null locale means the customer has not chosen one, so the device
      // decides. Arabic is the source locale, so Material's own strings come
      // from the Arabic delegates rather than English.
      locale: localeState.locale,
      localeResolutionCallback: (Locale? device, Iterable<Locale> supported) =>
          resolveAppLocale(device, supported),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: appSupportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
