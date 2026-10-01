import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/features/requests/data/models/request_models.dart';
import 'package:home_services_app/features/requests/data/repositories/requests_repository.dart';
import 'package:home_services_app/features/requests/presentation/pages/request_detail_page.dart';

void main() {
  group('RequestDetailPage', () {
    testWidgets('renders the status, the problem and the timeline', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Leaking tap in the kitchen'), findsOneWidget);
      expect(find.text('Reference #REF-1'), findsOneWidget);
      expect(find.text('Awaiting your approval'), findsOneWidget);
      expect(find.text('Visit address'), findsNothing);
    });

    testWidgets('an empty timeline says so instead of showing nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeRepository()..timelineValue = []));
      await tester.pumpAndSettle();

      expect(find.text('No updates yet'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that refetches', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository()
        ..detailError = const ApiFailure(
          code: 'NOT_FOUND',
          message: 'Request not found',
          statusCode: 404,
        );
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Request not found'), findsOneWidget);

      repository.detailError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Leaking tap in the kitchen'), findsOneWidget);
    });

    testWidgets('accept is offered while the quote is open', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote-accept')), findsOneWidget);
    });

    testWidgets('accept sends the revision and removes the quote', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      // The quote sits below the fold; scrolling to the bottom is enough and
      // avoids overshooting the list on a short viewport.
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quote-accept')));
      await tester.pumpAndSettle();

      expect(repository.acceptedRevisions, <int>[3]);
      expect(find.byKey(const Key('quote-accept')), findsNothing);
    });

    testWidgets('a closed quote keeps its numbers but drops the buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_FakeRepository()..quoteValue = _quote(status: 'EXPIRED')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote-accept')), findsNothing);
      expect(find.text('Price quote'), findsOneWidget);
    });

    testWidgets('a quote without fees hides the zero rows', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakeRepository()
            ..quoteValue = _quote(
              status: 'SENT',
              materialsCost: 0,
              discount: 0,
              deposit: 0,
            ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Materials'), findsNothing);
      expect(find.text('Discount'), findsNothing);
      expect(find.text('Service'), findsOneWidget);
      expect(find.text('300.00 EGP'), findsOneWidget);
    });

    testWidgets('the cancel button only appears on a cancellable status', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_FakeRepository()..status = 'SERVICE_COMPLETED'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('request-cancel')), findsNothing);
    });

    testWidgets('cancelling shows the server refund before confirming', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('request-cancel')));
      await tester.pumpAndSettle();

      // The figure comes from the preview endpoint, never computed on screen.
      expect(find.text('120.00 EGP'), findsOneWidget);
      expect(find.text('30.00 EGP'), findsOneWidget);
      expect(repository.cancelled, isFalse, reason: 'nothing sent yet');

      await tester.tap(find.text('Confirm cancellation'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'changed my mind');
      await tester.tap(find.text('Confirm cancellation').last);
      await tester.pumpAndSettle();

      expect(repository.cancelled, isTrue);
    });

    testWidgets('dismissing the refund dialog cancels nothing', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('request-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.cancelled, isFalse);
    });
  });
}

Widget _wrap(_FakeRepository repository) {
  return ProviderScope(
    overrides: <Override>[
      requestsRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const RequestDetailPage(requestId: 'req-1'),
    ),
  );
}

ServiceRequest _request({required String status}) {
  return ServiceRequest(
    id: 'req-1',
    referenceCode: 'REF-1',
    categoryNameAr: 'Plumbing',
    status: status,
    urgency: 'NORMAL',
    inspectionOnly: false,
    inspectionRequired: false,
    problemDescription: 'Leaking tap in the kitchen',
    createdAt: DateTime(2026, 1, 1),
  );
}

Quote _quote({
  required String status,
  double materialsCost = 50,
  double discount = 20,
  double deposit = 75,
}) {
  return Quote(
    id: 'q-1',
    requestId: 'req-1',
    revisionNumber: 3,
    status: status,
    urgency: 'NORMAL',
    serviceCost: 300,
    materialsCost: materialsCost,
    urgencyFee: 0,
    inspectionFee: 0,
    discount: discount,
    subtotal: 330,
    total: 310,
    depositAmount: deposit,
    requiresDeposit: deposit > 0,
    estimatedDurationMinutes: 90,
  );
}

class _FakeRepository implements RequestsRepository {
  _FakeRepository()
    : status = 'AWAITING_CUSTOMER_APPROVAL',
      timelineValue = <RequestEvent>[
        RequestEvent(
          id: 'e-1',
          eventType: 'CREATED',
          occurredAt: DateTime(2026, 1, 1),
        ),
        RequestEvent(
          id: 'e-2',
          eventType: 'QUOTE_SENT',
          toStatus: 'QUOTE_SENT',
          occurredAt: DateTime(2026, 1, 2),
        ),
      ];

  String status;
  List<RequestEvent> timelineValue;
  Quote? quoteValue = _quote(status: 'SENT');

  ApiFailure? detailError;

  final List<int> acceptedRevisions = <int>[];
  bool cancelled = false;

  @override
  Future<ServiceRequest> detail(String requestId) async {
    final ApiFailure? failure = detailError;
    if (failure != null) throw failure;
    return _request(status: status);
  }

  @override
  Future<List<RequestEvent>> timeline(String requestId) async => timelineValue;

  @override
  Future<Quote?> quote(String requestId) async => quoteValue;

  @override
  Future<CancellationPreview> cancellationPreview(String requestId) async {
    return const CancellationPreview(
      requestId: 'req-1',
      depositRequiredAmount: 150,
      depositPaidAmount: 150,
      refundPercent: 80,
      refundableAmount: 120,
      deductionAmount: 30,
      requiresApproval: false,
    );
  }

  @override
  Future<ServiceRequest> acceptQuote(
    String requestId, {
    required int acceptedRevision,
  }) async {
    acceptedRevisions.add(acceptedRevision);
    quoteValue = null;
    status = 'DEPOSIT_PENDING';
    return _request(status: status);
  }

  @override
  Future<ServiceRequest> rejectQuote(String requestId, {String? reason}) async {
    quoteValue = null;
    return _request(status: status);
  }

  @override
  Future<ServiceRequest> cancel(String requestId, {String? reasonNote}) async {
    cancelled = true;
    status = 'CANCELLED';
    return _request(status: status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
