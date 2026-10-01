import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/core/network/json_readers.dart';
import 'package:home_services_app/features/requests/data/models/request_models.dart';

/// `GET /catalogue` returns bare arrays, not an envelope.
///
/// The list datasource parses with `mapList('items')`, which throws a type
/// error when handed a `List`. These tests pin the two shapes the backend can
/// produce so the choice between them is a deliberate one rather than a guess
/// discovered on device.
void main() {
  group('catalogue response shapes', () {
    test('the catalogue endpoints are read as bare arrays', () {
      // `GET /services`, `/catalogue` and `/services/{id}/problems` all declare
      // `response_model=list[...]`, so there is no `items` key to unwrap. This
      // is the payload shape `ApiClient.getList` is built for.
      const Map<String, dynamic> item = <String, dynamic>{
        'id': 'cat-1',
        'code': 'PLUMBING',
        'name_ar': 'سباكة',
        'name_en': 'Plumbing',
      };
      final List<Map<String, dynamic>> body = <Map<String, dynamic>>[item];

      expect(body, hasLength(1));
      expect(ServiceCategory.fromJson(body.first).code, 'PLUMBING');
    });

    test('an enveloped response is unwrapped by mapList', () {
      final Map<String, dynamic> enveloped = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'cat-1',
            'code': 'PLUMBING',
            'name_ar': 'سباكة',
            'name_en': 'Plumbing',
          },
        ],
      };

      final List<dynamic> items = enveloped.mapList('items');
      expect(items, hasLength(1));
      expect(
        ServiceCategory.fromJson(items.first as Map<String, dynamic>).code,
        'PLUMBING',
      );
    });
  });

  group('AddressSnapshot', () {
    test('submits when the required fields are present', () {
      const AddressSnapshot address = AddressSnapshot(
        governorate: 'Cairo',
        city: 'Nasr City',
        latitude: 30.0444,
        longitude: 31.2357,
      );

      expect(address.isSubmittable, isTrue);
      expect(address.contactPairIsValid, isTrue);
    });

    test('does not submit without coordinates', () {
      const AddressSnapshot address = AddressSnapshot(
        governorate: 'Cairo',
        city: 'Nasr City',
        latitude: 0,
        longitude: 0,
      );

      expect(address.isSubmittable, isFalse);
    });

    test('a contact name without a phone is rejected', () {
      const AddressSnapshot address = AddressSnapshot(
        governorate: 'Cairo',
        city: 'Nasr City',
        latitude: 30.0444,
        longitude: 31.2357,
        contactName: 'Mona',
      );

      expect(address.contactPairIsValid, isFalse);
    });

    test('copyWith clears optional fields explicitly', () {
      const AddressSnapshot address = AddressSnapshot(
        governorate: 'Cairo',
        city: 'Nasr City',
        latitude: 30.0444,
        longitude: 31.2357,
        zone: 'Zone 1',
        contactName: 'Mona',
        contactPhone: '01000000000',
      );

      // An empty string must mean "remove this", not "keep the old value",
      // which is why the model carries clear flags.
      final AddressSnapshot cleared = address.copyWith(
        clearZone: true,
        clearContactName: true,
        clearContactPhone: true,
      );

      expect(cleared.zone, isNull);
      expect(cleared.contactName, isNull);
      expect(cleared.contactPhone, isNull);
      expect(cleared.governorate, 'Cairo');
    });

    test('an empty string does not overwrite an existing value', () {
      const AddressSnapshot address = AddressSnapshot(
        governorate: 'Cairo',
        city: 'Nasr City',
        latitude: 30.0444,
        longitude: 31.2357,
        zone: 'Zone 1',
      );

      expect(address.copyWith().zone, 'Zone 1');
    });
  });

  group('ServiceRequest parsing', () {
    test('reads the fields the list card renders', () {
      final ServiceRequest request = ServiceRequest.fromJson(<String, dynamic>{
        'id': 'req-1',
        'reference_code': 'HS-1001',
        'status': 'QUOTE_SENT',
        'urgency': 'URGENT',
        'inspection_only': false,
        'inspection_required': false,
        'problem_description': 'Leaking tap',
        'created_at': '2026-02-01T10:00:00Z',
        'category_name_ar': 'سباكة',
        'address_summary_ar': 'القاهرة، مدينة نصر',
        'media_count': 2,
        'has_unread_updates': true,
      });

      expect(request.referenceCode, 'HS-1001');
      expect(request.status, 'QUOTE_SENT');
      expect(request.isUrgent, isTrue);
      expect(request.mediaCount, 2);
      expect(request.hasUnreadUpdates, isTrue);
    });

    test('falls back to the category when there is no problem type', () {
      final ServiceRequest withProblem =
          ServiceRequest.fromJson(<String, dynamic>{
            'id': 'req-1',
            'reference_code': 'HS-1',
            'status': 'SUBMITTED',
            'urgency': 'NORMAL',
            'inspection_only': false,
            'inspection_required': false,
            'problem_description': 'x',
            'created_at': '2026-02-01T10:00:00Z',
            'category_name_ar': 'سباكة',
            'problem_name_ar': 'تسريب',
          });

      expect(withProblem.displayTitle, 'تسريب');

      final ServiceRequest withoutProblem =
          ServiceRequest.fromJson(<String, dynamic>{
            'id': 'req-2',
            'reference_code': 'HS-2',
            'status': 'SUBMITTED',
            'urgency': 'NORMAL',
            'inspection_only': false,
            'inspection_required': false,
            'problem_description': 'x',
            'created_at': '2026-02-01T10:00:00Z',
            'category_name_ar': 'سباكة',
          });

      expect(withoutProblem.displayTitle, 'سباكة');
    });
  });
}
