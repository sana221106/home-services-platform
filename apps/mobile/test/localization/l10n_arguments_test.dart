import 'dart:convert';
import 'dart:ui' show Locale;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/app/localization/app_localizations.dart';

/// Guards the messages that take arguments.
///
/// `flutter gen-l10n` emits placeholder parameters in its own order rather than
/// the order they appear in the ARB, so a positional call site can bind the
/// numbers to the wrong words without any compile error. Each case here renders
/// the message and asserts the literal output, which is the only thing that
/// actually matters to the customer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations ar;

  setUp(() async {
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  group('argument order', () {
    test('wizard step counter binds current before total', () {
      // Signature is requestsStepCounter(int total, int current).
      expect(ar.requestsStepCounter(5, 3), 'الخطوة 3 من 5');
      expect(ar.requestsStepCounter(5, 1), 'الخطوة 1 من 5');
    });

    test('photo counter binds count before max', () {
      expect(ar.requestsPhotosCount(2, 8), '2 من 8 صور');
    });

    test('single-argument messages', () {
      expect(ar.requestsPhotosLimit(8), contains('8'));
      expect(ar.requestsCountLabel(7), contains('7'));
      expect(ar.timeMinutes(7), 'منذ 7 دقيقة');
      expect(ar.timeHours(3), 'منذ 3 ساعة');
      expect(ar.timeDays(9), 'منذ 9 يوم');
      expect(ar.timeMonths(2), 'منذ 2 شهر');
      expect(ar.timeYears(1), 'منذ 1 سنة');
    });
  });

  group('ARB and generated output agree', () {
    // A message can be correct in the ARB and still render wrong if gen-l10n
    // regenerated with a different placeholder set, so compare the rendered
    // string against the template for the messages that take numbers.
    test('every numeric message fills all its placeholders', () {
      final Map<String, dynamic> arMap =
          jsonDecode(
                File('lib/app/localization/arb/app_ar.arb').readAsStringSync(),
              )
              as Map<String, dynamic>;

      final cases = <String, String Function()>{
        'requestsStepCounter': () => ar.requestsStepCounter(5, 3),
        'requestsPhotosCount': () => ar.requestsPhotosCount(2, 8),
        'requestsPhotosLimit': () => ar.requestsPhotosLimit(8),
        'requestsCountLabel': () => ar.requestsCountLabel(7),
        'timeMinutes': () => ar.timeMinutes(7),
        'timeHours': () => ar.timeHours(3),
        'timeDays': () => ar.timeDays(9),
        'timeMonths': () => ar.timeMonths(2),
        'timeYears': () => ar.timeYears(1),
      };

      cases.forEach((String key, String Function() render) {
        final String rendered = render();
        expect(
          rendered,
          isNot(contains('{')),
          reason: '$key rendered an unfilled placeholder: $rendered',
        );
        final String template = arMap[key]! as String;
        // Every placeholder in the template must be represented by a number in
        // the output.
        final int placeholders = RegExp(r'\{\w+\}').allMatches(template).length;
        final int numbers = RegExp(r'\d').allMatches(rendered).length;
        expect(
          numbers,
          greaterThanOrEqualTo(placeholders),
          reason: '$key lost an argument',
        );
      });
    });
  });
}
