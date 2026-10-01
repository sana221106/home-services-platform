import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/core/network/api_client.dart';
import 'package:home_services_app/core/network/api_endpoints.dart';
import 'package:home_services_app/core/network/paginated.dart';
import 'package:home_services_app/core/network/token_store.dart';

/// Records every outbound request and replies from a scripted handler.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  int countOf(String path) =>
      requests.where((RequestOptions r) => r.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  Object? body, {
  int status = 200,
  Map<String, List<String>> headers = const <String, List<String>>{},
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
      ...headers,
    },
  );
}

TokenPair _tokens({
  String access = 'access-1',
  String refresh = 'refresh-1',
  Duration ttl = const Duration(hours: 1),
}) {
  return TokenPair(
    accessToken: access,
    refreshToken: refresh,
    expiresAt: DateTime.now().add(ttl),
  );
}

void main() {
  late InMemoryTokenStore store;

  setUp(() => store = InMemoryTokenStore());

  group('error translation', () {
    test('maps the backend error envelope to ApiFailure', () {
      final client = ApiClient(tokenStore: store);
      final failure = client.fromResponse(
        Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(),
          statusCode: 409,
          data: <String, dynamic>{
            'code': 'INVALID_STATE_TRANSITION',
            'message': 'لا يمكن إلغاء الطلب في هذه المرحلة.',
            'details': <String, dynamic>{'from': 'CONFIRMED'},
          },
          headers: Headers.fromMap(<String, List<String>>{
            'X-Correlation-ID': <String>['abc123'],
          }),
        ),
      );

      expect(failure.code, 'INVALID_STATE_TRANSITION');
      expect(failure.message, 'لا يمكن إلغاء الطلب في هذه المرحلة.');
      expect(failure.statusCode, 409);
      expect(failure.isConflict, isTrue);
      expect(failure.details['from'], 'CONFIRMED');
      expect(failure.correlationId, 'abc123');
    });

    test('flattens 422 validation details into field errors', () {
      final client = ApiClient(tokenStore: store);
      final failure = client.fromResponse(
        Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(),
          statusCode: 422,
          data: <String, dynamic>{
            'code': 'VALIDATION_ERROR',
            'message': 'بيانات غير صالحة.',
            'details': <String, dynamic>{
              'phone': 'رقم الهاتف غير صحيح.',
              'code': <String>['رمز التحقق مطلوب.'],
            },
          },
        ),
      );

      expect(failure.isValidation, isTrue);
      expect(failure.fieldErrors['phone'], 'رقم الهاتف غير صحيح.');
      expect(failure.fieldErrors['code'], 'رمز التحقق مطلوب.');
    });

    test('a 500 never leaks a raw status line to the customer', () {
      final client = ApiClient(tokenStore: store);
      final failure = client.fromResponse(
        Response<String>(
          requestOptions: RequestOptions(),
          statusCode: 503,
          data: '<html>upstream connect error</html>',
        ),
      );

      expect(failure.message, isNot(contains('<')));
      expect(failure.message, isNot(contains('503')));
      expect(failure.isRetriable, isTrue);
    });

    test('timeouts and connection loss become retriable failures', () {
      final client = ApiClient(tokenStore: store);
      final options = RequestOptions();

      expect(
        client
            .translate(
              DioException.connectionTimeout(
                timeout: const Duration(seconds: 1),
                requestOptions: options,
              ),
            )
            .code,
        'REQUEST_TIMEOUT',
      );
      expect(
        client
            .translate(
              DioException.receiveTimeout(
                timeout: const Duration(seconds: 1),
                requestOptions: options,
              ),
            )
            .code,
        'REQUEST_TIMEOUT',
      );
      expect(
        client
            .translate(
              DioException.connectionError(
                requestOptions: options,
                reason: 'socket closed',
              ),
            )
            .code,
        'NETWORK_UNAVAILABLE',
      );
    });
  });

  group('authorization header', () {
    test('is attached to protected endpoints', () async {
      await store.write(_tokens());
      final adapter = _FakeAdapter((_) async => _json(<String, dynamic>{}));
      final client = ApiClient(tokenStore: store, dio: Dio())
        ..raw.httpClientAdapter = adapter;

      await client.raw.get<dynamic>(ApiEndpoints.home);

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer access-1',
      );
    });

    test('is omitted from the OTP endpoints', () async {
      await store.write(_tokens());
      final adapter = _FakeAdapter((_) async => _json(<String, dynamic>{}));
      final client = ApiClient(tokenStore: store, dio: Dio())
        ..raw.httpClientAdapter = adapter;

      await client.raw.post<dynamic>(ApiEndpoints.authVerifyOtp);

      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('every request carries a correlation id', () async {
      final adapter = _FakeAdapter((_) async => _json(<String, dynamic>{}));
      final client = ApiClient(tokenStore: store, dio: Dio())
        ..raw.httpClientAdapter = adapter;

      await client.raw.get<dynamic>(ApiEndpoints.home);

      final id = adapter.requests.single.headers['X-Correlation-ID'] as String?;
      expect(id, isNotNull);
      expect(id, hasLength(16));
    });
  });

  group('token refresh', () {
    test(
      'a 401 triggers one refresh and the original request is replayed',
      () async {
        await store.write(_tokens());
        var homeCalls = 0;
        final adapter = _FakeAdapter((RequestOptions options) async {
          if (options.path == ApiEndpoints.home) {
            homeCalls++;
            final auth = options.headers['Authorization'];
            if (auth == 'Bearer access-2') {
              return _json(<String, dynamic>{'ok': true});
            }
            return _json(<String, dynamic>{
              'code': 'TOKEN_EXPIRED',
            }, status: 401);
          }
          if (options.path == ApiEndpoints.authRefresh) {
            return _json(<String, dynamic>{
              'access_token': 'access-2',
              'refresh_token': 'refresh-2',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'expires_at': DateTime.now()
                  .add(const Duration(hours: 1))
                  .toUtc()
                  .toIso8601String(),
            });
          }
          return _json(<String, dynamic>{}, status: 404);
        });
        final client = ApiClient(tokenStore: store, dio: Dio())
          ..raw.httpClientAdapter = adapter;

        final response = await client.raw.get<dynamic>(ApiEndpoints.home);

        expect(response.statusCode, 200);
        expect(homeCalls, 2);
        expect(adapter.countOf(ApiEndpoints.authRefresh), 1);
        expect(store.tokens!.accessToken, 'access-2');
        expect(store.tokens!.refreshToken, 'refresh-2');
      },
    );

    test('the refresh call itself carries no bearer token', () async {
      await store.write(_tokens());
      final adapter = _FakeAdapter((RequestOptions options) async {
        if (options.path == ApiEndpoints.authRefresh) {
          expect(options.headers.containsKey('Authorization'), isFalse);
          return _json(<String, dynamic>{
            'access_token': 'access-2',
            'refresh_token': 'refresh-2',
            'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          });
        }
        return _json(<String, dynamic>{'code': 'TOKEN_EXPIRED'}, status: 401);
      });
      final client = ApiClient(tokenStore: store, dio: Dio())
        ..raw.httpClientAdapter = adapter;

      await client.raw
          .get<dynamic>(ApiEndpoints.home)
          .catchError(
            (Object _) => Response<dynamic>(requestOptions: RequestOptions()),
          );

      expect(adapter.countOf(ApiEndpoints.authRefresh), 1);
    });

    test(
      'a rejected refresh clears tokens and reports session expiry',
      () async {
        await store.write(_tokens());
        var expired = false;
        final adapter = _FakeAdapter((RequestOptions options) async {
          if (options.path == ApiEndpoints.authRefresh) {
            return _json(<String, dynamic>{
              'code': 'TOKEN_REVOKED',
            }, status: 401);
          }
          return _json(<String, dynamic>{'code': 'TOKEN_EXPIRED'}, status: 401);
        });
        final client = ApiClient(
          tokenStore: store,
          dio: Dio(),
          onSessionExpired: () async => expired = true,
        )..raw.httpClientAdapter = adapter;

        await expectLater(
          client.raw.get<dynamic>(ApiEndpoints.home),
          throwsA(isA<DioException>()),
        );
        await Future<void>.delayed(Duration.zero);

        expect(expired, isTrue);
        expect(store.tokens, isNull);
        // Exactly one refresh attempt: no retry loop.
        expect(adapter.countOf(ApiEndpoints.authRefresh), 1);
      },
    );

    test('concurrent 401s share a single refresh', () async {
      await store.write(_tokens());
      final adapter = _FakeAdapter((RequestOptions options) async {
        if (options.path == ApiEndpoints.authRefresh) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _json(<String, dynamic>{
            'access_token': 'access-2',
            'refresh_token': 'refresh-2',
            'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          });
        }
        if (options.headers['Authorization'] == 'Bearer access-2') {
          return _json(<String, dynamic>{'ok': true});
        }
        return _json(<String, dynamic>{'code': 'TOKEN_EXPIRED'}, status: 401);
      });
      final client = ApiClient(tokenStore: store, dio: Dio())
        ..raw.httpClientAdapter = adapter;

      final results = await Future.wait(<Future<Response<dynamic>>>[
        client.raw.get<dynamic>(ApiEndpoints.home),
        client.raw.get<dynamic>(ApiEndpoints.orders),
        client.raw.get<dynamic>(ApiEndpoints.profile),
      ]);

      expect(
        results.every((Response<dynamic> r) => r.statusCode == 200),
        isTrue,
      );
      expect(adapter.countOf(ApiEndpoints.authRefresh), 1);
    });
  });

  group('pagination', () {
    test('parses the items/meta envelope', () {
      final page = Paginated<String>.fromJson(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'v': 'a'},
          <String, dynamic>{'v': 'b'},
        ],
        'meta': <String, dynamic>{
          'page': 2,
          'per_page': 20,
          'total': 41,
          'total_pages': 3,
          'has_next': true,
          'has_previous': true,
        },
      }, (Map<String, dynamic> json) => json['v'] as String);

      expect(page.items, <String>['a', 'b']);
      expect(page.meta.page, 2);
      expect(page.meta.total, 41);
      expect(page.hasNext, isTrue);
    });

    test('tolerates a missing meta block', () {
      final page = Paginated<int>.fromJson(<String, dynamic>{
        'items': <dynamic>[],
      }, (Map<String, dynamic> json) => 0);

      expect(page.isEmpty, isTrue);
      expect(page.hasNext, isFalse);
      expect(page.meta.totalPages, 0);
    });
  });
}
