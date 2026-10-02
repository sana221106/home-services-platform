import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/features/properties/data/models/property_models.dart';
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
        ),
      );
      expect(wizard(c).canAdvance(RequestWizardStep.location), isTrue);
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
          contactName: 'Mona',
          contactPhone: '01000000000',
        ),
      );
      expect(wizard(c).canAdvance(RequestWizardStep.location), isTrue);
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
