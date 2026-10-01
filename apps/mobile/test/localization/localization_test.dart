import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/app/localization/app_localizations.dart';

Map<String, dynamic> _arb(String name) {
  final file = File('lib/app/localization/arb/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Widget _wrap(Widget child, Locale locale) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('localization catalogue', () {
    test('Arabic is the declared source locale', () {
      expect(AppLocalizations.supportedLocales, contains(const Locale('ar')));
      expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
      expect(_arb('app_ar.arb')['@@locale'], 'ar');
    });

    test('English defines exactly the same keys as Arabic', () {
      final ar = _arb('app_ar.arb');
      final en = _arb('app_en.arb');
      Set<String> strip(Map<String, dynamic> m) =>
          m.keys.where((String k) => !k.startsWith('@')).toSet();

      expect(strip(en), strip(ar));
      expect(
        strip(ar).difference(strip(en)),
        isEmpty,
        reason: 'English must not be missing a key the Arabic app ships',
      );
    });

    test('no Arabic string leaks Latin words', () {
      // The phone hint is intentionally Latin digits/x placeholders.
      const allowlisted = <String>{'authPhoneHint'};
      final ar = _arb('app_ar.arb');
      final offenders = <String>[];

      ar.forEach((String key, Object? value) {
        if (key.startsWith('@') || value is! String) return;
        if (allowlisted.contains(key)) return;
        // Placeholder names such as {count} are not user-facing copy.
        final copy = value.replaceAll(RegExp(r'\{\w+\}'), '');
        if (RegExp(r'[A-Za-z]').hasMatch(copy)) {
          offenders.add('$key -> $value');
        }
      });

      expect(
        offenders,
        isEmpty,
        reason: 'corrupted mixed-script copy like "س ceilings" must not ship',
      );
    });

    test('no Arabic string contains non-Arabic CJK characters', () {
      final ar = _arb('app_ar.arb');
      final offenders = <String>[];
      ar.forEach((String key, Object? value) {
        if (key.startsWith('@') || value is! String) return;
        if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(value)) {
          offenders.add('$key -> $value');
        }
      });
      expect(offenders, isEmpty);
    });

    test('placeholders match across locales', () {
      final ar = _arb('app_ar.arb');
      final en = _arb('app_en.arb');
      final pattern = RegExp(r'\{(\w+)\}');

      ar.forEach((String key, Object? arValue) {
        if (key.startsWith('@') || arValue is! String) return;
        final enValue = en[key];
        expect(enValue, isA<String>(), reason: '$key missing in English');
        final arNames = pattern
            .allMatches(arValue)
            .map((Match m) => m.group(1))
            .toSet();
        final enNames = pattern
            .allMatches(enValue! as String)
            .map((Match m) => m.group(1))
            .toSet();
        expect(enNames, arNames, reason: 'placeholder mismatch in $key');
      });
    });
  });

  group('localized output', () {
    testWidgets('resolves Arabic strings with RTL direction', (
      WidgetTester tester,
    ) async {
      late AppLocalizations l10n;
      late TextDirection direction;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (BuildContext context) {
              l10n = context.l10n;
              direction = Directionality.of(context);
              return Text(l10n.appTitle);
            },
          ),
          const Locale('ar'),
        ),
      );

      expect(direction, TextDirection.rtl);
      expect(l10n.appTitle, 'خدمات المنزل');
      expect(l10n.commonRetry, 'إعادة المحاولة');
    });

    testWidgets('interpolates Arabic placeholders', (
      WidgetTester tester,
    ) async {
      late String rendered;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (BuildContext context) {
              rendered = context.l10n.homeGreeting('سارة');
              return const SizedBox.shrink();
            },
          ),
          const Locale('ar'),
        ),
      );
      expect(rendered, 'أهلاً، سارة');
    });

    testWidgets('resolves the locale explicitly rather than by list order', (
      WidgetTester tester,
    ) async {
      late AppLocalizations l10n;
      late TextDirection direction;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (BuildContext context) {
              l10n = context.l10n;
              direction = Directionality.of(context);
              return Text(l10n.appTitle);
            },
          ),
          const Locale('en'),
        ),
      );

      expect(direction, TextDirection.ltr);
      expect(l10n.commonRetry, 'Retry');
    });

    test('locale resolution is explicit', () {
      const supported = <Locale>[Locale('ar'), Locale('en')];

      expect(
        resolveAppLocale(const Locale('ar'), supported),
        const Locale('ar'),
      );
      expect(
        resolveAppLocale(const Locale('en'), supported),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(const Locale('en', 'GB'), supported),
        const Locale('en'),
      );
      // Anything unrecognised falls back to the primary market, not "whatever
      // happens to be first after a future reorder".
      expect(
        resolveAppLocale(const Locale('fr'), supported),
        const Locale('ar'),
      );
      expect(resolveAppLocale(null, supported), const Locale('ar'));
    });
  });
}
