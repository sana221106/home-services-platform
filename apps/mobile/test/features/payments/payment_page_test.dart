import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';
import 'package:home_services_app/features/payments/data/models/payment_models.dart';
import 'package:home_services_app/features/payments/data/repositories/payments_repository.dart';
import 'package:home_services_app/features/payments/presentation/pages/payment_page.dart';

void main() {
  group('PaymentRecord', () {
    test('parses the payload including refunds and proof', () {
      final PaymentRecord payment = PaymentRecord.fromJson(<String, dynamic>{
        'id': 'pay-1',
        'request_id': 'req-1',
        'amount': '310.00',
        'method': 'VODAFONE_CASH',
        'status': 'VERIFICATION_PENDING',
        'reference_number': '778899',
        'is_deposit': true,
        'amount_refunded': '10.00',
        'recorded_at': '2026-01-01T10:00:00Z',
        'verified_at': null,
        'rejection_reason': null,
        'proof_url': 'https://cdn.example/proof.jpg',
      });

      expect(payment.amount, 310);
      expect(payment.needsReference, isTrue);
      expect(payment.hasProof, isTrue);
      expect(payment.isDeposit, isTrue);
      expect(payment.isPending, isTrue);
      expect(payment.isSettled, isFalse);
    });

    test(
      'cash needs no transfer reference and a verified payment is settled',
      () {
        final PaymentRecord payment = PaymentRecord.fromJson(<String, dynamic>{
          'id': 'pay-2',
          'amount': '100.00',
          'method': 'CASH',
          'status': 'VERIFIED',
          'is_deposit': false,
          'amount_refunded': '0.00',
        });

        expect(payment.needsReference, isFalse);
        expect(payment.isSettled, isTrue);
        expect(payment.hasProof, isFalse);
        expect(payment.hasRejectionReason, isFalse);
      },
    );

    test('a rejection keeps the server explanation', () {
      final PaymentRecord payment = PaymentRecord.fromJson(<String, dynamic>{
        'id': 'pay-3',
        'amount': '100.00',
        'method': 'INSTAPAY',
        'status': 'REJECTED',
        'is_deposit': false,
        'amount_refunded': '0.00',
        'rejection_reason': 'Reference number does not match',
      });

      expect(payment.isRejected, isTrue);
      expect(payment.hasRejectionReason, isTrue);
    });
  });

  group('DepositObligation', () {
    test('the outstanding part is what is still owed', () {
      final DepositObligation deposit =
          DepositObligation.fromJson(<String, dynamic>{
            'request_id': 'req-1',
            'required_amount': '150.00',
            'paid_amount': '50.00',
            'refunded_amount': '0.00',
            'status': 'PENDING',
            'due_at': '2026-01-05T10:00:00Z',
          });

      expect(deposit.outstandingAmount, 100);
      expect(deposit.isSatisfied, isFalse);
      expect(deposit.isRequired, isTrue);
    });

    test('a refund lowers the obligation and never goes negative', () {
      final DepositObligation deposit =
          DepositObligation.fromJson(<String, dynamic>{
            'request_id': 'req-1',
            'required_amount': '150.00',
            'paid_amount': '150.00',
            'refunded_amount': '200.00',
            'status': 'REFUNDED',
          });

      expect(deposit.outstandingAmount, 0);
      expect(deposit.isSatisfied, isTrue);
    });

    test('not required is not the same as satisfied', () {
      final DepositObligation deposit =
          DepositObligation.fromJson(<String, dynamic>{
            'request_id': 'req-1',
            'required_amount': '0.00',
            'paid_amount': '0.00',
            'refunded_amount': '0.00',
            'status': 'NOT_REQUIRED',
          });

      expect(deposit.isRequired, isFalse);
      expect(deposit.isSatisfied, isTrue);
    });
  });

  group('PaymentView', () {
    test('parses the whole Payment screen payload', () {
      final PaymentView view = PaymentView.fromJson(<String, dynamic>{
        'request_id': 'req-1',
        'reference_code': 'REQ-0001',
        'quote_total': '500.00',
        'deposit': <String, dynamic>{
          'request_id': 'req-1',
          'required_amount': '150.00',
          'paid_amount': '0.00',
          'refunded_amount': '0.00',
          'status': 'PENDING',
        },
        'payments': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'pay-1',
            'amount': '150.00',
            'method': 'CASH',
            'status': 'PENDING',
            'is_deposit': true,
            'amount_refunded': '0.00',
          },
        ],
        'amount_due': '500.00',
        'methods': <String>['CASH', 'VODAFONE_CASH', 'INSTAPAY'],
        'support_phone': '+201000000000',
        'instructions_ar': 'أرسل المبلغ ثم أدخل الرقم المرجعي.',
      });

      expect(view.quoteTotal, 500);
      expect(view.hasDeposit, isTrue);
      expect(view.hasPayments, isTrue);
      expect(view.hasOpenPayment, isTrue);
      expect(view.isSettled, isFalse);
      expect(view.methods, hasLength(3));
      expect(view.instructionsAr, isNotNull);
    });

    test('a missing deposit does not become a zero-valued obligation', () {
      final PaymentView view = PaymentView.fromJson(<String, dynamic>{
        'request_id': 'req-1',
        'reference_code': 'REQ-0002',
        'deposit': null,
        'payments': <Map<String, dynamic>>[],
        'amount_due': '0.00',
        'methods': <String>['CASH'],
        'support_phone': '+201000000000',
      });

      expect(view.deposit, isNull);
      expect(view.hasDeposit, isFalse);
      expect(view.isSettled, isTrue);
    });
  });

  group('PaymentPage', () {
    testWidgets('shows the outstanding amount, deposit and history', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakePaymentsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Amount due'), findsOneWidget);
      expect(find.text('250.00 EGP'), findsOneWidget);
      // Twice on purpose: the deposit panel's title, and the marker on the payment
      // that settled it.
      expect(find.text('Deposit'), findsNWidgets(2));
      expect(find.text('150.00 EGP'), findsWidgets);
      expect(find.text('Verification pending'), findsWidgets);
    });

    testWidgets('a settled request hides the submit action', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakePaymentsRepository()
            ..viewValue = _view(amountDue: 0, withPayment: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing left to pay'), findsOneWidget);
      // Offering payment when nothing is owed would invite a duplicate.
      expect(find.byKey(const Key('payment-submit')), findsNothing);
    });

    testWidgets('an open payment keeps the submit action available', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakePaymentsRepository()));
      await tester.pumpAndSettle();

      // The action sits at the bottom of the list, so it is scrolled to rather
      // than assumed visible.
      await tester.scrollUntilVisible(
        find.byKey(const Key('payment-submit')),
        300,
      );
      expect(find.byKey(const Key('payment-submit')), findsOneWidget);
    });

    testWidgets('the refund list appears when the server sends refunds', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakePaymentsRepository()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Refunds'), 300);
      expect(find.text('Refunds'), findsOneWidget);
      expect(find.text('100.00 EGP'), findsWidgets);
      expect(find.text('Processed'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that refetches', (
      WidgetTester tester,
    ) async {
      final _FakePaymentsRepository repository = _FakePaymentsRepository()
        ..viewError = const ApiFailure(
          code: 'NETWORK',
          message: 'Payments unavailable',
        );
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Payments unavailable'), findsOneWidget);

      repository.viewError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Amount due'), findsOneWidget);
    });

    testWidgets('a rejection shows the finance reason in full', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakePaymentsRepository()
            ..viewValue = _view(rejectionReason: 'Reference does not match'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Reference does not match'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
    });
  });
}

