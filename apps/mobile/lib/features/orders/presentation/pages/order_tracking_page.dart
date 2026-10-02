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
import '../../../requests/presentation/widgets/timeline_section.dart';
import '../../data/models/order_models.dart';
import '../controllers/order_tracking_controller.dart';
import '../widgets/expected_arrival_card.dart';

/// Spec screen 12: where one order is right now.
///
/// This screen deliberately shows no live map and no technician contact
/// details. Dispatch exposes an arrival window and a role label, and nothing
/// more (Â§9, Â§10).
class OrderTrackingPage extends ConsumerWidget {
  const OrderTrackingPage({required this.requestId, super.key});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final OrderTrackingState state = ref.watch(
      orderTrackingProvider(requestId),
    );
    final OrderTrackingController controller = ref.read(
      orderTrackingProvider(requestId).notifier,
    );

    return AppPageScaffold(
      title: l10n.orderTrackTitle,
      onBack: () => Navigator.of(context).maybePop(),
      bottomBar: _ActionBar.forTracking(state.tracking),
      body: switch (state.status) {
        OrderTrackingStatus.initial || OrderTrackingStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        OrderTrackingStatus.failed => ErrorRetry(
          message: state.errorMessage ?? l10n.commonSomethingWentWrong,
          onRetry: controller.load,
        ),
        OrderTrackingStatus.ready => _Content(
          tracking: state.tracking!,
          onRetry: controller.load,
        ),
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.tracking, required this.onRetry});

  final OrderTracking tracking;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    // The server's Arabic status label wins when present, because dispatch owns
    // that wording; the client mirror is the fallback for a status the app
    // predates.
    final AppRequestStatus? parsed = AppRequestStatus.fromCode(tracking.status);
    final String statusLabel =
        tracking.statusLabelAr ??
        (parsed == null ? tracking.status : parsed.label(l10n));
    final Color statusColor = parsed?.color(colors) ?? colors.textSecondary;

    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '#${tracking.referenceCode}',
                        style: context.text.title,
                      ),
                    ),
                    if (tracking.isUrgent)
                      AppChip(
                        label: l10n.requestsUrgencyUrgentLabel,
                        color: colors.danger,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                AppChip(label: statusLabel, color: statusColor),
                if (tracking.statusDescriptionAr.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(tracking.statusDescriptionAr, style: context.text.body),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),
          ExpectedArrivalCard(tracking: tracking),

          if (tracking.addressSummaryAr != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _Block(
              title: l10n.requestDetailAddressTitle,
              icon: 'assets/icons/pin.svg',
              child: Text(tracking.addressSummaryAr!, style: context.text.body),
            ),
          ],

          if (tracking.technicianName != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _Block(
              title: l10n.requestDetailTechnicianTitle,
              icon: 'assets/icons/user.svg',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(tracking.technicianName!, style: context.text.body),
                  if (tracking.technicianCompanyAr != null)
                    Text(
                      tracking.technicianCompanyAr!,
                      style: context.text.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          // The tracking endpoint already returns the same customer-visible
          // events the request timeline uses, so the widget is shared.
          TimelineSection(events: tracking.events),

          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('order-open-request'),
              onPressed: () => openRequestScreen(context, tracking),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(l10n.orderViewFullRequest),
            ),
          ),
        ],
      ),
    );
  }
}

/// Titled card with a leading icon, for the blocks tracking shows.
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.icon, required this.child});

  final String title;
  final String icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: title),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppIcon(icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }
}

/// Footer actions, driven entirely by the server's three flags.
///
/// Rating and complaint are shown as they arrive from tracking, but they open
/// the request screen where those flows live, so the two screens cannot disagree
/// about when an action is available.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.tracking});

  final OrderTracking? tracking;

  /// Null when the server offered nothing, so no empty footer strip is drawn.
  static Widget? forTracking(OrderTracking? tracking) {
    if (tracking == null || !tracking.hasAnyAction) return null;
    return _ActionBar(tracking: tracking);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final OrderTracking order = tracking!;

    return StickyFooter(
      children: <Widget>[
        if (order.canRate)
          Expanded(
            child: FilledButton(
              key: const Key('order-rate'),
              onPressed: () => openRequestScreen(context, order),
              child: Text(l10n.requestRateAction),
            ),
          ),
        if (order.canOpenComplaint)
          Expanded(
            child: OutlinedButton(
              key: const Key('order-complain'),
              onPressed: () => openRequestScreen(context, order),
              child: Text(l10n.requestComplainAction),
            ),
          ),
        if (order.canCancel)
          TextButton(
            key: const Key('order-cancel'),
            onPressed: () => openRequestScreen(context, order),
            child: Text(
              l10n.orderCancel,
              style: TextStyle(color: AppColors.of(context).danger),
            ),
          ),
      ],
    );
  }
}

/// Opens the full request screen, which owns the rating, complaint and
/// cancellation flows.
///
/// Those flows live on the request screen because each one needs more than a
/// single flag: cancelling has to show the server-computed refund before it
/// confirms, so it cannot be triggered straight from a tracking button.
void openRequestScreen(BuildContext context, OrderTracking tracking) {
  context.pushNamed(
    AppRoute.requestDetail.name,
    pathParameters: <String, String>{'requestId': tracking.requestId},
  );
}
