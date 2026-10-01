import 'environment.dart';

/// Build-time configuration.
///
/// Values come from `--dart-define`, never from a checked-in plaintext file,
/// so no environment secrets end up in the repository (§12).
abstract final class AppConfig {
  static const String _envRaw = String.fromEnvironment('ENVIRONMENT');
  static const String _baseUrlRaw = String.fromEnvironment('API_BASE_URL');
  static const String _webSocketRaw = String.fromEnvironment('API_WS_URL');
  static const bool _enableLogging = bool.fromEnvironment(
    'ENABLE_NETWORK_LOGGING',
    defaultValue: true,
  );

  static final Environment environment = Environment.fromDartDefine(_envRaw);

  /// Base URL without a trailing slash. Android emulators reach the host
  /// machine through 10.0.2.2 rather than localhost.
  static final String baseUrl = _resolveBaseUrl(_baseUrlRaw);

  static final String? webSocketUrl = _webSocketRaw.isEmpty
      ? null
      : _webSocketRaw;

  /// Never log credentials or bodies in production (§59).
  static final bool enableNetworkLogging =
      _enableLogging && environment != Environment.production;

  static bool get isProduction => environment == Environment.production;

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 30);

  /// Network images are fetched with the bearer token instead of a URL query
  /// parameter, so there is nothing to append here.
  static String _resolveBaseUrl(String raw) {
    if (raw.isNotEmpty) {
      return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    }

    switch (environment) {
      case Environment.production:
        return 'https://api.homeservices.example.com';
      case Environment.staging:
        return 'https://staging-api.homeservices.example.com';
      case Environment.development:
        return 'http://10.0.2.2:8000';
    }
  }
}
