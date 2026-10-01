import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// The locales this app ships. Arabic is the primary market, so it is listed
/// first and is the fallback for any device locale we do not recognise.
const List<Locale> appSupportedLocales = <Locale>[Locale('ar'), Locale('en')];

/// Resolves a device locale to a shipped locale.
///
/// Flutter's default would pick the first supported locale for anything
/// unrecognised. That happens to be Arabic here, but relying on list order is
/// accidental: this makes the fallback explicit and testable.
Locale resolveAppLocale(Locale? deviceLocale, Iterable<Locale> supported) {
  final List<Locale> locales = supported.toList(growable: false);
  if (locales.isEmpty) return const Locale('ar');

  final String? language = deviceLocale?.languageCode.toLowerCase();
  if (language == null) return locales.first;

  for (final locale in locales) {
    if (locale.languageCode.toLowerCase() == language) return locale;
  }
  return locales.first;
}

/// Shortcut so widgets read `context.l10n` instead of a long static lookup.
///
/// `l10n` throws when called above the app's `Localizations` scope, which is
/// the correct failure: a missing delegate is a wiring bug, not something to
/// paper over with empty strings.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
