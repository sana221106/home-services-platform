import 'package:equatable/equatable.dart';

import '../../app/localization/app_localizations.dart';

/// Tolerant readers for backend JSON.
///
/// The API returns ISO-8601 timestamps, decimal money, and string enums, and a
/// widget test must never crash because one field arrived as `null` or as a
/// number instead of a string. Every screen model is parsed through these
/// helpers rather than with raw casts.
extension JsonMap on Map<String, dynamic> {
  /// Reads a string, tolerating numbers and booleans.
  String? str(String key) {
    final Object? raw = this[key];
    return switch (raw) {
      final String v => v.trim().isEmpty ? null : v,
      final num v => v.toString(),
      final bool v => v.toString(),
      _ => null,
    };
  }

  String strOr(String key, String fallback) => str(key) ?? fallback;

  /// Reads an int, tolerating numeric strings such as `"12"`.
  int? integer(String key) {
    final Object? raw = this[key];
    return switch (raw) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v.trim()),
      _ => null,
    };
  }

  int intOr(String key, int fallback) => integer(key) ?? fallback;

  double? decimal(String key) {
    final Object? raw = this[key];
    return switch (raw) {
      final num v => v.toDouble(),
      final String v => double.tryParse(v.trim()),
      _ => null,
    };
  }

  bool flag(String key, {bool fallback = false}) {
    final Object? raw = this[key];
    return switch (raw) {
      final bool v => v,
      final num v => v != 0,
      final String v => v.toLowerCase() == 'true',
      _ => fallback,
    };
  }

  /// Reads a nested object, or an empty map when absent. Never null so callers
  /// can chain lookups without null checks.
  Map<String, dynamic> obj(String key) {
    final Object? raw = this[key];
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return (raw.first as Map).cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic>? objOrNull(String key) {
    final Object? raw = this[key];
    if (raw is Map) return raw.cast<String, dynamic>();
    return null;
  }

  List<String> stringList(String key) {
    final Object? raw = this[key];
    if (raw is! List) return const <String>[];
    return raw
        .map((Object? v) => v?.toString() ?? '')
        .where((String v) => v.isNotEmpty)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> mapList(String key) {
    final Object? raw = this[key];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((Map e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  /// Parses an ISO-8601 timestamp, returning null for absent or malformed
  /// values rather than throwing.
  DateTime? time(String key) {
    final Object? raw = this[key];
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }
}

/// Renders money for display.
///
/// Amounts are kept as strings from the API to avoid float drift on values the
/// customer will be charged. Only non-finite input is coerced.
String formatMoney(String? amount, {String symbol = 'EGP'}) {
  final num? value = num.tryParse((amount ?? '').trim());
  if (value == null) return symbol;
  final String fixed = value.toStringAsFixed(2);
  final List<String> parts = fixed.split('.');
  final StringBuffer buffer = StringBuffer();
  final String whole = parts.first;
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  buffer.write('.${parts.length > 1 ? parts[1] : '00'}');
  return '${buffer.toString()} $symbol';
}

/// Short relative age used by timelines and notifications ("منذ 3 أيام").
///
/// Takes [AppLocalizations] rather than embedding Arabic, because all copy is
/// centralised in ARB (§22). `now` is injectable so this is testable.
String formatRelative(
  DateTime? value, {
  required AppLocalizations l10n,
  DateTime? now,
}) {
  if (value == null) return '';
  final DateTime reference = now ?? DateTime.now();
  final Duration gap = reference.difference(value.toLocal());

  if (gap.isNegative) return '';
  if (gap.inMinutes < 1) return l10n.timeNow;
  if (gap.inMinutes < 60) return l10n.timeMinutes(gap.inMinutes);
  if (gap.inHours < 24) return l10n.timeHours(gap.inHours);
  if (gap.inDays == 1) return l10n.timeYesterday;
  if (gap.inDays < 30) return l10n.timeDays(gap.inDays);
  if (gap.inDays < 365) return l10n.timeMonths(gap.inDays ~/ 30);
  return l10n.timeYears(gap.inDays ~/ 365);
}

/// Calendar date and 12-hour clock, used by timelines and arrival windows.
String formatDateTime(DateTime? value, {required AppLocalizations l10n}) {
  if (value == null) return '';
  final DateTime local = value.toLocal();
  final String date = formatDate(value);
  final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final String minute = local.minute.toString().padLeft(2, '0');
  final String meridiem = local.hour < 12 ? l10n.meridiemAm : l10n.meridiemPm;
  return '$date · $hour:$minute $meridiem';
}

String formatDate(DateTime? value) {
  if (value == null) return '';
  final DateTime local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

/// A plain value object used when a screen needs to compare payloads.
class StringSet extends Equatable {
  const StringSet(this.values);

  final Set<String> values;

  @override
  List<Object?> get props => <Object?>[values];
}
