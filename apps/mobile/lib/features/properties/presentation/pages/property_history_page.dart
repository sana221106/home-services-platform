import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/widgets/app_icon.dart';
import '../../../../shared/widgets/app_widgets.dart';
import '../../data/models/property_models.dart';
import '../controllers/property_history_controller.dart';

/// Maintenance history for one property.
///
/// §17 requires date, category, problem, images, diagnosis, resolution, price,
/// materials, complaints and rework, so this screen shows the resolved record
/// rather than a thin status list.
class PropertyHistoryPage extends ConsumerWidget {
  const PropertyHistoryPage({required this.propertyId, super.key});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PropertyHistoryState state = ref.watch(
      propertyHistoryProvider(this.propertyId),
    );
    final l10n = context.l10n;

    return AppPageScaffold(
      title: state.property?.displayLabel ?? l10n.propertyHistoryTitle,
      subtitle: l10n.propertyHistorySubtitle,
      onBack: () => context.pop(),
      body: switch (state.status) {
        PropertyHistoryStatus.initial || PropertyHistoryStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        PropertyHistoryStatus.failed => ErrorRetry(
          message: state.error ?? l10n.commonRetry,
          onRetry: () =>
              ref.read(propertyHistoryProvider(this.propertyId).notifier).load(),
        ),
        PropertyHistoryStatus.ready =>
          state.items.isEmpty
              ? EmptyState(
                icon: 'assets/icons/history.svg',
                title: l10n.propertyHistoryEmptyTitle,
                body: l10n.propertyHistoryEmptyBody,
              )
              : RefreshIndicator(
                onRefresh: () =>
                    ref
                        .read(propertyHistoryProvider(this.propertyId).notifier)
                        .load(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal,
                    AppSpacing.sm,
                    AppSpacing.screenHorizontal,
                    96,
                  ),
                  children: <Widget>[
                    if (state.recurringCount > 0) ...<Widget>[
                      RecurringIssueBanner(count: state.recurringCount),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    for (final MaintenanceHistoryItem item in state.items) ...<Widget>[
                      MaintenanceHistoryCard(item: item),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
      },
    );
  }
}

/// Warns when operations has linked repeat visits on this property. The spec
/// leaves recurrence detection to AI later, so this only reports what the
/// backend already decided.
class RecurringIssueBanner extends StatelessWidget {
  const RecurringIssueBanner({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    return AppCard(
      accent: colors.warning,
      child: Row(
        children: <Widget>[
          AppIcon('assets/icons/history.svg', size: 22, color: colors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.l10n.propertyRecurringBanner(count),
              style: context.text.body,
            ),
          ),
        ],
      ),
    );
  }
}

/// One past service visit, with the resolved record beneath the headline.
class MaintenanceHistoryCard extends StatelessWidget {
  const MaintenanceHistoryCard({required this.item, super.key});

  final MaintenanceHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;

    return AppCard(
      onTap: () => context.goNamed(
        AppRoute.orderDetail.name,
        pathParameters: <String, String>{'requestId': item.requestId},
      ),
      accent: statusColor(colors, item.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppChip(
                label: statusLabel(context, item.status),
                color: statusColor(colors, item.status),
              ),
              const Spacer(),
              Text(
                formatDate(item.completedAt ?? item.createdAt),
                style: context.text.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.problemTypeName ?? item.categoryName ?? l10n.requestTitleFallback,
            style: context.text.title,
          ),
          if (item.problemDescription != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              item.problemDescription!,
              style: context.text.body.copyWith(color: colors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              if (item.categoryName != null)
                AppChip(label: item.categoryName!, icon: 'assets/icons/wrench.svg'),
              if (item.urgency == 'URGENT')
                AppChip(
                  label: l10n.requestUrgencyUrgent,
                  icon: 'assets/icons/bolt.svg',
                  color: colors.danger,
                ),
              if (item.inspectionOnly || item.inspectionRequired)
                AppChip(
                  label: l10n.requestInspectionOnly,
                  icon: 'assets/icons/search.svg',
                ),
              if (item.isRecurring)
                AppChip(
                  label: l10n.propertyRecurringChip,
                  icon: 'assets/icons/history.svg',
                  color: colors.warning,
                ),
              if (item.hasComplaint)
                AppChip(
                  label: l10n.complaintFiledChip,
                  icon: 'assets/icons/alert.svg',
                  color: colors.warning,
                ),
              if (item.reworkRequired)
                AppChip(
                  label: l10n.requestReworkChip,
                  icon: 'assets/icons/tool-box.svg',
                  color: colors.danger,
                ),
            ],
          ),
          if (item.finalDiagnosis != null || item.resolution != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            if (item.finalDiagnosis != null)
              InfoRow(
                label: l10n.requestDiagnosisLabel,
                value: item.finalDiagnosis!,
              ),
            if (item.resolution != null)
              InfoRow(label: l10n.requestResolutionLabel, value: item.resolution!),
            if (item.materials.isNotEmpty)
              InfoRow(
                label: l10n.requestMaterialsLabel,
                value: item.materials.join('، '),
              ),
          ],
          if (item.photoUrls.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.photoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                itemBuilder: (BuildContext context, int index) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    item.photoUrls[index],
                    width: 62,
                    height: 62,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 62,
                      height: 62,
                      color: colors.surfaceVariant,
                      child: AppIcon('assets/icons/image.svg', size: 20, color: colors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (item.finalPrice != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Text(l10n.requestFinalPriceLabel, style: context.text.body),
                const Spacer(),
                Text(
                  formatMoney(item.finalPrice, symbol: item.currency),
                  style: context.text.title.copyWith(color: colors.primary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Maps a backend request status onto the palette. Unknown statuses fall back to
/// the neutral secondary colour rather than a random hue (§117).
Color statusColor(AppColors colors, String status) => switch (status) {
  'COMPLETED' || 'CLOSED' => colors.success,
  'CANCELLED' || 'REJECTED' => colors.danger,
  'IN_PROGRESS' || 'ON_THE_WAY' || 'ASSIGNED' => colors.primary,
  'AWAITING_CONFIRMATION' || 'PENDING' || 'SUBMITTED' => colors.warning,
  _ => colors.textSecondary,
};

String statusLabel(BuildContext context, String status) =>
    context.l10n.requestStatusLabel(status);
