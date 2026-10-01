import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/constants/request_status.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/request_models.dart';

/// The price quote, with the accept and reject actions while it is open.
///
/// Every number comes straight from the quote. The client never computes a
/// total from the line items, because the server's subtotal and total already
/// include discounts and fees that the item list does not show.
class QuoteSection extends StatelessWidget {
  const QuoteSection({
    required this.quote,
    required this.onAccept,
    required this.onReject,
    this.isActing = false,
    super.key,
  });

  final Quote quote;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool isActing;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final AppRequestStatus? status = AppRequestStatus.fromCode(quote.status);
    final bool actionable = quote.isOpen && !isActing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: l10n.requestQuoteTitle),
        AppCard(
          accent: actionable ? colors.primary : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.quoteRevision(quote.revisionNumber),
                      style: context.text.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (status != null)
                    AppChip(
                      label: status.label(l10n),
                      color: status.color(colors),
                    ),
                ],
              ),

              if (quote.notes != null && quote.notes!.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(quote.notes!, style: context.text.caption),
              ],

              const SizedBox(height: AppSpacing.md),
              _Line(
                label: l10n.quoteServiceCost,
                value: l10n.commonCurrency(_money(quote.serviceCost)),
              ),
              // Zero lines are hidden: a quote with no materials should not show
              // a "Materials 0" row.
              if (quote.materialsCost > 0)
                _Line(
                  label: l10n.quoteMaterialsCost,
                  value: l10n.commonCurrency(_money(quote.materialsCost)),
                ),
              if (quote.urgencyFee > 0)
                _Line(
                  label: l10n.quoteUrgencyFee,
                  value: l10n.commonCurrency(_money(quote.urgencyFee)),
                ),
              if (quote.inspectionFee > 0)
                _Line(
                  label: l10n.quoteInspectionFee,
                  value: l10n.commonCurrency(_money(quote.inspectionFee)),
                ),
              if (quote.discount > 0)
                _Line(
                  label: l10n.quoteDiscount,
                  value: l10n.commonCurrency(_money(quote.discount)),
                  negative: true,
                ),
              const Divider(height: AppSpacing.lg),
              _Line(
                label: l10n.quoteTotal,
                value: l10n.commonCurrency(_money(quote.total)),
                emphasised: true,
              ),
              if (quote.requiresDeposit) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                InfoRow(
                  label: l10n.requestDepositAmount,
                  value: l10n.commonCurrency(_money(quote.depositAmount)),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              InfoRow(
                label: l10n.quoteDuration,
                value: l10n.quoteDurationValue(quote.estimatedDurationMinutes),
              ),

              if (quote.items.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.quoteItemsTitle,
                  style: context.text.label.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final QuoteItem item in quote.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.labelAr,
                            style: context.text.caption,
                          ),
                        ),
                        Text(
                          l10n.commonCurrency(_money(item.lineTotal)),
                          style: context.text.caption,
                        ),
                      ],
                    ),
                  ),
              ],

              if (quote.expiresAt != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    AppIcon(
                      'assets/icons/clock.svg',
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        l10n.quoteValidUntil(
                          MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(quote.expiresAt!),
                        ),
                        style: context.text.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if (actionable) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isActing ? null : onReject,
                        child: Text(l10n.requestQuoteReject),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: const Key('quote-accept'),
                        onPressed: isActing ? null : onAccept,
                        child: Text(l10n.requestQuoteAccept),
                      ),
                    ),
                  ],
                ),
              ] else ...<Widget>[
                // Still worth reading, just not actionable: an expired or
                // already decided quote keeps its numbers on screen.
                const SizedBox(height: AppSpacing.sm),
                Text(
                  // Reusing the status copy keeps one Arabic string per state
                  // instead of a second set that can drift from it.
                  status?.label(l10n) ?? l10n.requestQuoteExpired,
                  style: context.text.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Two decimals, no currency symbol: the suffix comes from `commonCurrency`.
  static String _money(double value) => value.toStringAsFixed(2);
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasised = false,
    this.negative = false,
  });

  final String label;
  final String value;
  final bool emphasised;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final Color valueColor = negative ? colors.success : colors.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: emphasised
                  ? context.text.body.copyWith(fontWeight: FontWeight.w700)
                  : context.text.caption.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            value,
            style: emphasised
                ? context.text.body.copyWith(fontWeight: FontWeight.w700)
                : context.text.caption.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}
