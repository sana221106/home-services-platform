import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/core/errors/app_exception.dart';
import 'package:home_services_app/core/errors/error_mapper.dart';

Response<Map<String, dynamic>> _response({
  required int status,
  Map<String, dynamic>? data,
  String? correlationId,
}) {
  return Response<Map<String, dynamic>>(
    requestOptions: RequestOptions(),
    statusCode: status,
    data: data,
    headers: correlationId == null
        ? Headers.fromMap(<String, List<String>>{})
        : Headers.fromMap(<String, List<String>>{
            'X-Correlation-ID': <String>[correlationId],
          }),
  );
}

void main() {
  group('failureFromResponse keeps diagnostics for every code', () {
    test(
      'a 409 domain refusal still carries its correlation id and details',
      () {
        final failure = ErrorMapper.failureFromResponse(
          _response(
            status: 409,
            correlationId: 'abc123',
            data: <String, dynamic>{
              'code': 'INVALID_STATE_TRANSITION',
              'message': 'لا يمكن الإلغاء بعد التأكيد.',
              'details': <String, dynamic>{'from': 'CONFIRMED'},
            },
          ),
        );

        expect(failure.code, 'INVALID_STATE_TRANSITION');
        expect(failure.correlationId, 'abc123');
        expect(failure.details['from'], 'CONFIRMED');
        expect(failure.isConflict, isTrue);
      },
    );

    test('a 422 validation failure still carries field errors', () {
      final failure = ErrorMapper.failureFromResponse(
        _response(
          status: 422,
          correlationId: 'v-1',
          data: <String, dynamic>{
            'code': 'VALIDATION_ERROR',
            'message': 'بيانات غير صحيحة.',
            'details': <String, dynamic>{
              'phone': 'رقم الهاتف غير صحيح.',
              'code': <String>['الرمز غير صحيح.'],
            },
          },
        ),
      );

      expect(failure.fieldErrors['phone'], 'رقم الهاتف غير صحيح.');
      // A list value is flattened to its first entry for a form field.
      expect(failure.fieldErrors['code'], 'الرمز غير صحيح.');
      expect(failure.correlationId, 'v-1');
    });

    test('falls back to a derived code and message when the body is empty', () {
      final failure = ErrorMapper.failureFromResponse(_response(status: 404));

      expect(failure.code, 'NOT_FOUND');
      expect(failure.message, isNotEmpty);
      expect(failure.isNotFound, isTrue);
    });
  });

  group('exceptionFromResponse picks the typed exception', () {
    test('401 becomes UnauthorisedException', () {
      final error = ErrorMapper.exceptionFromResponse(
        _response(
          status: 401,
          data: <String, dynamic>{
            'code': 'TOKEN_EXPIRED',
            'message': 'انتهت صلاحية الجلسة.',
          },
        ),
      );

      expect(error, isA<UnauthorisedException>());
    });

    test('422 becomes ValidationException', () {
      final error = ErrorMapper.exceptionFromResponse(
        _response(
          status: 422,
          data: <String, dynamic>{
            'code': 'VALIDATION_ERROR',
            'message': 'بيانات غير صحيحة.',
          },
        ),
      );

      expect(error, isA<ValidationException>());
    });

    test('a business-rule refusal keeps the structured details', () {
      final error = ErrorMapper.exceptionFromResponse(
        _response(
          status: 409,
          data: <String, dynamic>{
            'code': 'NOT_CANCELLABLE',
            'message': 'لا يمكن الإلغاء.',
            'details': <String, dynamic>{'policy': 'LATE_CANCELLATION'},
          },
        ),
      );

      expect(error, isA<DomainRuleException>());
      expect(
        (error as DomainRuleException).details['policy'],
        'LATE_CANCELLATION',
      );
    });

    test('an unknown 5xx stays a ServerException', () {
      final error = ErrorMapper.exceptionFromResponse(_response(status: 503));

      expect(error, isA<ServerException>());
    });
  });

  group('toFailure without a response', () {
    test('a transport timeout is retriable', () {
      final failure = ErrorMapper.toFailure(
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 15),
          requestOptions: RequestOptions(),
        ),
      );

      expect(failure.code, 'REQUEST_TIMEOUT');
      expect(failure.isRetriable, isTrue);
      expect(failure.statusCode, isNull);
    });

    test('a cancelled request is reported as cancelled', () {
      final failure = ErrorMapper.toFailure(
        DioException.requestCancelled(
          reason: 'superseded by pull-to-refresh',
          requestOptions: RequestOptions(),
        ),
      );

      expect(failure.code, 'REQUEST_CANCELLED');
    });
  });
}
