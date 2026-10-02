import 'package:equatable/equatable.dart';

import '../../../../core/network/json_readers.dart';

/// One payment the customer submitted.
///
/// A customer-submitted payment never carries `VERIFIED` on the way in: the
/// backend keeps that for staff, which is why [status] is kept as a raw code
/// rather than collapsed into a boolean here.
class PaymentRecord extends Equatable {
  const PaymentRecord({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    required this.amountRefunded,
    this.requestId,
    this.referenceNumber,
    this.isDeposit = false,
    this.recordedAt,
    this.verifiedAt,
    this.rejectionReason,
    this.proofUrl,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    return PaymentRecord(
      id: json.strOr('id', ''),
      requestId: json.str('request_id'),
      amount: json.decimal('amount') ?? 0,
      method: json.strOr('method', 'CASH'),
      status: json.strOr('status', 'PENDING'),
      referenceNumber: json.str('reference_number'),
      isDeposit: json.flag('is_deposit'),
      amountRefunded: json.decimal('amount_refunded') ?? 0,
      recordedAt: json.time('recorded_at'),
      verifiedAt: json.time('verified_at'),
      rejectionReason: json.str('rejection_reason'),
      proofUrl: json.str('proof_url'),
    );
  }

  final String id;
  final String? requestId;
  final double amount;
  final String method;
  final String status;
  final String? referenceNumber;
  final bool isDeposit;
  final double amountRefunded;
  final DateTime? recordedAt;
  final DateTime? verifiedAt;
  final String? rejectionReason;
  final String? proofUrl;

  /// Cash paid in person has no transfer reference to type in.
  bool get needsReference => method != 'CASH';

  bool get hasProof => proofUrl != null && proofUrl!.isNotEmpty;

  bool get isRejected => status == 'REJECTED';

  /// A rejection is the one case where the server explains itself, so it is
  /// shown in full rather than trimmed to a chip.
  bool get hasRejectionReason =>
      rejectionReason != null && rejectionReason!.isNotEmpty;

  /// Anything not settled keeps the customer waiting on the finance team.
  bool get isPending => !isSettled;

  bool get isSettled => switch (status) {
    'VERIFIED' => true,
    'REFUNDED' || 'PARTIALLY_REFUNDED' => true,
    _ => false,
  };

  @override
  List<Object?> get props => <Object?>[
    id,
    amount,
    method,
    status,
    referenceNumber,
    isDeposit,
    amountRefunded,
    recordedAt,
    verifiedAt,
    rejectionReason,
    proofUrl,
  ];
}

/// The deposit obligation attached to a request.
class DepositObligation extends Equatable {
  const DepositObligation({
    required this.requestId,
    required this.requiredAmount,
    required this.paidAmount,
    required this.refundedAmount,
    required this.status,
    this.dueAt,
  });

  factory DepositObligation.fromJson(Map<String, dynamic> json) {
    return DepositObligation(
      requestId: json.strOr('request_id', ''),
      requiredAmount: json.decimal('required_amount') ?? 0,
      paidAmount: json.decimal('paid_amount') ?? 0,
      refundedAmount: json.decimal('refunded_amount') ?? 0,
      status: json.strOr('status', 'NOT_REQUIRED'),
      dueAt: json.time('due_at'),
    );
  }

  final String requestId;
  final double requiredAmount;
  final double paidAmount;
  final double refundedAmount;
  final String status;
  final DateTime? dueAt;

  /// The outstanding part of the deposit, floored at zero.
  ///
  /// A refund discharges the obligation rather than enlarging it, so it is read
  /// as "settled" rather than folded into this number: money handed back is not
  /// money still owed.
  double get outstandingAmount {
    if (status == 'REFUNDED') return 0;
    final double due = requiredAmount - paidAmount;
    return due <= 0 ? 0 : due;
  }

  bool get isSatisfied => outstandingAmount <= 0;

  /// `NOT_REQUIRED` is not the same as satisfied: one means nobody asked for a
  /// deposit, the other means it is paid off.
  bool get isRequired => status != 'NOT_REQUIRED' && requiredAmount > 0;

