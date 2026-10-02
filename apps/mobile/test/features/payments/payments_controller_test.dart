import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/features/payments/data/models/payment_models.dart';
import 'package:home_services_app/features/payments/data/repositories/payments_repository.dart';
import 'package:home_services_app/features/payments/presentation/controllers/payments_controller.dart';

void main() {
  group('PaymentsController', () {
    test(
      'load brings the view, the methods and the refunds together',
      () async {
        final ProviderContainer container = _container(
          _FakePaymentsRepository(),
        );
        addTearDown(container.dispose);

        await container.read(paymentsProvider('req-1').notifier).load();

        final PaymentsState state = container.read(paymentsProvider('req-1'));
        expect(state.status, PaymentsStatus.ready);
        expect(state.view!.amountDue, 250);
        expect(state.methods.map((PaymentMethodOption o) => o.code), <String>[
          'CASH',
          'VODAFONE_CASH',
        ]);
        expect(state.refunds, hasLength(1));
      },
    );

    test('a failed load offers the message', () async {
      final ProviderContainer container = _container(
        _FakePaymentsRepository()
          ..viewError = const ApiFailure(
            code: 'NETWORK',
            message: 'Payments unavailable',
          ),
      );
      addTearDown(container.dispose);

      await container.read(paymentsProvider('req-1').notifier).load();

      final PaymentsState state = container.read(paymentsProvider('req-1'));
      expect(state.status, PaymentsStatus.failed);
      expect(state.errorMessage, 'Payments unavailable');
    });

    test(
      'submit posts the evidence with an idempotency key and reloads',
      () async {
        final _FakePaymentsRepository repository = _FakePaymentsRepository();
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);

        final PaymentRecord? record = await container
            .read(paymentsProvider('req-1').notifier)
            .submit(method: 'VODAFONE_CASH', amount: 250, isDeposit: false);

        expect(record, isNotNull);
        expect(repository.submittedMethod, 'VODAFONE_CASH');
        expect(repository.submittedAmount, 250);
        // A retried submit must not become a second payment.
        expect(repository.submittedIdempotencyKey, isNotEmpty);
        // Reloading is what keeps the outstanding total honest.
        expect(
          container.read(paymentsProvider('req-1')).status,
          PaymentsStatus.ready,
        );
      },
    );

    test('a rejected submit returns null and keeps the message', () async {
      final ProviderContainer container = _container(
        _FakePaymentsRepository()
          ..submitError = const ApiFailure(
            code: 'VALIDATION',
            message: 'Amount exceeds the total',
          ),
      );
      addTearDown(container.dispose);

      final PaymentRecord? record = await container
          .read(paymentsProvider('req-1').notifier)
          .submit(method: 'CASH', amount: 9999, isDeposit: false);

      expect(record, isNull);
      final PaymentsState state = container.read(paymentsProvider('req-1'));
      expect(state.errorMessage, 'Amount exceeds the total');
      expect(state.isSubmitting, isFalse);
    });

    test('uploading proof targets one payment and reloads', () async {
      final _FakePaymentsRepository repository = _FakePaymentsRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      final bool ok = await container
          .read(paymentsProvider('req-1').notifier)
          .uploadProof(
            paymentId: 'pay-1',
            filePath: 'C:/tmp/receipt.jpg',
            fileName: 'receipt.jpg',
          );

      expect(ok, isTrue);
      expect(repository.proofPaymentId, 'pay-1');
      expect(
        container.read(paymentsProvider('req-1')).status,
        PaymentsStatus.ready,
      );
    });

    test(
      'a failed proof upload reports failure instead of pretending',
      () async {
        final ProviderContainer container = _container(
          _FakePaymentsRepository()
            ..proofError = const ApiFailure(
              code: 'VALIDATION',
              message: 'Unsupported file',
            ),
        );
        addTearDown(container.dispose);

        final bool ok = await container
            .read(paymentsProvider('req-1').notifier)
            .uploadProof(
              paymentId: 'pay-1',
              filePath: 'C:/tmp/receipt.pdf',
              fileName: 'receipt.pdf',
            );

        expect(ok, isFalse);
        expect(
          container.read(paymentsProvider('req-1')).errorMessage,
          'Unsupported file',
        );
      },
    );
  });
}

ProviderContainer _container(_FakePaymentsRepository repository) {
  return ProviderContainer(
    overrides: <Override>[
      paymentsRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _FakePaymentsRepository implements PaymentsRepository {
  PaymentView viewValue = PaymentView(
    requestId: 'req-1',
    referenceCode: 'REQ-0001',
    quoteTotal: 500,
    amountDue: 250,
    methods: const <String>['CASH', 'VODAFONE_CASH'],
    payments: <PaymentRecord>[
      PaymentRecord(
        id: 'pay-1',
        amount: 250,
        method: 'VODAFONE_CASH',
        status: 'VERIFICATION_PENDING',
        amountRefunded: 0,
      ),
    ],
    supportPhone: '+201000000000',
  );
  ApiFailure? viewError;

  List<PaymentMethodOption> methodsValue = <PaymentMethodOption>[
    const PaymentMethodOption(
      code: 'CASH',
      labelAr: 'نقدًا',
      requiresProof: false,
    ),
    const PaymentMethodOption(code: 'VODAFONE_CASH', labelAr: 'فودافون كاش'),
  ];

  List<RefundRecord> refundsValue = <RefundRecord>[
    const RefundRecord(
      id: 'ref-1',
      paymentId: 'pay-0',
      amount: 100,
      reason: 'Overcharge',
      status: 'PROCESSED',
    ),
  ];

  ApiFailure? submitError;
  ApiFailure? proofError;

  String? submittedMethod;
  double? submittedAmount;
  String? submittedIdempotencyKey;
  String? proofPaymentId;

  @override
  Future<PaymentView> view(String requestId) async {
    final ApiFailure? failure = viewError;
    if (failure != null) throw failure;
    return viewValue;
  }

  @override
  Future<PaymentRecord> submit({
    required String requestId,
    required String method,
    required double amount,
    String? referenceNumber,
    required bool isDeposit,
    required String idempotencyKey,
  }) async {
    submittedMethod = method;
    submittedAmount = amount;
    submittedIdempotencyKey = idempotencyKey;
    final ApiFailure? failure = submitError;
    if (failure != null) throw failure;
    return PaymentRecord(
      id: 'pay-new',
      requestId: requestId,
      amount: amount,
      method: method,
      // Never verified on the way in: only finance can set that.
      status: 'VERIFICATION_PENDING',
      isDeposit: isDeposit,
      amountRefunded: 0,
    );
  }

  @override
  Future<void> uploadProof({
    required String requestId,
    required String paymentId,
    required String filePath,
    required String fileName,
  }) async {
    proofPaymentId = paymentId;
    final ApiFailure? failure = proofError;
    if (failure != null) throw failure;
  }

  @override
  Future<List<PaymentMethodOption>> paymentMethods() async => methodsValue;

  @override
  Future<List<RefundRecord>> refunds(String requestId) async => refundsValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
