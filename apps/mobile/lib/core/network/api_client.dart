import 'dart:async';

import 'package:dio/dio.dart';

import '../../app/config/app_config.dart';
import '../errors/error_mapper.dart';
import '../errors/failure.dart';
import '../storage/secure_storage_service.dart';
import 'api_endpoints.dart';
import 'auth_interceptor.dart';
import 'logging_interceptor.dart';

/// Single Dio entry point for the whole app.
///
/// Repositories depend on this, never on Dio directly, so auth, timeouts,
/// correlation ids and error translation live in exactly one place (§20).
///
/// Also implements [AuthTokenDelegate] so the token lifecycle lives in
/// `core/network/auth_interceptor.dart` while the refresh implementation, which
/// needs the token store, stays here.
class ApiClient implements AuthTokenDelegate {
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
      AuthInterceptor(this),
      CorrelationInterceptor(),
      if (AppConfig.enableNetworkLogging) LoggingInterceptor(),
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

  /// For the endpoints that answer with a bare JSON array.
  ///
  /// Dio cannot decode an array into `Map<String, dynamic>`, so the catalogue
  /// endpoints (`GET /services`, `GET /catalogue`, `GET /services/{id}/problems`)
  /// must be read as a list. They are declared `response_model=list[...]` on the
  /// backend and are not wrapped in a pagination envelope.
  Future<Response<List<Map<String, dynamic>>>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    return _send<List<Map<String, dynamic>>>(
      () => _dio.get<List<Map<String, dynamic>>>(
        path,
        queryParameters: query,
        options: _rejectNonSuccess(null),
      ),
    );
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

  /// Re-issues a request that already ran through the interceptors.
  ///
  /// Called by [AuthInterceptor] after a successful refresh so the retried call
  /// carries the new token and the original correlation id.
  @override
  Future<Response<dynamic>> fetch(RequestOptions options) =>
      _dio.fetch<dynamic>(options);

  @override
  Future<void> attachAuth(RequestOptions options) async {
    if (options.extra[AuthInterceptor.skipAuthFlag] == true) return;
    if (AuthInterceptor.publicPaths.contains(options.path)) return;
    final tokens = await _tokenStore.read();
    if (tokens != null && tokens.accessToken.isNotEmpty) {
      options.headers['Authorization'] =
          '${tokens.tokenType} ${tokens.accessToken}';
    }
  }

  /// Returns true when a new access token is available.
  @override
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
        options: Options(
          extra: <String, dynamic>{AuthInterceptor.skipAuthFlag: true},
        ),
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
  @override
  void notifySessionExpired() {
    unawaited(_tokenStore.clear());
    final callback = _onSessionExpired;
    if (callback != null) unawaited(callback());
  }

  /// Translates a transport-level failure into a displayable [ApiFailure].
  ///
  /// Delegates to [ErrorMapper] so the mapping has one owner and can be
  /// tested without constructing a client.
  ApiFailure translate(DioException error) => ErrorMapper.toFailure(error);

  /// Maps the backend's single error envelope `{code, message, details}`.
  ApiFailure fromResponse(Response<dynamic>? response) =>
      ErrorMapper.failureFromResponse(response);
}
