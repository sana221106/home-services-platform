/// Every persisted key in one place.
///
/// Centralised so a rename can never orphan a value silently, and so tests can
/// assert that nothing is written outside this set (§91).
abstract final class StorageKeys {
  /// `access|refresh|type|expiresAt`, newline separated, in the keystore.
  static const String sessionTokens = 'auth.session_tokens';

  /// Theme mode: `system` | `light` | `dark`.
  static const String themeMode = 'settings.theme_mode';

  /// Locale tag, or null when the device language should decide.
  static const String locale = 'settings.locale';

  /// Whether the customer has finished onboarding.
  static const String onboardingSeen = 'settings.onboarding_seen';

  /// Idempotency key for the request currently being drafted.
  static const String requestDraftKey = 'requests.draft_idempotency_key';

  /// Keys that must never appear in shared preferences, because they hold
  /// credentials. Asserted by `storage_key_test.dart`.
  static const Set<String> secret = <String>{sessionTokens};
}

/// Keys allowed in plain (non-keystore) storage. Used by the security audit
/// test to prove no token ever lands here.
abstract final class LocalStorageKeys {
  static const Set<String> allowed = <String>{
    StorageKeys.themeMode,
    StorageKeys.locale,
    StorageKeys.onboardingSeen,
    StorageKeys.requestDraftKey,
  };
}
