import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../app/localization/app_localizations.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/property_models.dart';
import '../controllers/properties_controller.dart';

/// Property list. Screen 14's entry point and the bottom-nav destination.
///
/// A customer with no properties is prompted to add one, because every request
/// needs a property to snapshot the address from (§61).
class PropertiesPage extends ConsumerWidget {
  const PropertiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PropertiesState state = ref.watch(propertiesProvider);
    final l10n = context.l10n;

    return AppPageScaffold(
      title: l10n.propertiesTitle,
      subtitle: l10n.propertiesSubtitle,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.goNamed(AppRoute.propertyNew.name),
          icon: AppIcon(
            'assets/icons/plus.svg',
            size: 22,
            color: Theme.of(context).extension<AppColors>()!.primary,
            semanticLabel: l10n.propertiesAdd,
          ),
          tooltip: l10n.propertiesAdd,
        ),
      ],
      body: switch (state.status) {
        PropertiesStatus.initial || PropertiesStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        PropertiesStatus.failed => ErrorRetry(
          message: state.error ?? l10n.commonRetry,
          onRetry: () => ref.read(propertiesProvider.notifier).load(),
        ),
        PropertiesStatus.ready =>
          state.properties.isEmpty
              ? EmptyState(
                  icon: 'assets/icons/building.svg',
                  title: l10n.propertiesEmptyTitle,
                  body: l10n.propertiesEmptyBody,
                  actionLabel: l10n.propertiesAdd,
                  onAction: () => context.goNamed(AppRoute.propertyNew.name),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(propertiesProvider.notifier).load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenHorizontal,
                      AppSpacing.sm,
                      AppSpacing.screenHorizontal,
                      96,
                    ),
                    itemCount: state.properties.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (BuildContext context, int index) {
                      final Property property = state.properties[index];
                      return PropertyCard(
                        property: property,
                        onTap: () => context.goNamed(
                          AppRoute.propertyDetail.name,
                          pathParameters: <String, String>{
                            'propertyId': property.id,
                          },
                        ),
                      );
                    },
                  ),
                ),
      },
    );
  }
}

/// Summary card for one property, with its default marker.
class PropertyCard extends StatelessWidget {
  const PropertyCard({required this.property, this.onTap, super.key});

  final Property property;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = Theme.of(context).extension<AppColors>()!;

    return AppCard(
      onTap: onTap,
      accent: property.isDefault ? colors.primary : null,
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: AppIcon(
              'assets/icons/building.svg',
              size: 24,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        property.displayLabel,
                        style: context.text.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (property.isDefault) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs),
                      AppChip(
                        label: context.l10n.propertiesDefault,
                        icon: 'assets/icons/check.svg',
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  property.displayAddress,
                  style: context.text.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
        ],
      ),
    );
  }
}
