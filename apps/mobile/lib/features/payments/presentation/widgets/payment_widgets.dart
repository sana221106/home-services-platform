import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/payment_models.dart';

/// Payment status wording, mirroring the backend `PaymentStatus` enum.
///
/// An unknown status renders as its own code so a status the server adds is
/// visible rather than silently blank.
String paymentStatusLabel(BuildContext context, String status) {
  final AppLocalizations l10n = context.l10n;
  return switch (status) {
    'PENDING' => l10n.paymentStatusPending,
    'VERIFICATION_PENDING' => l10n.paymentStatusVerificationPending,
    'VERIFIED' => l10n.paymentStatusVerified,
    'REJECTED' => l10n.paymentStatusRejected,
    'REFUNDED' => l10n.paymentStatusRefunded,
    'PARTIALLY_REFUNDED' => l10n.paymentStatusPartiallyRefunded,
    _ => status.isEmpty ? l10n.paymentStatusPending : status,
  };
}

/// Refund status wording, mirroring the backend `RefundStatus` enum.
String refundStatusLabel(BuildContext context, String status) {
  final AppLocalizations l10n = context.l10n;
  return switch (status) {
    'APPROVED' => l10n.paymentRefundApproved,
    'PROCESSED' => l10n.paymentRefundProcessed,
    'REJECTED' => l10n.paymentRefundRejected,
    _ => l10n.paymentRefundPending,
  };
}

/// The deposit panel.
///
/// Shown whenever the backend attaches a deposit to the request, including when
/// it is already paid: the customer needs to see that the deposit cleared, not
/// only that one was demanded.
class DepositCard extends StatelessWidget {
  const DepositCard({required this.deposit, super.key});

  final DepositObligation deposit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.requestDepositTitle,
                  style: context.text.title,
                ),
              ),
              AppChip(
                label: deposit.isSatisfied
                    ? l10n.paymentDepositPaid
                    : l10n.paymentDepositOutstanding,
                color: deposit.isSatisfied ? colors.success : colors.warning,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          InfoRow(
            label: l10n.requestDepositAmount,
            value: formatMoney(deposit.requiredAmount.toStringAsFixed(2)),
          ),
          InfoRow(
            label: l10n.paymentAmountPaid,
            value: formatMoney(deposit.paidAmount.toStringAsFixed(2)),
          ),
          // A deposit still shows its refund history: the customer needs to see
          // what came back, not only what is left.
          if (deposit.refundedAmount > 0)
            InfoRow(
              label: l10n.paymentRefundedAmount,
              value: formatMoney(deposit.refundedAmount.toStringAsFixed(2)),
            ),
          if (deposit.dueAt != null)
            InfoRow(
              label: l10n.paymentDueDate,
              value: formatDateTime(deposit.dueAt, l10n: l10n),
            ),
        ],
      ),
    );
  }
}

/// One submitted payment.
///
/// The status chip is the centre of this row: a customer who submitted evidence
/// needs to see it is waiting on finance, not gone.
class PaymentTile extends StatelessWidget {
  const PaymentTile({
    required this.payment,
    this.onAttachProof,
    this.isUploading = false,
    super.key,
  });

  final PaymentRecord payment;

  /// Offered only while a receipt is still meaningful; null hides the action.
  final VoidCallback? onAttachProof;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  formatMoney(payment.amount.toStringAsFixed(2)),
                  style: context.text.title,
                ),
              ),
              AppChip(
                label: paymentStatusLabel(context, payment.status),
                color: payment.isRejected
                    ? colors.danger
                    : (payment.isSettled ? colors.success : colors.warning),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(_methodLabel(context, payment.method), style: context.text.body),
          if (payment.isDeposit) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            AppChip(label: l10n.requestDepositTitle, color: colors.primary),
          ],

          if (payment.referenceNumber != null &&
              payment.referenceNumber!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            InfoRow(
              label: l10n.paymentReferenceNumber,
              value: payment.referenceNumber!,
            ),
          ],

          if (payment.recordedAt != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              formatDateTime(payment.recordedAt, l10n: l10n),
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
          ],

          // A rejection is the one case where the server explains itself, so it
          // gets the full sentence rather than being trimmed into the chip.
          if (payment.hasRejectionReason) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '${l10n.paymentRejectedReason}: ${payment.rejectionReason}',
                style: context.text.caption.copyWith(color: colors.danger),
              ),
            ),
          ],

          if (payment.verifiedAt != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                const Icon(Icons.verified, size: 16),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    '${l10n.paymentVerifiedOn} ${formatDateTime(payment.verifiedAt, l10n: l10n)}',
                    style: context.text.caption.copyWith(color: colors.success),
                  ),
                ),
              ],
            ),
          ],

          if (payment.amountRefunded > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${l10n.paymentRefundedAmount}: '
              '${formatMoney(payment.amountRefunded.toStringAsFixed(2))}',
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
          ],

          if (onAttachProof != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            if (payment.hasProof)
              Row(
                children: <Widget>[
                  Icon(Icons.check_circle, size: 16, color: colors.success),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    l10n.paymentReceiptAttached,
                    style: context.text.caption.copyWith(color: colors.success),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                key: Key('attach-proof-${payment.id}'),
                onPressed: isUploading ? null : onAttachProof,
                icon: isUploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.receipt_long, size: 16),
                label: Text(l10n.paymentAttachReceipt),
              ),
          ],
        ],
      ),
    );
  }

  /// Falls back to the raw code so a method the app has no label for still
  /// names itself on screen.
  String _methodLabel(BuildContext context, String method) {
    final AppLocalizations l10n = context.l10n;
    return switch (method) {
      'CASH' => l10n.paymentMethodCash,
      'VODAFONE_CASH' => l10n.paymentMethodVodafoneCash,
      'INSTAPAY' => l10n.paymentMethodInstaPay,
      _ => method,
    };
  }
}

/// One refund row.
class RefundTile extends StatelessWidget {
  const RefundTile({required this.refund, super.key});

  final RefundRecord refund;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(Icons.undo, size: 18, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  formatMoney(refund.amount.toStringAsFixed(2)),
                  style: context.text.labelStrong,
                ),
                Text(
                  refund.reason,
                  style: context.text.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          AppChip(
            label: refundStatusLabel(context, refund.status),
            color: refund.isProcessed ? colors.success : colors.warning,
          ),
        ],
      ),
    );
  }
}
