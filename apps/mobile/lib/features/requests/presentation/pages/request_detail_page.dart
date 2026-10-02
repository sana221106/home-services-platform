import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/constants/request_status.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/request_models.dart';
import '../controllers/request_detail_controller.dart';
import '../widgets/quote_section.dart';
import '../widgets/timeline_section.dart';

/// Spec screen 11: everything about one request.
///
/// The status is the headline because it decides which actions are offered at
/// all, and `AppRequestStatus` is the single place that mapping lives.
class RequestDetailPage extends ConsumerWidget {
  const RequestDetailPage({required this.requestId, super.key});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final RequestDetailState state = ref.watch(
      requestDetailProvider(requestId),
    );
    final RequestDetailController controller = ref.read(
      requestDetailProvider(requestId).notifier,
    );

    return AppPageScaffold(
      title: l10n.requestDetailTitle,
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: _ActionBar.footerFor(state: state, controller: controller),
      body: switch (state.status) {
        RequestDetailStatus.initial || RequestDetailStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        RequestDetailStatus.failed => ErrorRetry(
          message: state.errorMessage ?? l10n.commonSomethingWentWrong,
          onRetry: () => controller.load(force: true),
        ),
        RequestDetailStatus.ready => _Content(
          state: state,
          controller: controller,
        ),
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.state, required this.controller});

  final RequestDetailState state;
  final RequestDetailController controller;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final ServiceRequest? request = state.request;
    if (request == null) {
      return EmptyState(
        title: l10n.commonSomethingWentWrong,
        icon: 'assets/icons/alert.svg',
      );
    }

    final ({Color color, String label}) status = requestStatusPresentation(
      context,
      request.status,
    );

