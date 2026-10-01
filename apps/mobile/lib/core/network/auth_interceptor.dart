import 'dart:async';

import 'package:dio/dio.dart';

import 'api_endpoints.dart';

/// What [AuthInterceptor] needs from whoever owns the Dio instance.
///
/// Declared as an interface rather than importing `ApiClient`, because the
/// client registers this interceptor and a direct import would be a cycle.
abstract interface class AuthTokenDelegate {
  /// Adds the bearer header unless the path is public.
  Future<void> attachAuth(RequestOptions options);

  /// Rotates the session. Concurrent callers share one refresh (§94).
  Future<bool> refreshTokens();

  /// Clears tokens and tells the router to send the customer to onboarding.
  void notifySessionExpired();

  /// Re-issues the original request after a successful refresh.
  Future<Response<dynamic>> fetch(RequestOptions options);
}

/// Attaches the bearer token, refreshes once on 401, and reports expiry.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._client);

  final AuthTokenDelegate _client;

  /// Marks a request as the refresh call itself so this interceptor skips it.
  /// Prevents an infinite refresh loop without a second Dio instance.
  static const String skipAuthFlag = 'skip_auth';

  static const String _retryFlag = 'auth_retry';

  /// Endpoints that must not carry a bearer token.
  static const Set<String> publicPaths = <String>{
    ApiEndpoints.authRequestOtp,
    ApiEndpoints.authVerifyOtp,
    ApiEndpoints.authRefresh,
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(_authorize(options, handler));
  }

  Future<void> _authorize(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      await _client.attachAuth(options);
    } catch (_) {
      // A storage read failure must not block the request; the server decides.
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(_handleError(err, handler));
  }

  Future<void> _handleError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final bool is401 = err.response?.statusCode == 401;
    final bool alreadyRetried = options.extra[_retryFlag] == true;

    if (is401 && !alreadyRetried && !_isAuthEndpoint(options.path)) {
      options.extra[_retryFlag] = true;
      final bool refreshed = await _client.refreshTokens();

      if (!refreshed) {
        _client.notifySessionExpired();
        handler.next(err);
        return;
      }

      try {
        options.headers.remove('Authorization');
        await _client.attachAuth(options);
        handler.resolve(await _client.fetch(options));
      } catch (_) {
        // The retry failed too; surface the original 401 so the router can
        // send the customer back to onboarding.
        handler.next(err);
      }
      return;
    }

    if (is401) {
      _client.notifySessionExpired();
    }

    handler.next(err);
  }

  static bool _isAuthEndpoint(String path) =>
      path == ApiEndpoints.authRefresh ||
      path == ApiEndpoints.authRequestOtp ||
      path == ApiEndpoints.authVerifyOtp;
}
