import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/features/requests/data/models/coverage_models.dart';

void main() {
  group('CoverageZone', () {
    test('parses the customer-facing shape', () {
      final CoverageZone zone = CoverageZone.fromJson(<String, dynamic>{
        'id': 'z-1',
        'code': 'damietta_new',
        'name_ar': 'دمياط الجديدة',
        'governorate': 'Damietta',
        'city': 'New Damietta',
        'district': 'دمياط الجديدة',
        'center_latitude': '31.150000',
        'center_longitude': '31.416700',
        'radius_km': '18.00',
      });

      expect(zone.code, 'damietta_new');
      expect(zone.nameAr, 'دمياط الجديدة');
      expect(zone.city, 'New Damietta');
      expect(zone.centerLatitude, 31.15);
      expect(zone.radiusKm, 18.0);
    });

    test('survives a missing optional district', () {
      final CoverageZone zone = CoverageZone.fromJson(<String, dynamic>{
        'id': 'z-2',
        'code': 'cai',
        'name_ar': 'القاهرة',
        'governorate': 'Cairo',
        'city': 'Cairo',
        'center_latitude': 30.0444,
        'center_longitude': 31.2357,
      });

      expect(zone.district, isNull);
      expect(zone.radiusKm, 0);
    });

    test('a zone the server reports without a centre still parses', () {
      // `GET /coverage-zones` sends null rather than 0,0 for a centre-less area,
      // because 0,0 would read as a real point in the Gulf of Guinea.
      final CoverageZone zone = CoverageZone.fromJson(<String, dynamic>{
        'id': 'z-3',
        'code': 'NOWHERE',
        'name_ar': 'بلا مركز',
        'governorate': 'Nowhere',
        'city': 'Nowhere',
        'center_latitude': null,
        'center_longitude': null,
        'radius_km': null,
      });

      expect(zone.code, 'NOWHERE');
      expect(zone.centerLatitude, 0);
      expect(zone.radiusKm, 0);
    });
  });

  group('AddressSuggestion', () {
    test('reads a hit that is inside coverage', () {
      final AddressSuggestion hit = AddressSuggestion.fromJson(<String, dynamic>{
        'display_name': 'شارع التحرير، القاهرة',
        'latitude': 30.0444,
        'longitude': 31.2357,
        'street': 'شارع التحرير',
        'city': 'القاهرة',
        'zone_code': 'cai',
        'zone_name_ar': 'القاهرة',
      });

      expect(hit.isOutsideCoverage, isFalse);
      expect(hit.zoneNameAr, 'القاهرة');
    });

    test('flags a hit the platform does not serve', () {
      // The honest signal: selecting this fills the address but must not pass
      // for a serviceable one (§30).
      final AddressSuggestion hit = AddressSuggestion.fromJson(<String, dynamic>{
        'display_name': 'أسوان',
        'latitude': 24.0889,
        'longitude': 32.8998,
        'zone_code': null,
      });

      expect(hit.isOutsideCoverage, isTrue);
    });

    test('an empty zone code counts as outside coverage', () {
      const AddressSuggestion hit = AddressSuggestion(
        displayName: 'مكان',
        latitude: 24.0,
        longitude: 32.0,
        zoneCode: '',
      );

      expect(hit.isOutsideCoverage, isTrue);
    });
  });
}