  @override
  List<Object?> get props => <Object?>[
    requestId,
    requiredAmount,
    paidAmount,
    refundedAmount,
    status,
    dueAt,
  ];
}

/// A refund the customer is told about.
class RefundRecord extends Equatable {
  const RefundRecord({
    required this.id,
    required this.paymentId,
    required this.amount,
    required this.reason,
    required this.status,
    this.approvedAt,
    this.processedAt,
  });

  factory RefundRecord.fromJson(Map<String, dynamic> json) {
    return RefundRecord(
      id: json.strOr('id', ''),
      paymentId: json.strOr('payment_id', ''),
      amount: json.decimal('amount') ?? 0,
      reason: json.strOr('reason', ''),
      status: json.strOr('status', 'PENDING'),
      approvedAt: json.time('approved_at'),
      processedAt: json.time('processed_at'),
    );
  }

  final String id;
  final String paymentId;
  final double amount;
  final String reason;
  final String status;
  final DateTime? approvedAt;
  final DateTime? processedAt;

  bool get isProcessed => status == 'PROCESSED';

  @override
  List<Object?> get props => <Object?>[
    id,
    paymentId,
    amount,
    reason,
    status,
    approvedAt,
    processedAt,
  ];
}

/// A payment method the app may offer, with the wording the backend sends.
///
/// `requiresProof` comes from the server because the finance flow differs per
/// method: cash needs no receipt, a wallet transfer does.
class PaymentMethodOption extends Equatable {
  const PaymentMethodOption({
    required this.code,
    required this.labelAr,
    this.instructionsAr,
    this.requiresProof = true,
  });

  factory PaymentMethodOption.fromJson(Map<String, dynamic> json) {
    return PaymentMethodOption(
      code: json.strOr('code', ''),
      labelAr: json.strOr('label_ar', ''),
      instructionsAr: json.str('instructions_ar'),
      requiresProof: json.flag('requires_proof', fallback: true),
    );
  }

  final String code;
  final String labelAr;
  final String? instructionsAr;
  final bool requiresProof;

  /// Fallback so a code the enum gains later still gets a chip instead of an
  /// empty tile.
  String get label => labelAr.isEmpty ? code : labelAr;

  @override
  List<Object?> get props => <Object?>[
    code,
    labelAr,
    instructionsAr,
    requiresProof,
  ];
}

/// Everything the Payment screen renders, from `GET /requests/{id}/payment`.
class PaymentView extends Equatable {
  const PaymentView({
    required this.requestId,
    required this.referenceCode,
    required this.amountDue,
    required this.methods,
    required this.payments,
    this.quoteTotal,
    this.deposit,
    this.supportPhone,
    this.instructionsAr,
  });

  factory PaymentView.fromJson(Map<String, dynamic> json) {
    return PaymentView(
      requestId: json.strOr('request_id', ''),
      referenceCode: json.strOr('reference_code', ''),
      quoteTotal: json.decimal('quote_total'),
      deposit: json.objOrNull('deposit') == null
          ? null
          : DepositObligation.fromJson(json.obj('deposit')),
      payments: json
          .mapList('payments')
          .map(PaymentRecord.fromJson)
          .toList(growable: false),
      amountDue: json.decimal('amount_due') ?? 0,
      methods: json.stringList('methods'),
      supportPhone: json.str('support_phone'),
      instructionsAr: json.str('instructions_ar'),
    );
  }

  final String requestId;
  final String referenceCode;
  final double? quoteTotal;
  final DepositObligation? deposit;
  final List<PaymentRecord> payments;
  final double amountDue;

  /// Codes from the payment view, not from a hard-coded list.
  final List<String> methods;
  final String? supportPhone;

  /// Server wording, because the finance team owns these instructions.
  final String? instructionsAr;

  bool get hasPayments => payments.isNotEmpty;

  bool get hasDeposit => deposit != null && deposit!.isRequired;

  bool get isSettled => amountDue <= 0;

  /// Nothing left to pay and nothing still being verified.
  bool get hasOpenPayment =>
      payments.any((PaymentRecord payment) => payment.isPending);

  @override
  List<Object?> get props => <Object?>[
    requestId,
    referenceCode,
    quoteTotal,
    deposit,
    payments,
    amountDue,
    methods,
    supportPhone,
    instructionsAr,
  ];
}
