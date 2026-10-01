import 'package:home_services_app/core/utils/phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneNumber.normalize', () {
    test('converts a local Egyptian number to E.164', () {
      expect(PhoneNumber.normalize('01001234567'), '+201001234567');
    });

    test('keeps a number that already has the country code', () {
      expect(PhoneNumber.normalize('+201001234567'), '+201001234567');
    });

    test('strips separators the customer actually types', () {
      expect(PhoneNumber.normalize(' 0100 123 4567 '), '+201001234567');
      expect(PhoneNumber.normalize('(0100) 123-4567'), '+201001234567');
    });

    test('treats a 00 international prefix as a plus sign', () {
      expect(PhoneNumber.normalize('00201001234567'), '+201001234567');
    });

    test('rejects input that cannot be a phone number', () {
      expect(PhoneNumber.normalize(''), isNull);
      expect(PhoneNumber.normalize('   '), isNull);
      expect(PhoneNumber.normalize('12345'), isNull);
      expect(PhoneNumber.normalize('not a number'), isNull);
    });

    test('honours a caller-supplied dial code', () {
      expect(
        PhoneNumber.normalize('01001234567', dialCode: '+966'),
        '+9661001234567',
      );
    });
  });
}
