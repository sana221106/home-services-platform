import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/order_models.dart';

/// The visit window and the timestamps around it.
///
/// Three states, because conflating them would promise more than dispatch can
/// deliver: a promised window before the technician is dispatched, a
/// confirmation once they have actually arrived, and the work timestamps
/// afterwards (§10).
class ExpectedArrivalCard extends StatelessWidget {
  const ExpectedArrivalCard({required this.tracking, super.key});

  final OrderTracking tracking;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.orderTimelineTitle),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (tracking.hasArrived)
                _Headline(
                  icon: 'assets/icons/check.svg',
                  color: AppColors.of(context).success,
                  title: l10n.orderTechnicianArrived,
                  subtitle: formatDateTime(tracking.actualArrival, l10n: l10n),
                )
              else if (tracking.hasExpectedArrival)
                _Headline(
                  icon: 'assets/icons/truck.svg',
                  color: AppColors.of(context).primary,
                  title: l10n.orderEta,
                  // Rendered as a range. A single time would read as a promise.
                  subtitle:
                      '${formatDateTime(tracking.expectedArrivalStart, l10n: l10n)}'
                      ' – ${formatTimeOnly(tracking.expectedArrivalEnd, l10n: l10n)}',
                )
              else
                _Headline(
                  icon: 'assets/icons/clock.svg',
                  color: AppColors.of(context).textSecondary,
                  title: l10n.orderArrivalNotScheduled,
                  subtitle: l10n.orderArrivalNotScheduledBody,
                ),

              if (tracking.workStartedAt != null ||
                  tracking.workCompletedAt != null ||
                  tracking.serviceCompletedAt != null) ...<Widget>[
                const Divider(height: AppSpacing.lg),
                if (tracking.workStartedAt != null)
                  InfoRow(
                    label: l10n.orderWorkStarted,
                    value: formatDateTime(tracking.workStartedAt, l10n: l10n),
                  ),
                if (tracking.workCompletedAt != null)
                  InfoRow(
                    label: l10n.orderWorkCompleted,
                    value: formatDateTime(tracking.workCompletedAt, l10n: l10n),
                  ),
                if (tracking.serviceCompletedAt != null)
                  InfoRow(
                    label: l10n.orderServiceCompleted,
                    value: formatDateTime(
                      tracking.serviceCompletedAt,
                      l10n: l10n,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final String icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: AppIcon(icon, size: 20, color: color),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: context.text.body.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: context.text.caption.copyWith(
                  color: AppColors.of(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
