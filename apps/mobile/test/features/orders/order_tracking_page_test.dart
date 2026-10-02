import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/features/orders/data/models/order_models.dart';
import 'package:home_services_app/features/orders/data/repositories/orders_repository.dart';
import 'package:home_services_app/features/orders/presentation/pages/order_tracking_page.dart';
import 'package:home_services_app/features/requests/data/models/request_models.dart';

void main() {
  group('OrderTrackingPage', () {
    testWidgets('shows the promised arrival window as a range', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeOrdersRepository()));
      await tester.pumpAndSettle();

      expect(find.text('#REF-1'), findsOneWidget);
      // The server's Arabic status label wins over the client mirror.
      expect(find.text('في الطريق'), findsOneWidget);
      // A window, not a single promised time.
      expect(find.text('Estimated arrival'), findsOneWidget);
      expect(find.textContaining('AM'), findsOneWidget);
    });

    testWidgets('an arrived technician replaces the estimate with a fact', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeOrdersRepository()..arrived = true));
      await tester.pumpAndSettle();

      expect(find.text('Technician has arrived'), findsOneWidget);
      expect(find.text('Expected arrival'), findsNothing);
      expect(find.text('Work started'), findsOneWidget);
    });

    testWidgets('an unscheduled order says so rather than showing a blank', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_FakeOrdersRepository()..scheduled = false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Arrival not scheduled yet'), findsOneWidget);
      expect(find.text('Estimated arrival'), findsNothing);
    });

    testWidgets('shows the technician label but no contact details', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeOrdersRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Ahmed'), findsOneWidget);
      expect(find.text('فريق الخدمة'), findsOneWidget);
      // Dispatch exposes a name and a role label, never a phone number (§9), so
      // the tracking screen has no call affordance at all.
      expect(find.byIcon(Icons.phone), findsNothing);
      expect(find.byIcon(Icons.chat), findsNothing);
    });

    testWidgets('renders the shared timeline from the tracking payload', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeOrdersRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('No updates yet'), findsNothing);
    });

    testWidgets('an empty timeline says so instead of showing nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_FakeOrdersRepository()..events = <RequestEvent>[]),
      );
      await tester.pumpAndSettle();

      // The timeline sits below the arrival card, which is itself below the
      // status card, so it has to be scrolled into the lazily built list.
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('No updates yet'), findsOneWidget);
    });

    testWidgets('offers only the actions the server permits', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeOrdersRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('order-cancel')), findsOneWidget);
      expect(find.byKey(const Key('order-rate')), findsNothing);
      expect(find.byKey(const Key('order-complain')), findsNothing);
    });

    testWidgets('draws no footer at all when nothing is permitted', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakeOrdersRepository()
            ..canCancel = false
            ..canRate = false
            ..canComplain = false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('order-cancel')), findsNothing);
      expect(find.byKey(const Key('order-rate')), findsNothing);
      expect(find.byKey(const Key('order-complain')), findsNothing);
    });

    testWidgets('a failed load offers a retry that refetches', (
      WidgetTester tester,
    ) async {
      final _FakeOrdersRepository repository = _FakeOrdersRepository()
        ..trackError = const ApiFailure(
          code: 'NETWORK',
          message: 'Tracking unavailable',
        );
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Tracking unavailable'), findsOneWidget);

      repository.trackError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('#REF-1'), findsOneWidget);
    });
  });
}

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
      home: const OrderTrackingPage(requestId: 'req-1'),
    ),
  );
}

class _FakeOrdersRepository implements OrdersRepository {
  bool scheduled = true;
  bool arrived = false;
  bool canCancel = true;
  bool canRate = false;
  bool canComplain = false;
  ApiFailure? trackError;

  List<RequestEvent> events = <RequestEvent>[
    RequestEvent(
      id: 'e-1',
      eventType: 'ASSIGNED',
      toStatus: 'TECHNICIAN_ASSIGNED',
      occurredAt: DateTime(2026, 1, 1),
    ),
  ];

  @override
  Future<OrderTracking> track(String requestId) async {
    final ApiFailure? failure = trackError;
    if (failure != null) throw failure;

    return OrderTracking(
      requestId: requestId,
      referenceCode: 'REF-1',
      status: 'ON_THE_WAY',
      statusLabelAr: 'في الطريق',
      statusDescriptionAr: 'الفني في الطريق إليك',
      urgency: 'NORMAL',
      expectedArrivalStart: scheduled ? DateTime(2026, 1, 2, 10) : null,
      expectedArrivalEnd: scheduled ? DateTime(2026, 1, 2, 14) : null,
      actualArrival: arrived ? DateTime(2026, 1, 2, 10, 12) : null,
      workStartedAt: arrived ? DateTime(2026, 1, 2, 10, 20) : null,
      technicianName: 'Ahmed',
      technicianCompanyAr: 'فريق الخدمة',
      addressSummaryAr: 'Building 3, Nasr City',
      events: events,
      canCancel: canCancel,
      canOpenComplaint: canComplain,
      canRate: canRate,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