PaymentView _view({
  double amountDue = 250,
  bool withPayment = true,
  String? rejectionReason,
}) {
  return PaymentView(
    requestId: 'req-1',
    referenceCode: 'REQ-0001',
    quoteTotal: 500,
    deposit: DepositObligation(
      requestId: 'req-1',
      requiredAmount: 150,
      paidAmount: 0,
      refundedAmount: 0,
      status: 'PENDING',
    ),
    payments: <PaymentRecord>[
      if (withPayment)
        PaymentRecord(
          id: 'pay-1',
          amount: 150,
          method: 'VODAFONE_CASH',
          status: rejectionReason == null ? 'VERIFICATION_PENDING' : 'REJECTED',
          isDeposit: true,
          amountRefunded: 0,
          rejectionReason: rejectionReason,
        ),
    ],
    amountDue: amountDue,
    methods: const <String>['CASH', 'VODAFONE_CASH', 'INSTAPAY'],
    supportPhone: '+201000000000',
    instructionsAr: 'أرسل المبلغ ثم أدخل الرقم المرجعي.',
  );
}

Widget _wrap(_FakePaymentsRepository repository) {
  return ProviderScope(
    overrides: <Override>[
      paymentsRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PaymentPage(requestId: 'req-1'),
    ),
  );
}

class _FakePaymentsRepository implements PaymentsRepository {
  PaymentView viewValue = _view();
  ApiFailure? viewError;
  ApiFailure? submitError;
  ApiFailure? proofError;

  @override
  Future<PaymentView> view(String requestId) async {
    final ApiFailure? failure = viewError;
    if (failure != null) throw failure;
    return viewValue;
  }

  @override
  Future<List<RefundRecord>> refunds(String requestId) async => <RefundRecord>[
    const RefundRecord(
      id: 'ref-1',
      paymentId: 'pay-0',
      amount: 100,
      reason: 'Overcharge',
      status: 'PROCESSED',
    ),
  ];

  @override
  Future<List<PaymentMethodOption>> paymentMethods() async =>
      <PaymentMethodOption>[
        const PaymentMethodOption(
          code: 'CASH',
          labelAr: 'Cash',
          requiresProof: false,
        ),
        const PaymentMethodOption(
          code: 'VODAFONE_CASH',
          labelAr: 'Vodafone Cash',
        ),
        const PaymentMethodOption(code: 'INSTAPAY', labelAr: 'InstaPay'),
      ];

  @override
  Future<PaymentRecord> submit({
    required String requestId,
    required String method,
    required double amount,
    String? referenceNumber,
    required bool isDeposit,
    required String idempotencyKey,
  }) async {
    final ApiFailure? failure = submitError;
    if (failure != null) throw failure;
    return PaymentRecord(
      id: 'pay-new',
      requestId: requestId,
      amount: amount,
      method: method,
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
    final ApiFailure? failure = proofError;
    if (failure != null) throw failure;
  }

  @override
  Future<List<PaymentRecord>> payments(String requestId) async =>
      <PaymentRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
