import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/features/properties/data/models/property_models.dart';
import 'package:home_services_app/features/requests/data/models/coverage_models.dart';
import 'package:home_services_app/features/requests/data/models/photo_annotation.dart';
import 'package:home_services_app/features/requests/data/models/request_models.dart';
import 'package:home_services_app/features/requests/presentation/controllers/request_wizard_controller.dart';

void main() {
  ProviderContainer container() {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  RequestWizardController wizard(ProviderContainer c) =>
      c.read(requestWizardProvider.notifier);

  group('step gating', () {
    test('step one needs a category', () {
      final ProviderContainer c = container();
      expect(wizard(c).canAdvance(RequestWizardStep.service), isFalse);

      wizard(c).selectCategory(
        const ServiceCategory(
          id: 'cat-1',
          code: 'PLUMBING',
          nameAr: 'سباكة',
          nameEn: 'Plumbing',
        ),
      );
      expect(wizard(c).canAdvance(RequestWizardStep.service), isTrue);
    });

    test('step two enforces the 10 character minimum', () {
      final ProviderContainer c = container();
      wizard(c).setDescription('short');
      expect(wizard(c).canAdvance(RequestWizardStep.details), isFalse);

      wizard(c).setDescription('a long enough problem description');
      expect(wizard(c).canAdvance(RequestWizardStep.details), isTrue);
    });

    test('step two rejects over 4000 characters', () {
      final ProviderContainer c = container();
      wizard(c).setDescription('x' * 4001);
      expect(wizard(c).canAdvance(RequestWizardStep.details), isFalse);
    });

    test('the photo step cannot be skipped because submit needs media', () {
      final ProviderContainer c = container();
      expect(wizard(c).canAdvance(RequestWizardStep.photos), isFalse);

      wizard(c).addPhotos(<PendingPhoto>[
        PendingPhoto(
          localId: 'p1',
          filename: 'a.jpg',
          bytes: _bytes,
          contentType: 'image/jpeg',
        ),
      ]);
      expect(wizard(c).canAdvance(RequestWizardStep.photos), isTrue);
    });

    test('the location step needs a submittable address', () {
      final ProviderContainer c = container();
      expect(wizard(c).canAdvance(RequestWizardStep.location), isFalse);

      wizard(c).updateAddress(
        const AddressSnapshot(
          governorate: 'Cairo',
          city: 'Nasr City',
          latitude: 30.0444,
          longitude: 31.2357,
          zoneCode: 'cairo',
        ),
      );
      expect(wizard(c).canAdvance(RequestWizardStep.location), isTrue);
    });

    test('a typed city without a picked area cannot advance', () {
      final ProviderContainer c = container();
      // The old form accepted free text here, which is exactly what let a
      // request through to a 422 OUT_OF_COVERAGE at submit time.
      wizard(c).updateAddress(
        const AddressSnapshot(
          governorate: 'دمياط',
          city: 'دمياط الجديدة',
          latitude: 31.15,
          longitude: 31.4167,
        ),
      );
      expect(wizard(c).canAdvance(RequestWizardStep.location), isFalse);
    });

    test('an address without coordinates is not submittable', () {
      final ProviderContainer c = container();
      wizard(c).updateAddress(
        const AddressSnapshot(
          governorate: 'Cairo',
          city: 'Nasr City',
          latitude: 0,
          longitude: 0,
        ),
      );
      expect(wizard(c).canAdvance(RequestWizardStep.location), isFalse);
    });

    test('a half filled contact pair blocks the location step', () {
      final ProviderContainer c = container();
      wizard(c).updateAddress(
        const AddressSnapshot(
          governorate: 'Cairo',
          city: 'Nasr City',
          latitude: 30.0444,
          longitude: 31.2357,
          zoneCode: 'cairo',
          contactName: 'Mona',
        ),
      );
      expect(wizard(c).canAdvance(RequestWizardStep.location), isFalse);

      wizard(c).updateAddress(
        const AddressSnapshot(
          governorate: 'Cairo',
          city: 'Nasr City',
          latitude: 30.0444,
          longitude: 31.2357,
          zoneCode: 'cairo',
          contactName: 'Mona',
          contactPhone: '01000000000',
        ),
      );
      expect(wizard(c).canAdvance(RequestWizardStep.location), isTrue);
    });
  });

  group('coverage zone selection', () {
    const CoverageZone damiettaNew = CoverageZone(
      id: 'zone-2',
      code: 'damietta_new',
      nameAr: 'دمياط الجديدة',
      governorate: 'Damietta',
      city: 'New Damietta',
      centerLatitude: 31.15,
      centerLongitude: 31.4167,
      radiusKm: 18,
    );

    test('the picked area supplies the code the backend matches on', () {
      final ProviderContainer c = container();
      wizard(c).updateAddress(
        const AddressSnapshot(
          governorate: 'dمياط',
          city: 'دمياط الجديدة',
          latitude: 31.15,
          longitude: 31.4167,
        ),
      );

      wizard(c).selectCoverageZone(damiettaNew);

      final AddressSnapshot? address = c.read(requestWizardProvider).address;
      expect(address?.zoneCode, 'damietta_new');
      expect(address?.zone, 'دمياط الجديدة');
      // Arabic is what the customer reads; the canonical English pair is what
      // the backend matches on when no coordinates are available.
      expect(address?.governorate, 'Damietta');
      expect(address?.city, 'New Damietta');
      expect(wizard(c).canAdvance(RequestWizardStep.location), isTrue);
    });

    test('picking an area does not move the point to its centre', () {
      final ProviderContainer c = container();
      wizard(c).updateAddress(
        const AddressSnapshot(
          governorate: 'Cairo',
          city: 'Nasr City',
          latitude: 30.0444,
          longitude: 31.2357,
        ),
      );

      wizard(c).selectCoverageZone(damiettaNew);

      final AddressSnapshot? address = c.read(requestWizardProvider).address;
      // The zone says where the platform serves, not where the work happens.
      expect(address?.latitude, 30.0444);
      expect(address?.longitude, 31.2357);
    });

    test('an area without a point stays unsubmitable', () {
      final ProviderContainer c = container();
      wizard(c).updateAddress(
        const AddressSnapshot(
          governorate: 'Cairo',
          city: 'Nasr City',
          latitude: 0,
          longitude: 0,
        ),
      );

      wizard(c).selectCoverageZone(damiettaNew);

      expect(c.read(requestWizardProvider).address?.zoneCode, 'damietta_new');
      expect(wizard(c).canAdvance(RequestWizardStep.location), isFalse);
    });

    test('an area picked before any property is ignored', () {
      final ProviderContainer c = container();
      wizard(c).selectCoverageZone(damiettaNew);
      expect(c.read(requestWizardProvider).address, isNull);
    });
  });

  group('inspection only and urgency', () {
    test(
      'the backend rejects inspection-only with urgent, so it downgrades',
      () {
        final ProviderContainer c = container();
        wizard(c).setUrgency('URGENT');
        expect(c.read(requestWizardProvider).isUrgent, isTrue);

        wizard(c).setInspectionOnly(true);
        expect(c.read(requestWizardProvider).effectiveUrgency, 'NORMAL');
      },
    );

    test('normal urgency is untouched by inspection-only', () {
      final ProviderContainer c = container();
      wizard(c).setInspectionOnly(true);
      expect(c.read(requestWizardProvider).effectiveUrgency, 'NORMAL');
    });
  });

  group('photo limits', () {
    test('addPhotos stops at the server cap instead of overflowing', () {
      final ProviderContainer c = container();
      wizard(c).addPhotos(
        List<PendingPhoto>.generate(
          RequestMedia.maxPerRequest + 4,
          (int i) => PendingPhoto(
            localId: 'p$i',
            filename: '$i.jpg',
            bytes: _bytes,
            contentType: 'image/jpeg',
          ),
        ),
      );

      expect(
        c.read(requestWizardProvider).photos.length,
        RequestMedia.maxPerRequest,
      );
    });

    test('removePhoto drops one photo by id', () {
      final ProviderContainer c = container();
      wizard(c).addPhotos(<PendingPhoto>[
        PendingPhoto(
          localId: 'keep',
          filename: 'a.jpg',
          bytes: _bytes,
          contentType: 'image/jpeg',
        ),
        PendingPhoto(
          localId: 'drop',
          filename: 'b.jpg',
          bytes: _bytes,
          contentType: 'image/jpeg',
        ),
      ]);

      wizard(c).removePhoto('drop');
      final List<PendingPhoto> photos = c.read(requestWizardProvider).photos;
      expect(photos, hasLength(1));
      expect(photos.single.localId, 'keep');
    });
  });

  group('canSubmit and blockers', () {
    RequestWizardController complete(ProviderContainer c) {
      final RequestWizardController w = wizard(c);
      w.selectCategory(
        const ServiceCategory(
          id: 'cat-1',
          code: 'PLUMBING',
          nameAr: 'سباكة',
          nameEn: 'Plumbing',
        ),
      );
      w.selectProperty(
        const Property(
          id: 'prop-1',
          label: 'Home',
          city: 'Nasr City',
          governorate: 'Cairo',
          latitude: 30.0444,
          longitude: 31.2357,
        ),
      );
      // A property supplies the point but not the served area, so a complete
      // wizard has to pick one from the coverage list as well.
      w.selectCoverageZone(
        const CoverageZone(
          id: 'zone-1',
          code: 'cairo',
          nameAr: 'القاهرة',
          governorate: 'Cairo',
          city: 'Cairo',
          centerLatitude: 30.0444,
          centerLongitude: 31.2357,
          radiusKm: 40,
        ),
      );
      w.setDescription('the tap is leaking badly');
      w.addPhotos(<PendingPhoto>[
        PendingPhoto(
          localId: 'p1',
          filename: 'a.jpg',
          bytes: _bytes,
          contentType: 'image/jpeg',
        ),
      ]);
      return w;
    }

    test('a fully answered wizard can submit', () {
      final ProviderContainer c = container();
      complete(c);

      final RequestWizardState state = c.read(requestWizardProvider);
      expect(state.blockers, isEmpty);
      expect(state.canSubmit, isTrue);
    });

    test('blockers name each missing piece', () {
      final ProviderContainer c = container();
      final RequestWizardState state = c.read(requestWizardProvider);

      expect(state.blockers, contains('service'));
      expect(state.blockers, contains('location'));
      expect(state.blockers, contains('details'));
      expect(state.blockers, contains('photos'));
      expect(state.canSubmit, isFalse);
    });

    test('removing a photo closes the submit gate again', () {
      final ProviderContainer c = container();
      complete(c);
      expect(c.read(requestWizardProvider).canSubmit, isTrue);

      // This is the guard against the 400 that `POST /requests/{id}/submit`
      // returns when media_count is zero.
      wizard(c).removePhoto('p1');
      expect(c.read(requestWizardProvider).canSubmit, isFalse);
    });
  });

  group('photo annotations', () {
    test('freehand marks normalize to 0..1 payload geometry', () {
      final PhotoAnnotation mark = PhotoAnnotation.freehand(const <Offset>[
        Offset(0.1, 0.2),
        Offset(0.4, 0.5),
      ]);

      expect(mark.type, 'freehand');
      final Map<String, dynamic> payload = mark.toPayload();
      expect(payload['annotation_type'], 'freehand');
      final List<dynamic> points =
          (payload['geometry'] as Map<String, dynamic>)['points']
              as List<dynamic>;
      expect(points, hasLength(2));
      expect((points.first as Map<String, dynamic>)['x'], 0.1);
    });

    test('a note is only sent when it has content', () {
      final PhotoAnnotation without = PhotoAnnotation.circle(
        const Offset(0.5, 0.5),
        0.2,
      );
      expect(without.toPayload().containsKey('note'), isFalse);

      final PhotoAnnotation withNote = PhotoAnnotation.circle(
        const Offset(0.5, 0.5),
        0.2,
        note: '  the leak  ',
      );
      expect(withNote.toPayload()['note'], 'the leak');
    });

    test('setPhotoAnnotations replaces marks on just one photo', () {
      final ProviderContainer c = container();
      wizard(c).addPhotos(<PendingPhoto>[
        PendingPhoto(
          localId: 'p1',
          filename: 'a.jpg',
          bytes: _bytes,
          contentType: 'image/jpeg',
        ),
        PendingPhoto(
          localId: 'p2',
          filename: 'b.jpg',
          bytes: _bytes,
          contentType: 'image/jpeg',
        ),
      ]);

      wizard(c).setPhotoAnnotations('p1', <PhotoAnnotation>[
        PhotoAnnotation.freehand(const <Offset>[Offset(0.1, 0.1)]),
      ]);

      final List<PendingPhoto> photos = c.read(requestWizardProvider).photos;
      expect(
        photos.firstWhere((PendingPhoto p) => p.localId == 'p1').annotations,
        hasLength(1),
      );
      expect(
        photos.firstWhere((PendingPhoto p) => p.localId == 'p2').annotations,
        isEmpty,
      );
    });

    test('removing a photo drops its marks with it', () {
      final ProviderContainer c = container();
      wizard(c).addPhotos(<PendingPhoto>[
        PendingPhoto(
          localId: 'p1',
          filename: 'a.jpg',
          bytes: _bytes,
          contentType: 'image/jpeg',
        ),
      ]);
      wizard(c).setPhotoAnnotations('p1', <PhotoAnnotation>[
        PhotoAnnotation.circle(const Offset(0.5, 0.5), 0.2),
      ]);

      wizard(c).removePhoto('p1');
      expect(c.read(requestWizardProvider).photos, isEmpty);
    });
  });

  group('route mapping', () {
    test('every step maps to a distinct route', () {
      final Set<String> routes = RequestWizardStep.values
          .map(RequestWizardController.routeFor)
          .toSet();

      expect(routes, hasLength(RequestWizardStep.values.length));
    });
  });
}

final _bytes = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]);
