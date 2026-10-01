import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_services_app/core/constants/request_status.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/features/requests/data/models/request_models.dart';
import 'package:home_services_app/features/requests/data/repositories/requests_repository.dart';
import 'package:home_services_app/features/requests/presentation/controllers/request_detail_controller.dart';

void main() {
  group('CancellationPreview', () {
    test('keeps deposit amounts instead of collapsing them to booleans', () {
      const CancellationPreview preview = CancellationPreview(
        requestId: 'req-1',
        depositRequiredAmount: 150.5,
        depositPaidAmount: 150.5,
        refundPercent: 80,
        refundableAmount: 120.4,
        deductionAmount: 30.1,
        requiresApproval: false,
      );

      expect(preview.depositRequired, isTrue);
      expect(preview.depositPaid, isTrue);
      // The exact figures are what the confirmation dialog shows.
      expect(preview.depositRequiredAmount, 150.5);
      expect(preview.refundableAmount, 120.4);
      expect(preview.deductionAmount, 30.1);
    });

    test('an unpaid deposit reports both flags false', () {
      const CancellationPreview preview = CancellationPreview(
        requestId: 'req-1',
        depositRequiredAmount: 100,
        depositPaidAmount: 0,
        refundPercent: 100,
        refundableAmount: 0,
        deductionAmount: 0,
        requiresApproval: false,
      );

      expect(preview.depositRequired, isTrue);
      expect(preview.depositPaid, isFalse);
    });

    test('no deposit at all reports nothing to refund', () {
      const CancellationPreview preview = CancellationPreview(
        requestId: 'req-1',
        depositRequiredAmount: 0,
        depositPaidAmount: 0,
        refundPercent: 0,
        refundableAmount: 0,
        deductionAmount: 0,
        requiresApproval: false,
      );

      expect(preview.depositRequired, isFalse);
      expect(preview.depositPaid, isFalse);
    });
  });

  group('RequestDetailState', () {
    test('only a SENT or awaiting-approval quote counts as answerable', () {
      expect(_stateWithQuoteStatus('SENT').hasQuoteToAnswer, isTrue);
      expect(
        _stateWithQuoteStatus('AWAITING_CUSTOMER_APPROVAL').hasQuoteToAnswer,
        isTrue,
      );
      expect(_stateWithQuoteStatus('EXPIRED').hasQuoteToAnswer, isFalse);
      expect(_stateWithQuoteStatus('ACCEPTED').hasQuoteToAnswer, isFalse);
      expect(
        const RequestDetailState().hasQuoteToAnswer,
        isFalse,
        reason: 'a request with no quote offers nothing to answer',
      );
    });

    test(
      'cancel is offered for a cancellable status and withheld otherwise',
      () {
        expect(
          RequestDetailState(
            request: _request(status: 'UNDER_REVIEW'),
          ).canCancel,
          isTrue,
        );
        expect(
          RequestDetailState(
            request: _request(status: 'SERVICE_COMPLETED'),
          ).canCancel,
          isFalse,
        );
        expect(
          RequestDetailState(request: _request(status: 'CANCELLED')).canCancel,
          isFalse,
        );
      },
    );

    test('rating and complaint follow their own status sets', () {
      final RequestDetailState paid = RequestDetailState(
        request: _request(status: 'PAID'),
      );
      expect(paid.canRate, isTrue);
      expect(paid.canComplain, isTrue);

      final RequestDetailState inProgress = RequestDetailState(
        request: _request(status: 'WORK_IN_PROGRESS'),
      );
      expect(inProgress.canRate, isFalse);
      expect(inProgress.canComplain, isTrue);

      final RequestDetailState quoting = RequestDetailState(
        request: _request(status: 'QUOTE_SENT'),
      );
      expect(quoting.canRate, isFalse);
      expect(quoting.canComplain, isFalse);
    });

    test('no actions are offered while a request is mid-action', () {
      final RequestDetailState state = RequestDetailState(
        request: _request(status: 'PAID'),
        isActing: true,
      );

      expect(state.canRate, isFalse);
      expect(state.canComplain, isFalse);
      expect(state.canCancel, isFalse);
    });

    test('copyWith keeps the quote unless it is explicitly cleared', () {
      final RequestDetailState state = _stateWithQuoteStatus('SENT');

      expect(state.copyWith(isActing: true).quote, isNotNull);
      expect(state.copyWith(clearQuote: true).quote, isNull);
    });
  });

  group('RequestDetailController', () {
    test('loads request, timeline and quote together', () async {
      final _FakeRepository repository = _FakeRepository();
      final ProviderContainer container = _container(repository);
      final RequestDetailController controller = container.read(
        requestDetailProvider('req-1').notifier,
      );

      await controller.load();

      final RequestDetailState state = container.read(
        requestDetailProvider('req-1'),
      );
      expect(state.status, RequestDetailStatus.ready);
      expect(state.request?.referenceCode, 'REF-1');
      expect(state.events, hasLength(2));
      expect(state.quote?.revisionNumber, 2);
      expect(repository.detailCalls, 1);
    });

    test(
      'a load failure surfaces the message and keeps it retryable',
      () async {
        final _FakeRepository repository = _FakeRepository()
          ..detailError = const ApiFailure(
            code: 'NOT_FOUND',
            message: 'Request not found',
            statusCode: 404,
          );
        final ProviderContainer container = _container(repository);
        final RequestDetailController controller = container.read(
          requestDetailProvider('req-1').notifier,
        );

        await controller.load();

        expect(
          container.read(requestDetailProvider('req-1')).status,
          RequestDetailStatus.failed,
        );
        expect(
          container.read(requestDetailProvider('req-1')).errorMessage,
          'Request not found',
        );

        repository.detailError = null;
        await controller.load(force: true);
        expect(
          container.read(requestDetailProvider('req-1')).status,
          RequestDetailStatus.ready,
        );
      },
    );

    test('a null quote is a normal result, not a failure', () async {
      final _FakeRepository repository = _FakeRepository()..quoteValue = null;
      final ProviderContainer container = _container(repository);

      await container.read(requestDetailProvider('req-1').notifier).load();

      final RequestDetailState state = container.read(
        requestDetailProvider('req-1'),
      );
      expect(state.status, RequestDetailStatus.ready);
      expect(state.quote, isNull);
    });

    test('accepting sends the revision the customer actually saw', () async {
      final _FakeRepository repository = _FakeRepository();
      final ProviderContainer container = _container(repository);
      final RequestDetailController controller = container.read(
        requestDetailProvider('req-1').notifier,
      );
      await controller.load();

      await controller.acceptQuote();

      expect(repository.acceptedRevisions, <int>[2]);
      final RequestDetailState state = container.read(
        requestDetailProvider('req-1'),
      );
      expect(state.request?.status, 'DEPOSIT_PENDING');
      expect(state.quote, isNull, reason: 'a decided quote must not linger');
    });

    test('a failed accept keeps the quote so the customer can retry', () async {
      final _FakeRepository repository = _FakeRepository()
        ..acceptError = const ApiFailure(
          code: 'QUOTE_REVISION_CONFLICT',
          message: 'A newer quote was issued',
          statusCode: 409,
        );
      final ProviderContainer container = _container(repository);
      final RequestDetailController controller = container.read(
        requestDetailProvider('req-1').notifier,
      );
      await controller.load();

      await controller.acceptQuote();

      final RequestDetailState state = container.read(
        requestDetailProvider('req-1'),
      );
      expect(state.quote, isNotNull);
      expect(state.isActing, isFalse);
      expect(state.actionError, 'A newer quote was issued');
    });

    test('rejecting passes the reason through and clears the quote', () async {
      final _FakeRepository repository = _FakeRepository();
      final ProviderContainer container = _container(repository);
      final RequestDetailController controller = container.read(
        requestDetailProvider('req-1').notifier,
      );
      await controller.load();

      await controller.rejectQuote(reason: 'too expensive');

      expect(repository.rejectReasons, <String?>['too expensive']);
      expect(container.read(requestDetailProvider('req-1')).quote, isNull);
    });

    test(
      'an empty reason is sent as null rather than a blank string',
      () async {
        final _FakeRepository repository = _FakeRepository();
        final ProviderContainer container = _container(repository);
        final RequestDetailController controller = container.read(
          requestDetailProvider('req-1').notifier,
        );
        await controller.load();

        await controller.rejectQuote(reason: '');

        expect(repository.rejectReasons, <String?>[null]);
      },
    );

    test('cancellation preview is fetched before the cancel is sent', () async {
      final _FakeRepository repository = _FakeRepository();
      final ProviderContainer container = _container(repository);
      final RequestDetailController controller = container.read(
        requestDetailProvider('req-1').notifier,
      );
      await controller.load();

      final CancellationPreview preview = await controller
          .cancellationPreview();
      expect(preview.refundableAmount, 120);
      expect(
        container.read(requestDetailProvider('req-1')).isActing,
        isFalse,
        reason: 'the button unlocks again once the preview is shown',
      );

      await controller.cancel(reasonNote: 'changed my mind');

      expect(repository.cancelReasons, <String?>['changed my mind']);
      expect(
        container.read(requestDetailProvider('req-1')).request?.status,
        'CANCELLED',
      );
    });

    test('a failed preview reports the message and rethrows', () async {
      final _FakeRepository repository = _FakeRepository()
        ..previewError = const ApiFailure(
          code: 'NOT_CANCELLABLE',
          message: 'Too late to cancel',
          statusCode: 409,
        );
      final ProviderContainer container = _container(repository);
      final RequestDetailController controller = container.read(
        requestDetailProvider('req-1').notifier,
      );
      await controller.load();

      await expectLater(
        controller.cancellationPreview(),
        throwsA(isA<ApiFailure>()),
      );

      final RequestDetailState state = container.read(
        requestDetailProvider('req-1'),
      );
      expect(state.actionError, 'Too late to cancel');
      expect(state.isActing, isFalse);
    });

    test('a second load while one is in flight is ignored', () async {
      final _FakeRepository repository = _FakeRepository();
      final ProviderContainer container = _container(repository);
      final RequestDetailController controller = container.read(
        requestDetailProvider('req-1').notifier,
      );

      await Future.wait<void>(<Future<void>>[
        controller.load(),
        controller.load(),
      ]);

      expect(repository.detailCalls, 1);
    });
  });

  group('status mapping used by the detail screen', () {
    test(
      'an unknown backend status degrades to neutral instead of crashing',
      () {
        final RequestDetailState state = RequestDetailState(
          request: _request(status: 'SOMETHING_NEW_FROM_BACKEND'),
        );

        expect(state.requestStatus, isNull);
        expect(state.canCancel, isFalse);
        expect(state.canRate, isFalse);
        expect(state.canComplain, isFalse);
      },
    );

    test('RESOLVED is not terminal, matching the backend set', () {
      expect(AppRequestStatus.resolved.isTerminal, isFalse);
      expect(AppRequestStatus.closed.isTerminal, isTrue);
      expect(AppRequestStatus.cancelled.isTerminal, isTrue);
    });
  });
}

