import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/request_models.dart';
import '../../data/repositories/requests_repository.dart';
import '../controllers/request_wizard_controller.dart';
import '../widgets/request_wizard_scaffold.dart';
import '../widgets/wizard_navigation.dart';

/// Wizard step 1 of 5 (spec screen 6): pick a service category.
///
/// The grid is driven by `GET /catalogue`, which already nests problem types, so
/// choosing a category also primes the problems for step 2 without a second
/// round trip.
class SelectServicePage extends ConsumerWidget {
  const SelectServicePage({this.onDone, super.key});

  /// Null when reached from the router, which then pops the wizard.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final RequestWizardState wizard = ref.watch(requestWizardProvider);
    final AsyncValue<List<ServiceCategory>> catalogue = ref.watch(
      catalogueProvider,
    );

    return RequestWizardScaffold(
      step: RequestWizardStep.service,
      nextEnabled: wizard.category != null,
      onNext: () => wizardGoNext(
        context,
        ref.read(requestWizardProvider.notifier),
        RequestWizardStep.details,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.requestsServiceChoose, style: context.text.title),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.requestsCategoryTitle,
            style: context.text.caption.copyWith(
              color: AppColors.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          catalogue.when(
            loading: () => const _ServiceGridSkeleton(),
            error: (Object error, StackTrace stack) => ErrorRetry(
              message: l10n.requestsServiceEmptyBody,
              onRetry: () => ref.invalidate(catalogueProvider),
            ),
            data: (List<ServiceCategory> categories) {
              if (categories.isEmpty) {
                return EmptyState(
                  title: l10n.requestsServiceEmpty,
                  body: l10n.requestsServiceEmptyBody,
                  icon: 'assets/icons/wrench.svg',
                  actionLabel: l10n.commonRetry,
                  onAction: () => ref.invalidate(catalogueProvider),
                );
              }
              return _ServiceGrid(categories: categories);
            },
          ),
        ],
      ),
    );
  }
}

class _ServiceGrid extends ConsumerWidget {
  const _ServiceGrid({required this.categories});

  final List<ServiceCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final RequestWizardState wizard = ref.watch(requestWizardProvider);

    return Column(
      children: <Widget>[
        for (final ServiceCategory category in categories) ...<Widget>[
          WizardSelectTile(
            title: _localisedName(category, l10n.localeName),
            subtitle: _subtitle(category, l10n),
            selected: wizard.category?.id == category.id,
            onTap: () => ref
                .read(requestWizardProvider.notifier)
                .selectCategory(category),
            leading: _CategoryBadge(category: category),
            trailing: wizard.category?.id == category.id
                ? Icon(
                    Icons.check_circle,
                    color: AppColors.of(context).primary,
                    size: 20,
                  )
                : null,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  /// Catalogue names come from the backend because they are admin-editable
  /// content; only the language choice is the app's.
  static String _localisedName(ServiceCategory category, String language) =>
      language.startsWith('ar') ? category.nameAr : category.nameEn;

  static String _subtitle(ServiceCategory category, AppLocalizations l10n) {
    final List<String> parts = <String>[
      if (category.descriptionAr != null && category.descriptionAr!.isNotEmpty)
        category.descriptionAr!,
      if (category.estimatedDurationMinutes > 0)
        '${category.estimatedDurationMinutes}',
    ];
    return parts.join(' · ');
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final ServiceCategory category;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    // Admin-supplied hex wins so the grid matches the brand's palette, with the
    // theme colour as a fallback for a malformed stored value.
    final Color accent = category.accentColor ?? colors.primary;
    final Color soft = category.softBackgroundColor ?? colors.primarySoft;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(_iconFor(category.iconKey), color: accent, size: 22),
    );
  }

  /// Maps the backend's `icon_key` to a Material icon.
  ///
  /// `icon_key` is a free string with no lookup endpoint, so an unknown key
  /// falls back to a wrench instead of a missing-asset crash.
  static IconData _iconFor(String key) => switch (key) {
    'plumbing' => Icons.plumbing,
    'electrical' => Icons.electrical_services,
    'ac' || 'hvac' => Icons.ac_unit,
    'cleaning' => Icons.cleaning_services,
    'carpentry' => Icons.carpenter,
    'painting' => Icons.format_paint,
    'appliance' => Icons.kitchen,
    'pest' => Icons.pest_control,
    'moving' => Icons.local_shipping,
    'garden' => Icons.yard,
    _ => Icons.build,
  };
}

class _ServiceGridSkeleton extends StatelessWidget {
  const _ServiceGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Column(
      children: <Widget>[
        for (int i = 0; i < 6; i++)
          Container(
            height: 68,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.border.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
      ],
    );
  }
}
