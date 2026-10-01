import 'environment.dart';
import 'flavor_config.dart';

/// Build-time configuration.
///
/// Values come from `--dart-define`, never from a checked-in plaintext file,
/// so no environment secrets end up in the repository (§12).
abstract final class AppConfig {
  static const String _envRaw = String.fromEnvironment('ENVIRONMENT');
  static const bool _enableLogging = bool.fromEnvironment(
    'ENABLE_NETWORK_LOGGING',
    defaultValue: true,
  );

  static final Environment environment = Environment.fromDartDefine(_envRaw);

  /// Host and API prefix for this build.
  static final String baseUrl = FlavorConfig.baseUrl(environment);

  /// Realtime endpoint, or null when the build has none.
  static final String? webSocketUrl = FlavorConfig.webSocketUrl();

  /// Never log request bodies or credentials in production (§93).
  static final bool enableNetworkLogging =
      _enableLogging && environment != Environment.production;

  static bool get isProduction => environment == Environment.production;

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Longer because request submission and media upload are both writes.
  static const Duration sendTimeout = Duration(seconds: 30);
}
