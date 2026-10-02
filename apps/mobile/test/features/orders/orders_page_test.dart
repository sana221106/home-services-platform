import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/core/network/paginated.dart';
import 'package:home_services_app/features/orders/data/models/order_models.dart';
import 'package:home_services_app/features/orders/data/repositories/orders_repository.dart';
import 'package:home_services_app/features/orders/presentation/pages/orders_page.dart';

void main() {
  group('OrderSummary', () {
    test('parses the list payload', () {
      final OrderSummary order = OrderSummary.fromJson(<String, dynamic>{
        'request_id': 'req-1',
        'reference_code': 'REF-1',
        'status': 'ON_THE_WAY',
        'status_label_ar': 'في الطريق',
        'category_name_ar': 'Plumbing',
        'category_icon_key': 'faucet',
        'urgency': 'URGENT',
        'property_label': 'Home',
        'created_at': '2026-01-01T10:00:00Z',
        'submitted_at': '2026-01-01T11:00:00Z',
        'completed_at': null,
        'total': '310.00',
        'has_complaint': true,
        'has_unread_updates': true,
      });

      expect(order.requestId, 'req-1');
      expect(order.total, '310.00');
      expect(order.isUrgent, isTrue);
      expect(order.hasComplaint, isTrue);
      expect(order.hasUnreadUpdates, isTrue);
      expect(order.completedAt, isNull);
    });

    test('survives a payload with nothing but the required keys', () {
      final OrderSummary order = OrderSummary.fromJson(<String, dynamic>{
        'request_id': 'req-2',
      });

      // A malformed row must render, not crash the list.
      expect(order.requestId, 'req-2');
      expect(order.total, isNull);
      expect(order.urgency, 'NORMAL');
      expect(order.isUrgent, isFalse);
    });
  });

  group('OrderTracking', () {
    test('parses the arrival window, technician and flags', () {
      final OrderTracking tracking = OrderTracking.fromJson(<String, dynamic>{
        'request_id': 'req-1',
        'reference_code': 'REF-1',
        'status': 'ON_THE_WAY',
        'status_label_ar': 'في الطريق',
        'status_description_ar': 'الفني في الطريق إليك',
        'urgency': 'NORMAL',
        'expected_arrival': <String, dynamic>{
          'start': '2026-01-02T10:00:00Z',
          'end': '2026-01-02T14:00:00Z',
        },
        'actual_arrival': null,
        'technician': <String, dynamic>{
          'display_name': 'Ahmed',
          'company_label_ar': 'فريق الخدمة',
        },
        'address_summary_ar': 'Building 3, Nasr City',
        'events': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'e-1', 'event_type': 'ASSIGNED'},
        ],
        'can_cancel': true,
        'can_open_complaint': false,
        'can_rate': false,
      });

      expect(tracking.hasExpectedArrival, isTrue);
      expect(tracking.hasArrived, isFalse);
      expect(tracking.technicianName, 'Ahmed');
      expect(tracking.addressSummaryAr, 'Building 3, Nasr City');
      expect(tracking.events, hasLength(1));
      expect(tracking.canCancel, isTrue);
      expect(tracking.hasAnyAction, isTrue);
    });

    test('treats a null technician as absent rather than empty', () {
      final OrderTracking tracking = OrderTracking.fromJson(<String, dynamic>{
        'request_id': 'req-1',
        'technician': null,
        'expected_arrival': null,
      });

      expect(tracking.technicianName, isNull);
      expect(tracking.hasExpectedArrival, isFalse);
      expect(tracking.hasAnyAction, isFalse);
    });
  });

  group('OrdersPage', () {
    testWidgets('lists orders with their status', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(_FakeOrdersRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('#REF-1'), findsOneWidget);
      expect(find.text('Technician on the way'), findsOneWidget);
    });

    testWidgets('an empty history explains itself and offers the wizard', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_FakeOrdersRepository()..listValue = _emptyPage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.text('Book a service'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that refetches', (
      WidgetTester tester,
    ) async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository()
        ..listError = const ApiFailure(
          code: 'NETWORK',
          message: 'Orders unavailable',
        );
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Orders unavailable'), findsOneWidget);

      repository.listError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Plumbing'), findsOneWidget);
    });

    testWidgets('a terminal order shows the accepted total', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakeOrdersRepository()
            ..listValue = _page(<OrderSummary>[
              _order(status: 'CLOSED', total: '310.00'),
            ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('310.00'), findsOneWidget);
    });

    testWidgets('a running order says pricing is pending instead', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeOrdersRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Pending pricing'), findsNothing);
    });
  });
}

OrderSummary _order({required String status, String? total = '310.00'}) {
  return OrderSummary(
    requestId: 'req-1',
    referenceCode: 'REF-1',
    status: status,
    categoryNameAr: 'Plumbing',
    urgency: 'NORMAL',
    propertyLabel: 'Home',
    createdAt: DateTime(2026, 1, 1),
    total: total,
  );
}

Paginated<OrderSummary> _page(List<OrderSummary> items) {
  return Paginated<OrderSummary>(
    items: items,
    meta: const PageMeta(
      page: 1,
      perPage: 20,
      total: 1,
      totalPages: 1,
      hasNext: false,
      hasPrevious: false,
    ),
  );
}

Paginated<OrderSummary> _emptyPage() => _page(<OrderSummary>[]);

Widget _wrap(_FakeOrdersRepository repository) {
  return ProviderScope(
    overrides: <Override>[
      ordersRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const OrdersPage(),
    ),
  );
}

class _FakeOrdersRepository implements OrdersRepository {
  _FakeOrdersRepository()
    : listValue = _page(<OrderSummary>[_order(status: 'ON_THE_WAY')]);

  Paginated<OrderSummary> listValue;
  ApiFailure? listError;

  final List<int> requestedPages = <int>[];

  @override
  Future<Paginated<OrderSummary>> list({int page = 1, int perPage = 20}) async {
    requestedPages.add(page);
    final ApiFailure? failure = listError;
    if (failure != null) throw failure;
    return listValue;
  }

  @override
  Future<OrderTracking> track(String requestId) async =>
      OrderTracking.fromJson(<String, dynamic>{'request_id': requestId});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
