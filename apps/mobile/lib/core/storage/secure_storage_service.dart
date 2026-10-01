import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session tokens returned by `POST /api/v1/auth/verify-otp` and rotated by
/// `POST /api/v1/auth/refresh`.
///
/// Tokens live in the platform keystore / keychain, never in shared
/// preferences and never in plaintext on disk.
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.tokenType = 'Bearer',
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    return TokenPair(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    );
  }

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final DateTime expiresAt;

  /// Refresh slightly early so an in-flight request cannot race the expiry.
  bool get isExpired =>
      DateTime.now().add(const Duration(minutes: 1)).isAfter(expiresAt);

  @override
  String toString() =>
      'TokenPair(type: $tokenType, expiresAt: $expiresAt, access: [redacted])';
}

/// Storage abstraction so tests can inject a fake without the platform channel.
abstract interface class TokenStore {
  Future<TokenPair?> read();
  Future<void> write(TokenPair tokens);
  Future<void> clear();
}

/// Keychain-backed [TokenStore] with an in-memory cache.
///
/// The cache keeps the Dio interceptor off the platform channel on every
/// request, which matters because a failed read must not block the app start.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // v11 encrypts with AES_GCM by default; resetOnError recovers a
            // keyset invalidated by an OS upgrade instead of failing reads.
            aOptions: AndroidOptions(
              resetOnError: true,
              migrateOnAlgorithmChange: true,
            ),
            // Session tokens are readable only while the device is unlocked
            // and never migrate to a new device via backup.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const String _key = 'auth_tokens';

  final FlutterSecureStorage _storage;
  TokenPair? _cached;

  @override
  Future<TokenPair?> read() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = _decode(raw);
      _cached = decoded;
      return decoded;
    } catch (_) {
      // A corrupted keystore entry must not crash the app; the user signs in
      // again instead.
      await _safeClear();
      return null;
    }
  }

  @override
  Future<void> write(TokenPair tokens) async {
    _cached = tokens;
    await _storage.write(key: _key, value: _encode(tokens));
  }

  @override
  Future<void> clear() async {
    _cached = null;
    await _safeClear();
  }

  Future<void> _safeClear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing actionable: the cache is already cleared.
    }
  }

  String _encode(TokenPair tokens) =>
      '${tokens.accessToken}\n${tokens.refreshToken}\n${tokens.tokenType}\n${tokens.expiresAt.toUtc().toIso8601String()}';

  TokenPair? _decode(String raw) {
    final parts = raw.split('\n');
    if (parts.length < 4) return null;
    return TokenPair(
      accessToken: parts[0],
      refreshToken: parts[1],
      tokenType: parts[2],
      expiresAt: DateTime.parse(parts[3]).toLocal(),
    );
  }
}

/// Non-persistent [TokenStore] for tests.
class InMemoryTokenStore implements TokenStore {
  TokenPair? tokens;

  @override
  Future<TokenPair?> read() async => tokens;

  @override
  Future<void> write(TokenPair tokens) async => this.tokens = tokens;

  @override
  Future<void> clear() async => tokens = null;
}
