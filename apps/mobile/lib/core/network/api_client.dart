import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../app/config/app_config.dart';
import '../logging/app_logger.dart';
import 'api_endpoints.dart';
import 'api_failure.dart';
import 'token_store.dart';

/// Single Dio entry point for the whole app.
///
/// Repositories depend on this, never on Dio directly, so auth, timeouts,
/// correlation ids and error translation live in exactly one place (§20).
class ApiClient {
  ApiClient({
    required TokenStore tokenStore,
    Dio? dio,
    Future<void> Function()? onSessionExpired,
  }) : _tokenStore = tokenStore,
       _onSessionExpired = onSessionExpired {
    _dio = dio ?? Dio();
    _dio.options = BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      // Status handling is manual so a non-2xx never throws an untyped error.
      validateStatus: (int? status) => status != null && status < 400,
    );
    _dio.interceptors.addAll(<Interceptor>[
      _AuthInterceptor(this),
      _CorrelationInterceptor(),
      if (AppConfig.enableNetworkLogging) _LogInterceptor(),
    ]);
  }

  final TokenStore _tokenStore;
  final Future<void> Function()? _onSessionExpired;

  late final Dio _dio;

  /// Shared across concurrent 401s: the first caller refreshes, the rest await
  /// the same future instead of firing a refresh storm.
  Future<bool>? _refreshInFlight;

  Dio get raw => _dio;

  // ---------------------------------------------------------------------
  // Verb helpers.
  //
  // Data sources use these instead of touching Dio so every call inherits the
  // auth, correlation and logging interceptors, and so a 4xx/5xx always raises
  // a DioException carrying the backend envelope that [translate] understands.
  // ---------------------------------------------------------------------

  Future<Response<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    final Response<Map<String, dynamic>> response =
        await _send<Map<String, dynamic>>(
          () => _dio.get<Map<String, dynamic>>(
            path,
            queryParameters: query,
            options: _rejectNonSuccess(options),
          ),
        );
    return response;
  }

  Future<Response<Map<String, dynamic>>> post(
    String path, {
    Object? data,
    Options? options,
  }) async {
    final Response<Map<String, dynamic>> response =
        await _send<Map<String, dynamic>>(
          () => _dio.post<Map<String, dynamic>>(
            path,
            data: data,
            options: _rejectNonSuccess(options),
          ),
        );
    return response;
  }

  Future<Response<Map<String, dynamic>>> patch(
    String path, {
    Object? data,
    Options? options,
  }) async {
    final Response<Map<String, dynamic>> response =
        await _send<Map<String, dynamic>>(
          () => _dio.patch<Map<String, dynamic>>(
            path,
            data: data,
            options: _rejectNonSuccess(options),
          ),
        );
    return response;
  }

  Future<Response<Map<String, dynamic>>> delete(
    String path, {
    Object? data,
    Options? options,
  }) async {
    final Response<Map<String, dynamic>> response =
        await _send<Map<String, dynamic>>(
          () => _dio.delete<Map<String, dynamic>>(
            path,
            data: data,
            options: _rejectNonSuccess(options),
          ),
        );
    return response;
  }

  /// Multipart upload for request media and payment proof (§79, §6).
  Future<Response<Map<String, dynamic>>> upload(
    String path, {
    required FormData formData,
    Options? options,
  }) async {
    final Response<Map<String, dynamic>> response =
        await _send<Map<String, dynamic>>(
          () => _dio.post<Map<String, dynamic>>(
            path,
            data: formData,
            options: _rejectNonSuccess(
              options ?? Options(),
              contentType: 'multipart/form-data',
            ),
          ),
        );
    return response;
  }

  /// Runs a request and converts any non-2xx into a [DioException] shaped like
  /// Dio's own, so `translate` and `fromResponse` work unchanged.
  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) async {
    try {
      final Response<T> response = await request();
      final int status = response.statusCode ?? 0;
      if (status >= 400) {
        throw DioException.badResponse(
          statusCode: status,
          requestOptions: response.requestOptions,
          response: response,
        );
      }
      return response;
    } on DioException catch (error) {
      // Preserve genuine transport failures; only synthesise for 4xx/5xx that
      // slipped through validateStatus.
      if (error.response == null &&
          error.type != DioExceptionType.badResponse) {
        rethrow;
      }
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  static Options _rejectNonSuccess(Options? options, {String? contentType}) {
    return (options ?? Options()).copyWith(
      validateStatus: (int? status) => status != null && status < 400,
      contentType: contentType,
    );
  }

  /// Endpoints that must not carry a bearer token or trigger a refresh loop.
  static const Set<String> _publicPaths = <String>{
    ApiEndpoints.authRequestOtp,
    ApiEndpoints.authVerifyOtp,
    ApiEndpoints.authRefresh,
  };

  /// Marks a request as the refresh call itself so the auth interceptor skips
  /// it. Prevents an infinite refresh loop without a second Dio instance.
  static const String skipAuthFlag = 'skip_auth';

  Future<void> attachAuth(RequestOptions options) async {
    if (options.extra[skipAuthFlag] == true) return;
    if (_publicPaths.contains(options.path)) return;
    final tokens = await _tokenStore.read();
    if (tokens != null && tokens.accessToken.isNotEmpty) {
      options.headers['Authorization'] =
          '${tokens.tokenType} ${tokens.accessToken}';
    }
  }

  /// Returns true when a new access token is available.
  Future<bool> refreshTokens() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final current = await _tokenStore.read();
    if (current == null || current.refreshToken.isEmpty) return false;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.authRefresh,
        data: <String, dynamic>{'refresh_token': current.refreshToken},
        options: Options(extra: <String, dynamic>{skipAuthFlag: true}),
      );
      final body = response.data;
      if (body == null) return false;
      await _tokenStore.write(TokenPair.fromJson(body));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Called once per expired session so the router can bounce to onboarding.
  void notifySessionExpired() {
    unawaited(_tokenStore.clear());
    final callback = _onSessionExpired;
    if (callback != null) unawaited(callback());
  }

  /// Translates a transport-level failure into a displayable [ApiFailure].
  ApiFailure translate(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiFailure.timeout();
      case DioExceptionType.cancel:
        return const ApiFailure.cancelled();
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return const ApiFailure.network();
      case DioExceptionType.badCertificate:
        return const ApiFailure(
          code: 'BAD_CERTIFICATE',
          message: 'تعذر التحقق من اتصال الخادم الآمن.',
        );
      case DioExceptionType.badResponse:
        return fromResponse(error.response);
      case DioExceptionType.transformTimeout:
        return const ApiFailure.timeout();
    }
  }

  /// Maps the backend's single error envelope `{code, message, details}`.
  ApiFailure fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final correlationId =
        response?.headers.value('X-Correlation-ID') ??
        (response?.requestOptions.headers['X-Correlation-ID'] as String?);
    final data = response?.data;

    if (data is Map) {
      final code = data['code'] as String? ?? _defaultCode(status);
      final rawMessage = data['message'] as String?;
      return ApiFailure(
        code: code,
        message: rawMessage ?? _fallbackMessage(status),
        statusCode: status,
        details:
            (data['details'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        fieldErrors: _fieldErrors(data['details']),
        correlationId: correlationId,
      );
    }

    return ApiFailure(
      code: _defaultCode(status),
      message: _fallbackMessage(status),
      statusCode: status,
      correlationId: correlationId,
    );
  }

  Map<String, String> _fieldErrors(Object? details) {
    if (details is! Map) return const <String, String>{};
    final out = <String, String>{};
    details.forEach((Object? key, Object? value) {
      if (key is String && value is String && value.isNotEmpty) {
        out[key] = value;
      } else if (key is String && value is List && value.isNotEmpty) {
        out[key] = value.first.toString();
      }
    });
    return out;
  }

  static String _defaultCode(int? status) => switch (status) {
    400 || 422 => ApiErrorCodes.validationError,
    401 => ApiErrorCodes.unauthenticated,
    403 => ApiErrorCodes.forbidden,
    404 => ApiErrorCodes.notFound,
    409 => ApiErrorCodes.conflict,
    413 => ApiErrorCodes.uploadRejected,
    429 => ApiErrorCodes.rateLimited,
    null => 'NETWORK_UNAVAILABLE',
    _ => 'HTTP_$status',
  };

  static String _fallbackMessage(int? status) {
    if (status == null) return 'تعذر الاتصال بالخادم.';
    if (status >= 500) return 'خدمة غير متاحة مؤقتًا. حاول مرة أخرى.';
    return switch (status) {
      401 => 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      403 => 'ليس لديك صلاحية للقيام بهذا الإجراء.',
      404 => 'العنصر المطلوب غير موجود.',
      409 => 'تم تعديل البيانات بالفعل. حدّث الصفحة وحاول مجددًا.',
      429 => 'طلبات كثيرة جدًا. حاول مرة أخرى بعد قليل.',
      _ => 'حدث خطأ غير متوقع.',
    };
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);

  final ApiClient _client;
  static const String _retryFlag = 'auth_retry';

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

  static bool _isAuthEndpoint(String path) =>
      path == ApiEndpoints.authRefresh ||
      path == ApiEndpoints.authVerifyOtp ||
      path == ApiEndpoints.authRequestOtp;

  Future<void> _handleError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = options.extra[_retryFlag] == true;

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
        handler.resolve(await _client.raw.fetch<dynamic>(options));
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
}

class _CorrelationInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Correlation-ID'] =
        options.headers['X-Correlation-ID'] ?? _generate();
    handler.next(options);
  }

  static final Random _random = Random();

  static String _generate() {
    final int a = _random.nextInt(1 << 32);
    final int b = _random.nextInt(1 << 32);
    return a.toRadixString(16).padLeft(8, '0') +
        b.toRadixString(16).padLeft(8, '0');
  }
}

class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Method, path and status only: never headers or bodies, which carry
    // tokens, OTPs, addresses and payment references.
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