    return RefreshIndicator(
      onRefresh: () => controller.load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          // Status first: it answers "what is happening now".
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(request.displayTitle, style: context.text.title),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${l10n.requestsReferenceCode} #${request.referenceCode}',
                  style: context.text.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    AppChip(label: status.label, color: status.color),
                    if (request.isUrgent)
                      AppChip(
                        label: l10n.requestUrgencyUrgent,
                        color: colors.danger,
                      ),
                    if (request.inspectionOnly)
                      AppChip(
                        label: l10n.requestInspectionOnly,
                        icon: 'assets/icons/eye.svg',
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),
          _DetailBlock(
            title: l10n.requestDetailProblemTitle,
            child: Text(request.problemDescription, style: context.text.body),
          ),

          if (request.media.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _DetailBlock(
              title: l10n.requestDetailPhotos(request.media.length),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final RequestMedia media in request.media)
                    _MediaThumb(media: media),
                ],
              ),
            ),
          ],

          if (request.addressSummaryAr != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _DetailBlock(
              title: l10n.requestDetailAddressTitle,
              child: Text(request.addressSummaryAr!, style: context.text.body),
            ),
          ],

          if (request.technicianName != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _DetailBlock(
              title: l10n.requestDetailTechnicianTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(request.technicianName!, style: context.text.body),
                  if (request.technicianCompanyAr != null)
                    Text(
                      request.technicianCompanyAr!,
                      style: context.text.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          TimelineSection(events: state.events),

          // Rendered whenever the server has a quote; the accept and reject
          // buttons appear only while it is still open.
          if (state.quote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            QuoteSection(
              quote: state.quote!,
              isActing: state.isActing,
              onAccept: controller.acceptQuote,
              onReject: () => _confirmReject(context, controller),
            ),
          ],

          if (state.actionError != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      state.actionError!,
                      style: context.text.body.copyWith(color: colors.danger),
                    ),
                  ),
                  TextButton(
                    onPressed: controller.clearActionError,
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The API takes no reason on reject, but asking for one gives the team
  /// something to act on, so it stays optional rather than required.
  Future<void> _confirmReject(
    BuildContext context,
    RequestDetailController controller,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _ReasonDialog(
        title: l10n.requestQuoteReject,
        hint: l10n.cancelReasonHint,
        confirmLabel: l10n.requestQuoteReject,
      ),
    );
    if (reason == null) return;
    await controller.rejectQuote(reason: reason);
  }
}

/// The bottom bar holds only actions the current status actually permits, so
/// the customer is never offered a request the backend will reject.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.state, required this.controller});

  final RequestDetailState state;
  final RequestDetailController controller;

  /// Returns null when the status permits no action, so the page shows no
  /// footer strip at all rather than an empty one.
  static Widget? footerFor({
    required RequestDetailState state,
    required RequestDetailController controller,
  }) {
    if (!state.canRate &&
        !state.canComplain &&
        !state.canPay &&
        !state.canCancel) {
      return null;
    }
    return _ActionBar(state: state, controller: controller);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool busy = state.isActing;

    return StickyFooter(
      children: <Widget>[
        if (state.canRate)
          Expanded(
            child: FilledButton(
              key: const Key('request-rate'),
              onPressed: () => context.pushNamed(
                AppRoute.rateService.name,
                pathParameters: <String, String>{'requestId': state.requestId},
              ),
              child: Text(l10n.requestRateAction),
            ),
          ),
        if (state.canComplain)
          Expanded(
            child: OutlinedButton(
              key: const Key('request-complain'),
              onPressed: () => context.pushNamed(
                AppRoute.complaintNew.name,
                queryParameters: <String, String>{'requestId': state.requestId},
              ),
              child: Text(l10n.requestComplainAction),
            ),
          ),
        if (state.canPay)
          Expanded(
            child: OutlinedButton(
              key: const Key('request-pay'),
              onPressed: () => context.pushNamed(
                AppRoute.payment.name,
                pathParameters: <String, String>{'requestId': state.requestId},
                queryParameters: <String, String>{
                  if (state.referenceCode.isNotEmpty)
                    'reference': state.referenceCode,
                },
              ),
              child: Text(l10n.paymentViewTitle),
            ),
          ),
        if (state.canCancel)
          TextButton(
            key: const Key('request-cancel'),
            onPressed: busy ? null : () => _startCancel(context, controller),
            child: Text(
              l10n.requestCancelAction,
              style: TextStyle(color: AppColors.of(context).danger),
            ),
          ),
      ],
    );
  }

  /// Cancellation is never confirmed straight away: the refund is fetched from
  /// the server first so the amount shown is the amount that will be paid.
  Future<void> _startCancel(
    BuildContext context,
    RequestDetailController controller,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final CancellationPreview preview = await controller
          .cancellationPreview();
      if (!context.mounted) return;

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) =>
            _CancelDialog(preview: preview, l10n: l10n),
      );
      if (confirmed != true || !context.mounted) return;

      final String? reason = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) => _ReasonDialog(
          title: l10n.requestCancelTitle,
          hint: l10n.cancelReasonHint,
          confirmLabel: l10n.requestCancelConfirm,
        ),
      );
      if (reason == null) return;

      await controller.cancel(reasonNote: reason);
    } on Object {
      // The preview call itself failed; the controller keeps the message.
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonSomethingWentWrong)),
      );
    }
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: title),
        AppCard(child: child),
      ],
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.media});

  final RequestMedia media;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String? url = media.url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        height: 84,
        child: url == null
            ? ColoredBox(
                color: colors.surfaceVariant,
                child: AppIcon(
                  'assets/icons/image.svg',
                  color: colors.textSecondary,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                // A dead media URL must not break the detail screen; the rest
                // of the request is still useful without the photo.
                errorBuilder: (_, _, _) => ColoredBox(
                  color: colors.surfaceVariant,
                  child: AppIcon(
                    'assets/icons/image.svg',
                    color: colors.textSecondary,
                  ),
                ),
              ),
      ),
    );
  }
}

class _CancelDialog extends StatelessWidget {
  const _CancelDialog({required this.preview, required this.l10n});

  final CancellationPreview preview;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return AlertDialog(
      title: Text(l10n.requestCancelTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.requestCancelWarning, style: context.text.body),
          const SizedBox(height: AppSpacing.md),
          InfoRow(
            label: l10n.cancelRefundAmount,
            value: l10n.commonCurrency(
              preview.refundableAmount.toStringAsFixed(2),
            ),
          ),
          if (preview.deductionAmount > 0)
            InfoRow(
              label: l10n.cancelDeductionAmount,
              value: l10n.commonCurrency(
                preview.deductionAmount.toStringAsFixed(2),
              ),
            ),
          if (preview.requiresApproval) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.cancelNeedsApproval,
              style: context.text.caption.copyWith(color: colors.warning),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.requestCancelConfirm),
        ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _reason,
        maxLines: 3,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
