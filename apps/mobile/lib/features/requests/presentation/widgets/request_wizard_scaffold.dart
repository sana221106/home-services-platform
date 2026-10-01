import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../controllers/request_wizard_controller.dart';

/// Shared chrome for every wizard step: a progress rail plus a sticky footer
/// holding the back/next pair.
///
/// One shell for all five steps keeps the rail and the button behaviour
/// identical, which is what makes a five-step flow feel like one screen.
class RequestWizardScaffold extends ConsumerWidget {
  const RequestWizardScaffold({
    required this.step,
    required this.body,
    this.onBack,
    this.nextLabel,
    this.nextEnabled,
    this.onNext,
    this.hideNext = false,
    super.key,
  });

  final RequestWizardStep step;
  final Widget body;
  final VoidCallback? onBack;
  final String? nextLabel;
  final bool? nextEnabled;
  final VoidCallback? onNext;

  /// The photos step drives its own buttons, so it hides the shared next.
  final bool hideNext;

  static const List<RequestWizardStep> _ordered = RequestWizardStep.values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final int index = _ordered.indexOf(step);
    final int total = _ordered.length;
    final bool enabled = nextEnabled ?? true;

    return AppPageScaffold(
      // gen-l10n emits placeholder parameters in its own order, not the order
      // they appear in the ARB, so the positional call reads (total, current).
      // Pinned by a test so a regeneration cannot silently swap them.
      title: l10n.requestsStepCounter(total, index + 1),
      onBack: onBack,
      body: Column(
        children: <Widget>[
          _WizardProgressRail(current: index, total: total),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                0,
                AppSpacing.screenHorizontal,
                AppSpacing.lg,
              ),
              child: body,
            ),
          ),
        ],
      ),
      bottomBar: hideNext
          ? null
          : StickyFooter(
              children: <Widget>[
                if (onBack != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onBack,
                      child: Text(l10n.commonBack),
                    ),
                  ),
                if (onBack != null) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: enabled ? onNext : null,
                    child: Text(nextLabel ?? l10n.commonNext),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Segmented rail showing which of the five steps the customer is on.
class _WizardProgressRail extends StatelessWidget {
  const _WizardProgressRail({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
        AppSpacing.screenHorizontal,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < total; i++) ...<Widget>[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= current ? colors.primary : colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < total - 1) const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

/// A selectable tile used by the service and property pickers.
///
/// Shared so both pickers behave the same when selected, and so the selected
/// state is announced to screen readers.
class WizardSelectTile extends StatelessWidget {
  const WizardSelectTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: selected ? colors.primarySoft : colors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? colors.primary : colors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: context.text.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected ? colors.primary : colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: context.text.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
