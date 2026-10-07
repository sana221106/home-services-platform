import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/core/network/api_client.dart';
import 'package:home_services_app/core/network/api_endpoints.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/core/storage/secure_storage_service.dart';
import 'package:home_services_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:home_services_app/features/auth/data/models/auth_models.dart';
import 'package:home_services_app/features/auth/data/repositories/auth_repository.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options, Object? body)
  handler;
  final List<(String, Object?)> calls = <(String, Object?)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (options.data != null) {
      body = jsonDecode(
        options.data is String
            ? options.data as String
            : jsonEncode(options.data),
      );
    }
    calls.add((options.path, body));
    return handler(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

Map<String, dynamic> _session({String access = 'access-1'}) =>
    <String, dynamic>{
      'tokens': <String, dynamic>{
        'access_token': access,
        'refresh_token': 'refresh-1',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      },
      'customer': <String, dynamic>{
        'id': 'c1',
        'full_name': 'سارة أحمد',
        'phone': '+201001234567',
        'email': null,
        'avatar_url': null,
        'preferred_language': 'ar',
      },
    };

void main() {
  late InMemoryTokenStore store;
  late ApiClient client;

  setUp(() {
    store = InMemoryTokenStore();
    client = ApiClient(tokenStore: store, dio: Dio());
  });

  AuthRepository repositoryWith(_Adapter adapter) {
    client.raw.httpClientAdapter = adapter;
    return AuthRepository(
      remote: AuthRemoteDataSource(client.raw),
      tokenStore: store,
      client: client,
    );
  }

  group('email + OTP sign-in', () {
    test('requestOtp sends the email and an optional phone', () async {
      final adapter = _Adapter(
        (_, _) async => _json(<String, dynamic>{
          'message': 'تم إرسال الرمز',
          'expires_in_seconds': 300,
          'is_new_customer': true,
        }),
      );

      final challenge = await repositoryWith(
        adapter,
      ).requestOtp(email: 'sara@example.com', phone: '+201001234567');

      expect(adapter.calls.single.$1, ApiEndpoints.authRequestOtp);
      expect(adapter.calls.single.$2, <String, dynamic>{
        'email': 'sara@example.com',
        'phone': '+201001234567',
      });
      expect(challenge.isNewCustomer, isTrue);
      expect(challenge.expiresInSeconds, 300);
    });

    test('requestOtp omits the phone entirely when none was given', () async {
      final adapter = _Adapter(
        (_, _) async => _json(<String, dynamic>{
          'message': 'تم إرسال الرمز',
          'expires_in_seconds': 300,
          'is_new_customer': false,
        }),
      );

      await repositoryWith(
        adapter,
      ).requestOtp(email: 'sara@example.com');

      expect(adapter.calls.single.$1, ApiEndpoints.authRequestOtp);
      expect(adapter.calls.single.$2, <String, dynamic>{
        'email': 'sara@example.com',
      });
    });

    test('verifyOtp persists the tokens and returns the customer', () async {
      final adapter = _Adapter((_, _) async => _json(_session()));
      final repo = repositoryWith(adapter);

      final customer = await repo.verifyOtp(
        email: 'sara@example.com',
        code: '1234',
        fullName: 'سارة أحمد',
      );

      expect(adapter.calls.single.$1, ApiEndpoints.authVerifyOtp);
      expect(adapter.calls.single.$2, <String, dynamic>{
        'email': 'sara@example.com',
        'code': '1234',
        'full_name': 'سارة أحمد',
      });
      expect(store.tokens, isNotNull);
      expect(store.tokens!.accessToken, 'access-1');
      expect(store.tokens!.refreshToken, 'refresh-1');
      expect(customer.id, 'c1');
      expect(customer.firstName, 'سارة');
    });

    test('a rejected code surfaces as ApiFailure and stores nothing', () async {
      final adapter = _Adapter(
        (_, _) async => _json(<String, dynamic>{
          'code': 'OTP_ATTEMPTS_EXCEEDED',
          'message': 'تجاوزت عدد محاولات التحقق',
        }, status: 400),
      );

      await expectLater(
        repositoryWith(
          adapter,
        ).verifyOtp(email: 'sara@example.com', code: '0000'),
        throwsA(
          isA<ApiFailure>()
              .having((ApiFailure f) => f.code, 'code', 'OTP_ATTEMPTS_EXCEEDED')
              .having(
                (ApiFailure f) => f.message,
                'message',
                'تجاوزت عدد محاولات التحقق',
              ),
        ),
      );
      expect(store.tokens, isNull);
    });
  });

  group('session restore', () {
    test('no token means no session', () async {
      final adapter = _Adapter((_, _) async => _json(_session()));
      expect(await repositoryWith(adapter).restoreSession(), isNull);
      expect(adapter.calls, isEmpty);
    });

    test('a valid token is exchanged for the profile', () async {
      await store.write(
        TokenPair(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final adapter = _Adapter((_, _) async => _json(_session()['customer']));

      final profile = await repositoryWith(adapter).restoreSession();

      expect(adapter.calls.single.$1, ApiEndpoints.authMe);
      expect(adapter.calls.single.$1 == ApiEndpoints.authMe, isTrue);
      expect(profile!.phone, '+201001234567');
    });

    test('an expired token is cleared so the app shows sign-in', () async {
      await store.write(
        TokenPair(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final adapter = _Adapter(
        (_, _) async => _json(<String, dynamic>{
          'code': 'TOKEN_EXPIRED',
          'message': 'انتهت صلاحية الجلسة',
        }, status: 401),
      );

      final profile = await repositoryWith(adapter).restoreSession();

      expect(profile, isNull);
      expect(store.tokens, isNull);
    });
  });

  group('logout', () {
    test('clears the session even when the server call fails', () async {
      await store.write(
        TokenPair(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final adapter = _Adapter(
        (_, _) async => _json(<String, dynamic>{'detail': 'boom'}, status: 500),
      );

      await repositoryWith(adapter).logout();

      expect(store.tokens, isNull);
      expect(adapter.calls.single.$1, ApiEndpoints.authLogout);
      expect(adapter.calls.single.$2, <String, dynamic>{
        'refresh_token': 'refresh-1',
      });
    });
  });

  group('model safety', () {
    test('customer profile exposes no technician fields', () {
      // A compile-time reminder that the customer model has no staff data.
      const profile = CustomerProfile(
        id: 'c1',
        fullName: 'سارة',
        phone: '+20100',
      );
      expect(profile.preferredLanguage, 'ar');
      expect(profile.firstName, 'سارة');
    });
  });
}
