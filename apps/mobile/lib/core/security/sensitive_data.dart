/// Keeps credentials and personal data out of logs and crash reports.
///
/// The app handles OTPs, JWTs, access/refresh tokens, customer addresses and
/// payment references. None of those may reach a log sink or an analytics
/// payload, so redaction lives in one place and every logger calls it before
/// printing (§93, §99).
abstract final class SensitiveData {
  /// Field names whose values are always replaced wholesale.
  ///
  /// Matching on the key is the reliable half: a token under an unexpected name
  /// still gets caught here, which the value patterns alone cannot guarantee.
  static const Set<String> secretKeys = <String>{
    'access_token',
    'accesstoken',
    'refresh_token',
    'refreshtoken',
    'id_token',
    'authorization',
    'auth',
    'token',
    'otp',
    'otp_code',
    'code',
    'password',
    'pin',
    'card',
    'cvv',
    'national_id',
    'ssn',
  };

  /// Field names that identify a person but are useful for debugging, so only
  /// the middle of the value is kept.
  static const Set<String> personalKeys = <String>{
    'phone',
    'phone_number',
    'mobile',
    'msisdn',
    'address',
    'address_line',
    'national_id_number',
  };

  static const String mask = '[redacted]';

  /// Redacts free text that slipped past the key check.
  ///
  /// The lookarounds guard digit boundaries only. A `\b` before the optional `+`
  /// would never match, because `+` is not a word character, which leaked the
  /// plus sign into the output as `+[phone]`.
  static String redact(String value) {
    return value
        .replaceAll(RegExp(r'\beyJ[A-Za-z0-9_\-]{8,}'), '[jwt]')
        .replaceAll(RegExp(r'(?<!\d)\+?\d{8,15}(?!\d)'), '[phone]');
  }

  /// Redacts one field value, applying the stricter rule for its key.
  static String redactField(String key, Object? value) {
    if (value == null) return 'null';
    final String text = '$value';
    final String normalized = key.toLowerCase().replaceAll(
      RegExp(r'[\s\-]'),
      '_',
    );

    if (secretKeys.contains(normalized)) return mask;
    if (personalKeys.contains(normalized)) return _maskMiddle(text);
    return redact(text);
  }

  /// Redacts a whole structured payload, preserving the key so the log stays
  /// readable while the value disappears.
  static Map<String, String> redactFields(Map<String, Object?> fields) {
    return <String, String>{
      for (final MapEntry<String, Object?> entry in fields.entries)
        entry.key: redactField(entry.key, entry.value),
    };
  }

  /// Keeps the last few characters so two log lines can still be correlated
  /// without exposing the number.
  static String _maskMiddle(String value) {
    if (value.length <= 4) return mask;
    final String tail = value.substring(value.length - 4);
    return '$mask($tail)';
  }
}
