import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/core/security/sensitive_data.dart';

void main() {
  group('redactField', () {
    test('masks a value whose key names a credential', () {
      expect(
        SensitiveData.redactField('access_token', 'eyJabc.def.ghi'),
        '[redacted]',
      );
      expect(SensitiveData.redactField('otp', '1234'), '[redacted]');
      expect(
        SensitiveData.redactField('Authorization', 'Bearer x'),
        '[redacted]',
      );
    });

    test('matches keys regardless of case and separators', () {
      expect(SensitiveData.redactField('ACCESS-TOKEN', 'secret'), '[redacted]');
      expect(SensitiveData.redactField('accessToken', 'secret'), '[redacted]');
      expect(SensitiveData.redactField('AccessToken', 'secret'), '[redacted]');
    });

    test('keeps only the tail of personal data', () {
      expect(
        SensitiveData.redactField('phone', '+201001234567'),
        '[redacted](4567)',
      );
    });

    test('redacts free text that slipped past the key check', () {
      expect(
        SensitiveData.redactField('note', 'call +201001234567 back'),
        'call [phone] back',
      );
      expect(
        SensitiveData.redactField('note', 'token eyJhbGciOiJIUzI1NiJ9'),
        contains('[jwt]'),
      );
    });

    test('leaves a harmless status code readable', () {
      expect(SensitiveData.redactField('status', 'HTTP_409'), 'HTTP_409');
    });

    test('renders null', () {
      expect(SensitiveData.redactField('phone', null), 'null');
    });
  });

  group('redactFields', () {
    test('keeps keys readable while dropping secrets', () {
      final result = SensitiveData.redactFields(<String, Object?>{
        'phone': '01001234567',
        'status': 409,
        'refresh_token': 'rt-abc-123',
      });

      expect(result['status'], '409');
      expect(result['refresh_token'], '[redacted]');
      expect(result['phone'], '[redacted](4567)');
    });
  });
}
