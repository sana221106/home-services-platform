import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_colors.dart';

/// How urgent or final a status is, so widgets pick a colour by role and never
/// by hard-coding a hue per screen (§45, §117).
enum StatusTone { neutral, progress, attention, success, danger }

/// The request lifecycle exactly as the backend defines it (`RequestStatus`).
///
/// Mirrored rather than invented, because the client must not invent states the
/// server does not have. `fromCode` returns null for anything unknown so a
/// backend addition degrades to a neutral label instead of crashing (§8).
enum AppRequestStatus {
  draft('DRAFT', StatusTone.neutral),
  submitted('SUBMITTED', StatusTone.neutral),
  underReview('UNDER_REVIEW', StatusTone.progress),
  needMoreInformation('NEED_MORE_INFORMATION', StatusTone.attention),
  inspectionRequired('INSPECTION_REQUIRED', StatusTone.attention),
  inspectionScheduled('INSPECTION_SCHEDULED', StatusTone.progress),
  inspectionInProgress('INSPECTION_IN_PROGRESS', StatusTone.progress),
  inspectionCompleted('INSPECTION_COMPLETED', StatusTone.progress),
  quotePreparation('QUOTE_PREPARATION', StatusTone.progress),
  quoteSent('QUOTE_SENT', StatusTone.attention),
  awaitingCustomerApproval('AWAITING_CUSTOMER_APPROVAL', StatusTone.attention),
  quoteRejected('QUOTE_REJECTED', StatusTone.danger),
  depositPending('DEPOSIT_PENDING', StatusTone.attention),
  depositVerification('DEPOSIT_VERIFICATION', StatusTone.attention),
  confirmed('CONFIRMED', StatusTone.success),
  technicianAssignmentPending(
    'TECHNICIAN_ASSIGNMENT_PENDING',
    StatusTone.progress,
  ),
  technicianAssigned('TECHNICIAN_ASSIGNED', StatusTone.progress),
  onTheWay('ON_THE_WAY', StatusTone.progress),
  arrived('ARRIVED', StatusTone.progress),
  workInProgress('WORK_IN_PROGRESS', StatusTone.progress),
  serviceCompleted('SERVICE_COMPLETED', StatusTone.success),
  paymentPending('PAYMENT_PENDING', StatusTone.attention),
  paymentVerification('PAYMENT_VERIFICATION', StatusTone.attention),
  paid('PAID', StatusTone.success),
  awaitingRating('AWAITING_RATING', StatusTone.attention),
  complaintOpen('COMPLAINT_OPEN', StatusTone.danger),
  complaintUnderReview('COMPLAINT_UNDER_REVIEW', StatusTone.attention),
  revisitScheduled('REVISIT_SCHEDULED', StatusTone.progress),
  resolved('RESOLVED', StatusTone.success),
  closed('CLOSED', StatusTone.neutral),
  cancelled('CANCELLED', StatusTone.danger);

  const AppRequestStatus(this.code, this.tone);

  /// The wire value, byte-identical to the backend enum member.
  final String code;

  final StatusTone tone;

  /// Parses a backend status, tolerating case and surrounding whitespace.
  static AppRequestStatus? fromCode(String? code) {
    if (code == null) return null;
    final String needle = code.trim().toUpperCase();
    for (final AppRequestStatus status in AppRequestStatus.values) {
      if (status.code == needle) return status;
    }
    return null;
  }

  /// Whether the request can still be cancelled. Mirrors the backend policy
  /// rather than re-deciding it, so the client never hides a button the server
  /// would refuse (§8).
  bool get isTerminal =>
      const <AppRequestStatus>{closed, cancelled, resolved}.contains(this);
}

extension AppRequestStatusL10n on AppRequestStatus {
  /// Arabic copy from ARB. Unknown statuses fall back to the code itself so a
  /// new backend state is visible rather than silently blank.
  String label(AppLocalizations l10n) => switch (this) {
    AppRequestStatus.draft => l10n.requestStatusDraft,
    AppRequestStatus.submitted => l10n.requestStatusSubmitted,
    AppRequestStatus.underReview => l10n.requestStatusUnderReview,
    AppRequestStatus.needMoreInformation => l10n.requestStatusNeedMoreInfo,
    AppRequestStatus.inspectionRequired => l10n.requestStatusInspectionRequired,
    AppRequestStatus.inspectionScheduled =>
      l10n.requestStatusInspectionScheduled,
    AppRequestStatus.inspectionInProgress =>
      l10n.requestStatusInspectionInProgress,
    AppRequestStatus.inspectionCompleted =>
      l10n.requestStatusInspectionCompleted,
    AppRequestStatus.quotePreparation => l10n.requestStatusQuotePreparation,
    AppRequestStatus.quoteSent => l10n.requestStatusQuoteSent,
    AppRequestStatus.awaitingCustomerApproval =>
      l10n.requestStatusAwaitingApproval,
    AppRequestStatus.quoteRejected => l10n.requestStatusQuoteRejected,
    AppRequestStatus.depositPending => l10n.requestStatusDepositPending,
    AppRequestStatus.depositVerification =>
      l10n.requestStatusDepositVerification,
    AppRequestStatus.confirmed => l10n.requestStatusConfirmed,
    AppRequestStatus.technicianAssignmentPending =>
      l10n.requestStatusAssignmentPending,
    AppRequestStatus.technicianAssigned => l10n.requestStatusTechnicianAssigned,
    AppRequestStatus.onTheWay => l10n.requestStatusOnTheWay,
    AppRequestStatus.arrived => l10n.requestStatusArrived,
    AppRequestStatus.workInProgress => l10n.requestStatusWorkInProgress,
    AppRequestStatus.serviceCompleted => l10n.requestStatusServiceCompleted,
    AppRequestStatus.paymentPending => l10n.requestStatusPaymentPending,
    AppRequestStatus.paymentVerification =>
      l10n.requestStatusPaymentVerification,
    AppRequestStatus.paid => l10n.requestStatusPaid,
    AppRequestStatus.awaitingRating => l10n.requestStatusAwaitingRating,
    AppRequestStatus.complaintOpen => l10n.requestStatusComplaintOpen,
    AppRequestStatus.complaintUnderReview =>
      l10n.requestStatusComplaintUnderReview,
    AppRequestStatus.revisitScheduled => l10n.requestStatusRevisitScheduled,
    AppRequestStatus.resolved => l10n.requestStatusResolved,
    AppRequestStatus.closed => l10n.requestStatusClosed,
    AppRequestStatus.cancelled => l10n.requestStatusCancelled,
  };

  /// Colour for this status's tone, resolved through the active palette so
  /// dark mode needs no per-screen branch.
  Color color(AppColors colors) => switch (tone) {
    StatusTone.neutral => colors.textSecondary,
    StatusTone.progress => colors.primary,
    StatusTone.attention => colors.warning,
    StatusTone.success => colors.success,
    StatusTone.danger => colors.danger,
  };
}

/// Convenience for widgets: one call for label plus colour.
({String label, Color color}) requestStatusPresentation(
  BuildContext context,
  String? code,
) {
  final AppRequestStatus? status = AppRequestStatus.fromCode(code);
  if (status == null) {
    final AppColors colors = AppColors.of(context);
    return (
      label: code ?? context.l10n.requestStatusUnknown,
      color: colors.textSecondary,
    );
  }
  return (
    label: status.label(context.l10n),
    color: status.color(AppColors.of(context)),
  );
}
