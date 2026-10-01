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
      // Values that are deliberately non-Arabic: a phone placeholder, and the
      // image format names the backend actually accepts (JPEG/PNG/WebP).
      const allowlisted = <String>{'authPhoneHint', 'requestsPhotosHintSize'};
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

    test('no Arabic string is mojibake from a bad decode', () {
      // PowerShell 5.1 reads BOM-less UTF-8 as ANSI, so writing an ARB back
      // through Get-Content silently turns Arabic into Latin-1 box-drawing and
      // shade characters. It rendered as plausible text in the console, so it
      // shipped once as `requestsReviewTitle`. These ranges are the signature
      // of that decode; real Arabic copy never contains them.
      final mojibakeRanges = <String, RegExp>{
        'box drawing': RegExp(r'[\u2500-\u257F]'),
        'block elements': RegExp(r'[\u2580-\u259F]'),
        'Latin-1 supplement': RegExp(r'[\u00A0-\u00BF]'),
        'replacement char': RegExp('�'),
      };

      final offenders = <String>[];
      for (final MapEntry<String, dynamic> entry in _arb(
        'app_ar.arb',
      ).entries) {
        if (entry.key.startsWith('@') || entry.value is! String) continue;
        final String value = entry.value! as String;
        for (final MapEntry<String, RegExp> range in mojibakeRanges.entries) {
          if (range.value.hasMatch(value)) {
            offenders.add('${entry.key} contains ${range.key}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'mojibake means the ARB was rewritten through a lossy decode; '
            'edit ARB with UTF-8 aware tools, not PowerShell Get-Content',
      );
    });

    test('Arabic values that claim to be Arabic contain Arabic letters', () {
      // Catches the inverse failure: a value that lost its Arabic entirely and
      // became punctuation or digits only.
      final offenders = <String>[];
      _arb('app_ar.arb').forEach((String key, Object? value) {
        if (key.startsWith('@') || value is! String) return;
        if ((value! as String).trim().isEmpty) return;
        // These are deliberately non-Arabic values.
        const allowlisted = <String>{'authPhoneHint', 'requestsPhotosHintSize'};
        if (allowlisted.contains(key)) return;

        final bool hasArabicLetter = RegExp(r'[\u0620-\u064A]').hasMatch(value);
        if (!hasArabicLetter) offenders.add('$key -> $value');
      });

      expect(
        offenders,
        isEmpty,
        reason: 'a non-Arabic value in the Arabic catalogue is usually damage',
      );
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
