import 'dart:math';

import 'package:dio/dio.dart';

import '../logging/app_logger.dart';

/// Adds a per-request correlation id and logs method, path and status.
///
/// Never logs headers or bodies: those carry tokens, OTPs, addresses and payment
/// references (§93). The id matches the `X-Correlation-ID` the backend returns,
/// so a customer screenshot can be traced end to end.
class CorrelationInterceptor extends Interceptor {
  CorrelationInterceptor();

  static const String header = 'X-Correlation-ID';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers[header] =
        options.headers[header] ?? generateCorrelationId();
    handler.next(options);
  }

  /// 16 hex characters, matching the backend's trace id width.
  static String generateCorrelationId() {
    final Random random = Random();
    final String high = random
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    final String low = random
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$high$low';
  }
}

/// Network logging, enabled only by the `ENABLE_NETWORK_LOGGING` dart-define.
///
/// Kept separate from [CorrelationInterceptor] so a release build carries no
/// logging code path at all.
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugLog('→ ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    debugLog('← ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugLog(
      '✗ ${err.response?.statusCode ?? err.type.name} '
      '${err.requestOptions.path}',
    );
    handler.next(err);
  }
}
