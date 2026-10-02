import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

import '../../../../core/errors/failure.dart';
import '../../data/models/payment_models.dart';
import '../../data/repositories/payments_repository.dart';

enum PaymentsStatus { initial, loading, ready, failed }

class PaymentsState extends Equatable {
  const PaymentsState({
    this.status = PaymentsStatus.initial,
    this.view,
    this.methods = const <PaymentMethodOption>[],
    this.refunds = const <RefundRecord>[],
    this.errorMessage,
    this.isSubmitting = false,
    this.isUploadingProof = false,
    this.uploadingPaymentId,
  });

  final PaymentsStatus status;
  final PaymentView? view;
  final List<PaymentMethodOption> methods;
  final List<RefundRecord> refunds;
  final String? errorMessage;
  final bool isSubmitting;

  /// Proof upload is tracked per payment so the spinner lands on the row being
  /// uploaded instead of blanking the whole screen.
  final bool isUploadingProof;
  final String? uploadingPaymentId;

  PaymentsState copyWith({
    PaymentsStatus? status,
    PaymentView? view,
    List<PaymentMethodOption>? methods,
    List<RefundRecord>? refunds,
    String? errorMessage,
    bool? isSubmitting,
    bool? isUploadingProof,
    String? uploadingPaymentId,
    bool clearError = false,
    bool clearUploading = false,
  }) {
    return PaymentsState(
      status: status ?? this.status,
      view: view ?? this.view,
      methods: methods ?? this.methods,
      refunds: refunds ?? this.refunds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isUploadingProof: clearUploading
          ? false
          : (isUploadingProof ?? this.isUploadingProof),
      uploadingPaymentId: clearUploading
          ? null
          : (uploadingPaymentId ?? this.uploadingPaymentId),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    view,
    methods,
    refunds,
    errorMessage,
    isSubmitting,
    isUploadingProof,
    uploadingPaymentId,
  ];
}

/// The Payment screen for one request.
///
/// The view and the method catalogue are separate reads because the view already
/// carries the request's totals; the catalogue is what tells the app whether the
/// chosen method needs a receipt image.
class PaymentsController extends Notifier<PaymentsState> {
  PaymentsController(this.requestId);

  final String requestId;

  @override
  PaymentsState build() {
    Future<void>.microtask(load);
    return const PaymentsState(status: PaymentsStatus.loading);
  }

  Future<void> load() async {
    state = state.copyWith(status: PaymentsStatus.loading, clearError: true);
    try {
      // The three reads are independent, so they run together.
      final results = await Future.wait<Object?>(<Future<Object?>>[
        ref.read(paymentsRepositoryProvider).view(requestId),
        ref.read(paymentsRepositoryProvider).paymentMethods(),
        ref.read(paymentsRepositoryProvider).refunds(requestId),
      ]);

      state = PaymentsState(
        status: PaymentsStatus.ready,
        view: results[0] as PaymentView,
        methods: results[1]! as List<PaymentMethodOption>,
        refunds: results[2]! as List<RefundRecord>,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: PaymentsStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  /// Submits evidence, then reloads.
  ///
  /// The record that comes back is pending, never verified, so refetching is
  /// what keeps the list and the outstanding total in step with finance.
  Future<PaymentRecord?> submit({
    required String method,
    required double amount,
    String? referenceNumber,
    required bool isDeposit,
  }) async {
    if (state.isSubmitting) return null;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final PaymentRecord payment = await ref
          .read(paymentsRepositoryProvider)
          .submit(
            requestId: requestId,
            method: method,
            amount: amount,
            referenceNumber: referenceNumber,
            isDeposit: isDeposit,
            idempotencyKey: _idempotencyKey(),
          );
      await load();
      return payment;
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: failure.message,
      );
      return null;
    }
  }

  /// Uploads the receipt for an already-submitted payment.
  Future<bool> uploadProof({
    required String paymentId,
    required String filePath,
    required String fileName,
  }) async {
    if (state.isUploadingProof) return false;

    state = state.copyWith(
      isUploadingProof: true,
      uploadingPaymentId: paymentId,
      clearError: true,
    );
    try {
      await ref
          .read(paymentsRepositoryProvider)
          .uploadProof(
            requestId: requestId,
            paymentId: paymentId,
            filePath: filePath,
            fileName: fileName,
          );
      await load();
      return true;
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        isUploadingProof: false,
        errorMessage: failure.message,
      );
      return false;
    }
  }

  /// A random key per attempt. The backend scopes it to the request, so a
  /// retried submit returns the original payment instead of a second one, while
  /// a genuinely new payment gets a new key.
  String _idempotencyKey() {
    final Random random = Random.secure();
    final String suffix = random.nextInt(1 << 32).toRadixString(16);
    return 'app-$suffix-${DateTime.now().millisecondsSinceEpoch}';
  }
}

final NotifierProviderFamily<PaymentsController, PaymentsState, String>
paymentsProvider =
    NotifierProvider.family<PaymentsController, PaymentsState, String>(
      PaymentsController.new,
      name: 'payments',
    );