ProviderContainer _container(_FakeRepository repository) {
  final ProviderContainer container = ProviderContainer(
    overrides: [requestsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

RequestDetailState _stateWithQuoteStatus(String quoteStatus) {
  return RequestDetailState(
    request: _request(status: 'QUOTE_SENT'),
    quote: Quote(
      id: 'q-1',
      requestId: 'req-1',
      revisionNumber: 1,
      status: quoteStatus,
      urgency: 'NORMAL',
      serviceCost: 100,
      materialsCost: 0,
      urgencyFee: 0,
      inspectionFee: 0,
      discount: 0,
      subtotal: 100,
      total: 100,
      depositAmount: 0,
      requiresDeposit: false,
      estimatedDurationMinutes: 60,
    ),
  );
}

ServiceRequest _request({required String status}) {
  return ServiceRequest(
    id: 'req-1',
    referenceCode: 'REF-1',
    categoryNameAr: 'سباكة',
    status: status,
    urgency: 'NORMAL',
    inspectionOnly: false,
    inspectionRequired: false,
    problemDescription: 'Leaking tap in the kitchen',
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Stands in for the repository so the controller can be driven without Dio.
///
/// Only the methods the detail screen uses are overridden; the rest throw so an
/// unexpected call shows up as a test failure rather than silent success.
class _FakeRepository implements RequestsRepository {
  _FakeRepository()
    : detailValue = _request(status: 'QUOTE_SENT'),
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
      ],
      quoteValue = Quote(
        id: 'q-1',
        requestId: 'req-1',
        revisionNumber: 2,
        status: 'SENT',
        urgency: 'NORMAL',
        serviceCost: 100,
        materialsCost: 20,
        urgencyFee: 0,
        inspectionFee: 0,
        discount: 0,
        subtotal: 120,
        total: 120,
        depositAmount: 30,
        requiresDeposit: true,
        estimatedDurationMinutes: 60,
      ),
      previewValue = const CancellationPreview(
        requestId: 'req-1',
        depositRequiredAmount: 150,
        depositPaidAmount: 150,
        refundPercent: 80,
        refundableAmount: 120,
        deductionAmount: 30,
        requiresApproval: false,
      );

  ServiceRequest detailValue;
  List<RequestEvent> timelineValue;
  Quote? quoteValue;
  CancellationPreview previewValue;

  ApiFailure? detailError;
  ApiFailure? acceptError;
  ApiFailure? previewError;

  int detailCalls = 0;
  final List<int> acceptedRevisions = <int>[];
  final List<String?> rejectReasons = <String?>[];
  final List<String?> cancelReasons = <String?>[];

  @override
  Future<ServiceRequest> detail(String requestId) async {
    detailCalls++;
    final ApiFailure? failure = detailError;
    if (failure != null) throw failure;
    return detailValue;
  }

  @override
  Future<List<RequestEvent>> timeline(String requestId) async => timelineValue;

  @override
  Future<Quote?> quote(String requestId) async => quoteValue;

  @override
  Future<CancellationPreview> cancellationPreview(String requestId) async {
    final ApiFailure? failure = previewError;
    if (failure != null) throw failure;
    return previewValue;
  }

  @override
  Future<ServiceRequest> acceptQuote(
    String requestId, {
    required int acceptedRevision,
  }) async {
    final ApiFailure? failure = acceptError;
    if (failure != null) throw failure;
    acceptedRevisions.add(acceptedRevision);
    return ServiceRequest(
      id: 'req-1',
      referenceCode: 'REF-1',
      categoryNameAr: 'سباكة',
      status: 'DEPOSIT_PENDING',
      urgency: 'NORMAL',
      inspectionOnly: false,
      inspectionRequired: false,
      problemDescription: 'Leaking tap in the kitchen',
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<ServiceRequest> rejectQuote(String requestId, {String? reason}) async {
    rejectReasons.add(reason);
    return detailValue;
  }

  @override
  Future<ServiceRequest> cancel(String requestId, {String? reasonNote}) async {
    cancelReasons.add(reasonNote);
    return ServiceRequest(
      id: 'req-1',
      referenceCode: 'REF-1',
      categoryNameAr: 'سباكة',
      status: 'CANCELLED',
      urgency: 'NORMAL',
      inspectionOnly: false,
      inspectionRequired: false,
      problemDescription: 'Leaking tap in the kitchen',
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
