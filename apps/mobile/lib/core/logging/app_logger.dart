import 'package:flutter/foundation.dart';

import '../security/sensitive_data.dart';

/// Minimal logger.
///
/// Redaction is the default, not an option: this app handles OTPs, JWTs,
/// addresses and payment references, none of which may reach a log sink
/// (§93, §99). Callers pass structured fields, and everything is filtered by
/// [SensitiveData] before printing.
abstract final class AppLogger {
  static bool get enabled => kDebugMode;

  static void debug(String message, {Map<String, Object?> context = const {}}) {
    if (!enabled) return;
    debugPrint('[app] $message${_format(context)}');
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    if (!enabled) return;
    debugPrint('[error] $message${_format(context)}');
    if (error != null) {
      debugPrint('  cause: ${SensitiveData.redact('$error')}');
    }
    if (stackTrace != null) {
      debugPrint('  $stackTrace');
    }
  }

  static String _format(Map<String, Object?> context) {
    if (context.isEmpty) return '';
    final Map<String, String> safe = SensitiveData.redactFields(context);
    final List<String> parts = <String>[
      for (final MapEntry<String, String> entry in safe.entries)
        '${entry.key}=${entry.value}',
    ];
    return ' ${parts.join(' ')}';
  }
}

void debugLog(String message) => AppLogger.debug(message);
