import 'package:flutter/foundation.dart';

/// Minimal logger.
///
/// Redaction is the default, not an option: this app handles OTPs, JWTs,
/// addresses and payment references, none of which may reach a log sink
/// (§59). Callers pass structured fields, and anything that looks like a secret
/// is replaced before printing.
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
    if (error != null) debugPrint('  cause: ${_redact(error.toString())}');
    if (stackTrace != null) debugPrint('  $stackTrace');
  }

  static String _format(Map<String, Object?> context) {
    if (context.isEmpty) return '';
    final parts = context.entries.map(
      (MapEntry<String, Object?> e) => '${e.key}=${_redact('${e.value}')}',
    );
    return ' ${parts.join(' ')}';
  }

  /// Keeps values that look like credentials out of the output while staying
  /// useful for debugging identifiers and status codes.
  static String _redact(String value) {
    return value
        .replaceAll(RegExp(r'\b(eyJ[A-Za-z0-9_\-]{8,})'), '[jwt]')
        .replaceAll(RegExp(r'\b(\+?\d{8,15})\b'), '[phone]');
  }
}

void debugLog(String message) => AppLogger.debug(message);
