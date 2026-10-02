import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/property_models.dart';
import '../controllers/property_detail_controller.dart';

/// Property details (screen 14): the address snapshot, its contacts, and the
/// actions that keep the default flag and the archive state correct.
class PropertyDetailPage extends ConsumerWidget {
  const PropertyDetailPage({required this.propertyId, super.key});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final PropertyDetailState state = ref.watch(
      propertyDetailProvider(propertyId),
    );
    final PropertyDetailController controller = ref.read(
      propertyDetailProvider(propertyId).notifier,
    );

    ref.listen(propertyDetailProvider(propertyId), (
      _,
      PropertyDetailState next,
    ) {
      if (next.deleted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.propertyDeletedMessage)));
        Navigator.of(context).maybePop();
      }
    });

    return AppPageScaffold(
      title: l10n.propertyDetailTitle,
      onBack: () => Navigator.of(context).maybePop(),
      body: switch (state.status) {
        PropertyDetailStatus.initial || PropertyDetailStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        PropertyDetailStatus.failed => ErrorRetry(
          message: state.error ?? l10n.commonRetry,
          onRetry: controller.load,
        ),
        PropertyDetailStatus.ready => _Detail(
          property: state.property!,
          isMutating: state.isMutating,
          onSetDefault: controller.setDefault,
          onDelete: () => _confirmDelete(context, controller),
        ),
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PropertyDetailController controller,
  ) async {
    final AppLocalizations l10n = context.l10n;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(l10n.propertyDeleteConfirmTitle),
            content: Text(l10n.propertyDeleteConfirmBody),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const Key('property-delete-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.propertyDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await controller.remove();
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.property,
    required this.isMutating,
    required this.onSetDefault,
    required this.onDelete,
  });

  final Property property;
  final bool isMutating;
  final Future<bool> Function() onSetDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return ListView(
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
                  AppIcon(
                    'assets/icons/building.svg',
                    size: 28,
                    color: colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      property.displayLabel,
                      style: context.text.title,
                    ),
                  ),
                  if (property.isDefault)
                    AppChip(
                      label: l10n.propertiesDefault,
                      icon: 'assets/icons/check.svg',
                      color: colors.primary,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                property.displayAddress,
                style: context.text.body.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(title: l10n.propertyContactsTitle),
        const SizedBox(height: AppSpacing.xs),
        if (property.contacts.isEmpty)
          Text(
            l10n.commonOptional,
            style: context.text.body.copyWith(color: colors.textSecondary),
          )
        else
          for (final PropertyContact contact in property.contacts)
            InfoRow(label: contact.name, value: contact.phone ?? '—'),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(title: l10n.propertiesLabel),
        const SizedBox(height: AppSpacing.xs),
        ..._addressRows(context, property),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.tonalIcon(
          key: const Key('property-history-link'),
          onPressed: () => context.goNamed(
            AppRoute.propertyHistory.name,
            pathParameters: <String, String>{'propertyId': property.id},
          ),
          icon: const Icon(Icons.history),
          label: Text(l10n.propertiesHistory),
        ),
        if (!property.isDefault) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('property-set-default'),
            onPressed: isMutating
                ? null
                : () async {
                    final bool ok = await onSetDefault();
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.propertyDefaultSetMessage)),
                      );
                    }
                  },
            icon: const Icon(Icons.star_border),
            label: Text(l10n.propertiesSetDefault),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const Key('property-delete'),
          onPressed: isMutating ? null : onDelete,
          icon: Icon(Icons.delete_outline, color: colors.danger),
          label: Text(
            l10n.propertyDelete,
            style: TextStyle(color: colors.danger),
          ),
        ),
      ],
    );
  }

  List<Widget> _addressRows(BuildContext context, Property property) {
    final AppLocalizations l10n = context.l10n;
    final List<(String, String?)> rows = <(String, String?)>[
      (l10n.propertyGovernorateLabel, property.governorate),
      (l10n.propertyCityLabel, property.city),
      (l10n.propertyDistrictLabel, property.district),
      (l10n.propertyZoneLabel, property.zone),
      (l10n.propertyStreetLabel, property.street),
      (l10n.propertyBuildingLabel, property.building),
      (l10n.propertyFloorLabel, property.floor),
      (l10n.propertyApartmentLabel, property.apartment),
      (l10n.propertyLandmarkLabel, property.landmark),
      (l10n.propertyNotesLabel, property.notes),
      if (property.hasCoordinates)
        (
          l10n.propertyCoordinatesLabel,
          '${property.latitude}, ${property.longitude}',
        ),
    ];
    return <Widget>[
      for (final (String label, String? value) in rows)
        if (value != null && value.trim().isNotEmpty)
          InfoRow(label: label, value: value),
    ];
  }
}
