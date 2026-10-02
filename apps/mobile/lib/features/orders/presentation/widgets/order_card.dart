import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/constants/request_status.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/order_models.dart';

/// One order row.
///
/// The status chip leads because it is the answer to "what is happening now",
/// and the accepted total is shown only when the server has one, since most
/// orders are still being priced.
class OrderCard extends StatelessWidget {
  const OrderCard({required this.order, this.onTap, super.key});

  final OrderSummary order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final AppRequestStatus? parsed = AppRequestStatus.fromCode(order.status);
    final ({Color color, String label}) status = requestStatusPresentation(
      context,
      order.status,
    );

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  order.categoryNameAr,
                  style: context.text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (order.isUrgent)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.xs,
                  ),
                  child: AppChip(
                    label: l10n.requestsUrgencyUrgentLabel,
                    color: colors.danger,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '#${order.referenceCode}',
            style: context.text.caption.copyWith(color: colors.textSecondary),
          ),

          if (order.propertyLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                const Icon(Icons.place_outlined, size: 14),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    order.propertyLabel,
                    style: context.text.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              AppChip(label: status.label, color: status.color),
              if (order.hasUnreadUpdates) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                AppChip(label: l10n.requestsNewActivity, color: colors.primary),
              ],
              if (order.hasComplaint) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                AppChip(
                  label: l10n.orderComplaintOpenChip,
                  color: colors.warning,
                ),
              ],
              const Spacer(),
              // A terminal order has nothing left to track, so the total is the
              // last thing on the row rather than a call to action.
              if (parsed?.isTerminal ?? false)
                Text(
                  order.total == null
                      ? l10n.orderNoTotalYet
                      : formatMoney(order.total),
                  style: context.text.label.copyWith(color: colors.textPrimary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
