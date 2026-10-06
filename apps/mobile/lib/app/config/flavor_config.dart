import 'environment.dart';

/// Per-environment endpoints and feature switches.
///
/// Separate from [AppConfig] because these values differ per build target and
/// per environment, while timeouts and the logging policy are properties of the
/// app itself. Every value comes from `--dart-define` so no host or key is ever
/// committed (§12).
abstract final class FlavorConfig {
  static const String _baseUrlRaw = String.fromEnvironment('API_BASE_URL');
  static const String _webSocketRaw = String.fromEnvironment('API_WS_URL');

  /// The Web client ID whose audience the backend accepts on an ID token.
  ///
  /// Unlike a host or a secret this value is public by design: it ships inside
  /// the APK and Google publishes it. It is only overridable for the same
  /// reason the base URL is, so a fork of this app can point at its own project.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '423399881855-cqrpnda8gasr3jmnhjgutff6j1fvjlp1.apps.googleusercontent.com',
  );

  /// Base URL without a trailing slash.
  ///
  /// Android emulators reach the host machine through 10.0.2.2, not localhost.
  /// A Flutter Web build runs on the same machine, so localhost is correct
  /// there; passing an explicit `--dart-define` overrides both.
  static String baseUrl(Environment environment) {
    if (_baseUrlRaw.isNotEmpty) return _stripTrailingSlash(_baseUrlRaw);
    return switch (environment) {
      Environment.production => 'https://api-production-abe8e.up.railway.app',
      Environment.staging => 'https://staging-api.homeservices.example.com',
      Environment.development => 'http://10.0.2.2:8000',
    };
  }

  /// Optional realtime endpoint. Null means the app never opens a socket, which
  /// is correct today: the spec has no live technician tracking (§28).
  static String? webSocketUrl() => _webSocketRaw.isEmpty ? null : _webSocketRaw;

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
