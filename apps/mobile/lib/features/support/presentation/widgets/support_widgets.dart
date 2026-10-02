import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/support_models.dart';

/// One thread row: subject, preview and unread badge.
class ConversationTile extends StatelessWidget {
  const ConversationTile({required this.conversation, this.onTap, super.key});

  final Conversation conversation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final String subject = conversation.subject.isEmpty
        ? l10n.supportDefaultSubject
        : conversation.subject;
    final String? preview = conversation.lastMessagePreview;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  subject,
                  style: context.text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!conversation.isOpen)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.xs,
                  ),
                  child: AppChip(
                    label: l10n.supportThreadClosed,
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
          if (preview != null && preview.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              preview,
              style: context.text.caption.copyWith(color: colors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              // An unread count is a number, not a dot: the customer needs to
              // know whether it is one message or five.
              if (conversation.isUnread)
                AppChip(
                  label: l10n.supportUnreadCount(conversation.unreadCount),
                  color: colors.primary,
                  icon: 'assets/icons/notif.svg',
                ),
              const Spacer(),
              if (conversation.lastMessageAt != null)
                Text(
                  formatRelative(conversation.lastMessageAt, l10n: l10n),
                  style: context.text.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One message bubble.
///
/// The customer's own messages are tinted and end-aligned so the thread reads
/// as a conversation without needing an avatar per message.
class MessageBubble extends StatelessWidget {
  const MessageBubble({required this.message, super.key});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final bool mine = message.isFromCustomer;

    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: mine ? colors.primary : colors.surfaceVariant,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.lg),
            topRight: const Radius.circular(AppRadius.lg),
            bottomLeft: Radius.circular(mine ? AppRadius.lg : 4),
            bottomRight: Radius.circular(mine ? 4 : AppRadius.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              message.body,
              style: context.text.body.copyWith(
                color: mine ? Colors.white : colors.textPrimary,
              ),
            ),
            if (message.sentAt != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                formatDateTime(message.sentAt, l10n: context.l10n),
                style: context.text.caption.copyWith(
                  fontSize: 10,
                  color: mine
                      ? Colors.white.withValues(alpha: 0.75)
                      : colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A complaint row with its status chip and optional resolution.
class ComplaintTile extends StatelessWidget {
  const ComplaintTile({required this.complaint, super.key});

  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final String reasonText = complaintReasonLabel(context, complaint.reason);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  reasonText,
                  style: context.text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppChip(
                label: complaintStatusLabel(context, complaint.status),
                color: complaint.isSettled ? colors.success : colors.warning,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '#${complaint.referenceCode}',
            style: context.text.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            complaint.description,
            style: context.text.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          // The resolution is the answer to "what happened", so it is shown as
          // soon as the server has one rather than hidden behind a tap.
          if (complaint.resolution != null &&
              complaint.resolution!.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: colors.success,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        complaint.resolution!,
                        style: context.text.caption.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (complaint.requiresRework) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            AppChip(
              label: l10n.complaintReworkScheduled,
              color: colors.danger,
              icon: 'assets/icons/history.svg',
            ),
          ],
        ],
      ),
    );
  }
}

/// Complaint reason wording, mirroring the backend `ComplaintReason` enum.
///
/// A code the app does not know yet renders as the raw code rather than an empty
/// row, so a reason the server adds early is still visible.
String complaintReasonLabel(BuildContext context, String code) {
  final AppLocalizations l10n = context.l10n;
  return switch (ComplaintReasonCode.fromCode(code).code) {
    'WORK_NOT_DONE' => l10n.complaintReasonWorkNotDone,
    'POOR_QUALITY' => l10n.complaintReasonPoorQuality,
    'OVERCHARGE' => l10n.complaintReasonOvercharge,
    'TECHNICIAN_LATE' => l10n.complaintReasonTechnicianLate,
    'DAMAGE' => l10n.complaintReasonDamage,
    'RECURRING_FAULT' => l10n.complaintReasonRecurringFault,
    'OTHER' => l10n.complaintReasonOther,
    _ => code.isEmpty ? l10n.complaintReasonOther : code,
  };
}

/// Complaint status chip label, mirroring the backend `ComplaintStatus` enum.
String complaintStatusLabel(BuildContext context, String status) {
  final AppLocalizations l10n = context.l10n;
  return switch (status) {
    'OPEN' => l10n.complaintStatusOpen,
    'UNDER_REVIEW' => l10n.complaintStatusUnderReview,
    'QC_REQUIRED' => l10n.complaintStatusQcRequired,
    'REVISIT_REQUIRED' => l10n.complaintStatusRevisitRequired,
    'REVISIT_SCHEDULED' => l10n.complaintStatusRevisitScheduled,
    'RESOLVED' => l10n.complaintStatusResolved,
    'CLOSED' => l10n.complaintStatusClosed,
    // Unknown statuses show the raw code rather than a blank chip.
    _ => status.isEmpty ? l10n.requestStatusUnknown : status,
  };
}

/// Navigation helper shared by the support screens.
///
/// The subject rides along as a query parameter so the thread opens titled even
/// before its messages arrive; the messages endpoint never returns it.
void openConversation(BuildContext context, Conversation conversation) {
  context.pushNamed(
    AppRoute.conversationMessages.name,
    pathParameters: <String, String>{'conversationId': conversation.id},
    queryParameters: <String, String>{
      if (conversation.subject.isNotEmpty) 'subject': conversation.subject,
    },
  );
}
