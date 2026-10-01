import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/core/network/json_readers.dart';

void main() {
  late AppLocalizations ar;
  late AppLocalizations en;

  setUp(() async {
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  // A fixed reference point keeps these assertions independent of the clock.
  final DateTime now = DateTime(2026, 3, 15, 14, 30);

  /// Always injects the reference clock, otherwise these assertions would drift
  /// with the wall clock and start failing next month.
  String rel(Duration gap, {AppLocalizations? l}) =>
      formatRelative(now.subtract(gap), l10n: l ?? ar, now: now);

  group('formatRelative', () {
    test('returns empty for a missing timestamp', () {
      expect(formatRelative(null, l10n: ar), '');
    });

    test('returns empty for a future timestamp', () {
      expect(rel(const Duration(minutes: -5)), '');
    });

    test('picks the right bucket per elapsed time', () {
      expect(rel(const Duration(seconds: 10)), ar.timeNow);
      expect(rel(const Duration(minutes: 7)), ar.timeMinutes(7));
      expect(rel(const Duration(hours: 5)), ar.timeHours(5));
      expect(rel(const Duration(days: 1)), ar.timeYesterday);
      expect(rel(const Duration(days: 4)), ar.timeDays(4));
    });

    test('switches unit at the 30-day and 365-day boundaries', () {
      // 29 days is still days; 30 days rolls over to whole months.
      expect(rel(const Duration(days: 29)), ar.timeDays(29));
      expect(rel(const Duration(days: 30)), ar.timeMonths(1));
      expect(rel(const Duration(days: 200)), ar.timeMonths(6));
      // 364 days is still months; 365 is the first year.
      expect(rel(const Duration(days: 364)), ar.timeMonths(12));
      expect(rel(const Duration(days: 365)), ar.timeYears(1));
      expect(rel(const Duration(days: 400)), ar.timeYears(1));
    });

    test('is not midnight-sensitive: 23 hours is hours, not yesterday', () {
      expect(rel(const Duration(hours: 23)), ar.timeHours(23));
    });

    test('honours the injected clock instead of the wall clock', () {
      final DateTime value = DateTime(2020, 1, 1);
      expect(formatRelative(value, l10n: ar, now: now), ar.timeYears(6));
    });

    test('returns real copy for English, not Arabic', () {
      final String out = rel(const Duration(minutes: 7), l: en);
      expect(out, isNot(ar.timeMinutes(7)));
      expect(out, en.timeMinutes(7));
    });
  });

  group('formatDateTime', () {
    test('renders 12-hour clock with a localised meridiem', () {
      final DateTime morning = DateTime(2026, 3, 15, 9, 5);
      final DateTime afternoon = DateTime(2026, 3, 15, 15, 5);
      final DateTime midnight = DateTime(2026, 3, 15, 0, 30);
      final DateTime noon = DateTime(2026, 3, 15, 12, 0);

      expect(
        formatDateTime(morning, l10n: ar),
        '15/03/2026 · 9:05 ${ar.meridiemAm}',
      );
      expect(
        formatDateTime(afternoon, l10n: ar),
        '15/03/2026 · 3:05 ${ar.meridiemPm}',
      );
      // Midnight and noon are the classic off-by-12 cases: both render as 12.
      expect(
        formatDateTime(midnight, l10n: ar),
        '15/03/2026 · 12:30 ${ar.meridiemAm}',
      );
      expect(
        formatDateTime(noon, l10n: ar),
        '15/03/2026 · 12:00 ${ar.meridiemPm}',
      );
    });

    test('pads the minutes', () {
      expect(
        formatDateTime(DateTime(2026, 3, 15, 8, 7), l10n: en),
        '15/03/2026 · 8:07 ${en.meridiemAm}',
      );
    });

    test('returns empty for null', () {
      expect(formatDateTime(null, l10n: ar), '');
    });
  });

  group('formatDate', () {
    test('zero-pads day and month', () {
      expect(formatDate(DateTime(2026, 1, 2)), '02/01/2026');
    });

    test('returns empty for null', () {
      expect(formatDate(null), '');
    });
  });

  group('formatMoney', () {
    test('groups thousands and always shows two decimals', () {
      expect(formatMoney('1234.5'), '1,234.50 EGP');
      expect(formatMoney('1000000'), '1,000,000.00 EGP');
      expect(formatMoney('0'), '0.00 EGP');
    });

    test('falls back to the bare symbol when unparseable', () {
      expect(formatMoney(null), 'EGP');
      expect(formatMoney('not-a-number'), 'EGP');
    });

    test('accepts a non-default currency', () {
      expect(formatMoney('250', symbol: 'SAR'), '250.00 SAR');
    });
  });
}
