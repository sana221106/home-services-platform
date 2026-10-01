/// Phone number parsing.
///
/// Extracted from the login widget so the normalisation rule has one owner and
/// can be unit tested without pumping a screen (§119). The backend still
/// validates every number; this only avoids a pointless round trip on input the
/// server will reject anyway (§8).
abstract final class PhoneNumber {
  /// Default dialling code for the launch market. Not a business rule: the
  /// backend accepts any E.164 number, so this only fills in what the customer
  /// omitted.
  static const String defaultDialCode = '+20';

  /// Characters a human types that are not part of the number.
  static final RegExp _separators = RegExp(r'[\s\-().]');

  /// Backend contract: `^\+?[0-9]{8,15}$`.
  static final RegExp _e164 = RegExp(r'^\+[0-9]{8,15}$');

  /// Normalises typed input to E.164, or null when it cannot be a phone number.
  ///
  /// Accepts `01xxxxxxxxx`, `1xxxxxxxxx`, `+201xxxxxxxxx` and anything with
  /// spaces, dashes or brackets. A leading `00` is treated as the plus sign.
  static String? normalize(String raw, {String dialCode = defaultDialCode}) {
    if (raw.trim().isEmpty) return null;

    String digits = raw.trim().replaceAll(_separators, '');
    if (digits.startsWith('00')) digits = '+${digits.substring(2)}';

    final String candidate = switch (digits) {
      final String d when d.startsWith('+') => d,
      final String d when d.startsWith('0') => '$dialCode${d.substring(1)}',
      final String d => '$dialCode$d',
    };

    return _e164.hasMatch(candidate) ? candidate : null;
  }
}
