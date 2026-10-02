import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/features/properties/data/models/property_models.dart';
import 'package:home_services_app/features/properties/data/repositories/properties_repository.dart';
import 'package:home_services_app/features/properties/presentation/controllers/properties_controller.dart';
import 'package:home_services_app/features/properties/presentation/controllers/property_detail_controller.dart';
import 'package:home_services_app/features/properties/presentation/pages/property_detail_page.dart';
import 'package:home_services_app/features/properties/presentation/pages/property_new_page.dart';

void main() {
  group('Property model', () {
    test('parses the flat PropertyResponse shape', () {
      final Property property = Property.fromJson(<String, dynamic>{
        'id': 'p1',
        'label': 'Main apartment',
        'property_type': 'apartment',
        'governorate': 'Cairo',
        'city': 'Nasr City',
        'district': 'Hay El Asher',
        'street': 'Abbas El Akkad',
        'building': '12',
        'floor': '3',
        'latitude': 30.0561,
        'longitude': 31.3300,
        'is_default': true,
      });

      expect(property.label, 'Main apartment');
      expect(property.propertyType, 'apartment');
      expect(property.street, 'Abbas El Akkad');
      expect(property.hasCoordinates, isTrue);
      expect(property.displayAddress, contains('Cairo'));
    });

    test('treats the 0,0 pair as no location', () {
      final Property property = Property.fromJson(<String, dynamic>{
        'id': 'p1',
        'latitude': 0,
        'longitude': 0,
      });
      expect(property.hasCoordinates, isFalse);
    });
  });

  group('PropertiesController', () {
    test('load exposes the bare list from the endpoint', () async {
      final _FakePropertiesRepository repository = _FakePropertiesRepository()
        ..items = <Property>[_property()];
      final ProviderContainer container = _container(repository);

      await container.read(propertiesProvider.notifier).load();

      expect(container.read(propertiesProvider).properties, hasLength(1));
      expect(container.read(propertiesProvider).status, PropertiesStatus.ready);
    });

    test('create appends the returned property', () async {
      final _FakePropertiesRepository repository = _FakePropertiesRepository();
      final ProviderContainer container = _container(repository);

      final Property? created = await container
          .read(propertiesProvider.notifier)
          .create(
            label: 'New',
            governorate: 'Cairo',
            city: 'Cairo',
            latitude: 30.0,
            longitude: 31.0,
          );

      expect(created, isNotNull);
      expect(container.read(propertiesProvider).properties, hasLength(1));
      expect(repository.lastCreateLabel, 'New');
    });
  });

  group('PropertyDetailController', () {
    test('load failure surfaces the message', () async {
      final _FakePropertiesRepository repository = _FakePropertiesRepository()
        ..loadError = const ApiFailure(code: 'NOT_FOUND', message: 'Gone');
      final ProviderContainer container = _container(repository);
      final provider = propertyDetailProvider('p1');

      await container.read(provider.notifier).load();

      expect(container.read(provider).status, PropertyDetailStatus.failed);
      expect(container.read(provider).error, 'Gone');
    });

    test('setDefault promotes the property', () async {
      final _FakePropertiesRepository repository = _FakePropertiesRepository();
      final ProviderContainer container = _container(repository);
      final provider = propertyDetailProvider('p1');

      await container.read(provider.notifier).load();
      final bool ok = await container.read(provider.notifier).setDefault();

      expect(ok, isTrue);
      expect(repository.lastUpdateIsDefault, isTrue);
      expect(container.read(provider).property!.isDefault, isTrue);
    });

    test('remove marks the state deleted', () async {
      final _FakePropertiesRepository repository = _FakePropertiesRepository();
      final ProviderContainer container = _container(repository);
      final provider = propertyDetailProvider('p1');

      await container.read(provider.notifier).load();
      final bool ok = await container.read(provider.notifier).remove();

      expect(ok, isTrue);
      expect(container.read(provider).deleted, isTrue);
    });
  });

  group('PropertyDetailPage', () {
    testWidgets('renders the address and the history action', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        await _wrap(repository: _FakePropertiesRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main apartment'), findsOneWidget);
      expect(find.byKey(const Key('property-history-link')), findsOneWidget);
    });

    testWidgets('delete asks for confirmation and archives', (
      WidgetTester tester,
    ) async {
      final _FakePropertiesRepository repository = _FakePropertiesRepository();
      await tester.pumpWidget(await _wrap(repository: repository));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('property-delete')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('property-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this property?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('property-delete-confirm')));
      await tester.pumpAndSettle();

      expect(repository.deleted, isTrue);
    });
  });

  group('PropertyNewPage', () {
    testWidgets('blocks save until the required fields are filled', (
      WidgetTester tester,
    ) async {
      final _FakePropertiesRepository repository = _FakePropertiesRepository();
      await tester.pumpWidget(
        await _wrap(repository: repository, newProperty: true),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('property-save')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('property-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, 0);
    });
  });
}

Property _property({
  String id = 'p1',
  bool isDefault = false,
  List<PropertyContact> contacts = const <PropertyContact>[],
}) {
  return Property(
    id: id,
    label: 'Main apartment',
    propertyType: 'apartment',
    governorate: 'Cairo',
    city: 'Nasr City',
    district: 'Hay El Asher',
    street: 'Abbas El Akkad',
    building: '12',
    latitude: 30.0561,
    longitude: 31.3300,
    isDefault: isDefault,
    contacts: contacts,
  );
}

Future<Widget> _wrap({
  required _FakePropertiesRepository repository,
  bool newProperty = false,
}) async {
  return ProviderScope(
    overrides: <Override>[
      propertiesRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: newProperty
          ? const PropertyNewPage(enableMap: false)
          : const PropertyDetailPage(propertyId: 'p1'),
    ),
  );
}

ProviderContainer _container(_FakePropertiesRepository repository) {
  return ProviderContainer(
    overrides: <Override>[
      propertiesRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _FakePropertiesRepository implements PropertiesRepository {
  List<Property> items = <Property>[];
  Property detail = _property();
  ApiFailure? loadError;
  ApiFailure? saveError;
  int createCalls = 0;
  bool deleted = false;
  String? lastCreateLabel;
  bool? lastUpdateIsDefault;

  @override
  Future<List<Property>> list() async {
    final ApiFailure? failure = loadError;
    if (failure != null) throw failure;
    return items;
  }

  @override
  Future<Property> get(String propertyId) async {
    final ApiFailure? failure = loadError;
    if (failure != null) throw failure;
    return detail;
  }

  @override
  Future<List<MaintenanceHistoryItem>> history(String propertyId) async =>
      <MaintenanceHistoryItem>[];

  @override
  Future<Property> create({
    required String label,
    required String governorate,
    required String city,
    required double latitude,
    required double longitude,
    String? propertyType,
    String? zone,
    String? district,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
    String? notes,
    bool isDefault = false,
    String? contactName,
    String? contactPhone,
  }) async {
    createCalls++;
    lastCreateLabel = label;
    final ApiFailure? failure = saveError;
    if (failure != null) throw failure;
    final Property created = _property(id: 'created');
    items = <Property>[...items, created];
    return created;
  }

  @override
  Future<Property> update(
    String propertyId, {
    String? label,
    String? governorate,
    String? city,
    double? latitude,
    double? longitude,
    String? propertyType,
    String? zone,
    String? district,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
    String? notes,
    bool? isDefault,
    String? contactName,
    String? contactPhone,
  }) async {
    lastUpdateIsDefault = isDefault;
    final ApiFailure? failure = saveError;
    if (failure != null) throw failure;
    detail = _property(isDefault: isDefault ?? detail.isDefault);
    return detail;
  }

  @override
  Future<void> delete(String propertyId) async {
    deleted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
