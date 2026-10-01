import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../properties/data/models/property_models.dart';
import '../../data/models/request_models.dart';
import '../../data/repositories/requests_repository.dart';
import '../controllers/request_wizard_controller.dart';
import '../widgets/request_wizard_scaffold.dart';
import '../widgets/wizard_navigation.dart';

/// Wizard step 4 of 5 (spec screen 9): where the work happens.
///
/// `address` is a required field of `POST /requests`, not an optional extra. A
/// property is picked to prefill it, then every field stays editable because
/// the snapshot is what gets frozen onto the order.
class LocationPage extends ConsumerWidget {
  const LocationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final RequestWizardState wizard = ref.watch(requestWizardProvider);
    final RequestWizardController controller = ref.read(
      requestWizardProvider.notifier,
    );
    final AsyncValue<List<Property>> properties = ref.watch(
      wizardPropertiesProvider,
    );

    final AddressSnapshot? address = wizard.address;

    return RequestWizardScaffold(
      step: RequestWizardStep.location,
      onBack: () => wizardGoBack(context, controller, RequestWizardStep.photos),
      nextEnabled: wizard.isLocationValid,
      onNext: () => wizardGoNext(context, controller, RequestWizardStep.review),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: l10n.requestsLocationPick),
          properties.when(
            loading: () => const LinearProgressIndicator(),
            error: (Object error, StackTrace stack) => ErrorRetry(
              message: l10n.commonSomethingWentWrong,
              onRetry: () => ref.invalidate(wizardPropertiesProvider),
            ),
            data: (List<Property> list) {
              if (list.isEmpty) {
                return EmptyState(
                  title: l10n.requestsNoProperty,
                  body: l10n.requestsLocationNoProperty,
                  icon: 'assets/icons/home.svg',
                );
              }
              return Column(
                children: <Widget>[
                  for (final Property property in list)
                    WizardSelectTile(
                      title: property.displayLabel,
                      subtitle: property.displayAddress,
                      selected: wizard.property?.id == property.id,
                      onTap: () => controller.selectProperty(property),
                      trailing: property.isDefault
                          ? AppChip(label: l10n.propertiesDefault)
                          : null,
                    ),
                ],
              );
            },
          ),

          if (address != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(title: l10n.requestsAddressTitle),
            _AddressForm(address: address, onChanged: controller.updateAddress),
          ],
        ],
      ),
    );
  }
}

class _AddressForm extends ConsumerWidget {
  const _AddressForm({required this.address, required this.onChanged});

  final AddressSnapshot address;
  final ValueChanged<AddressSnapshot> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final bool contactPairInvalid =
        !address.contactPairIsValid && address.contactName != null;

    // Mirrors `AddressSnapshot.isSubmittable`: a 0,0 pair means the map was
    // never used, so the customer is warned before the button stays disabled.
    final bool coordsMissing = !address.hasCoordinates;

    return Column(
      children: <Widget>[
        WizardTextField(
          fieldKey: const Key('address-governorate'),
          value: address.governorate,
          onChanged: (String v) => onChanged(address.copyWith(governorate: v)),
          hintText: l10n.requestsAddressGovernorate,
        ),
        const SizedBox(height: AppSpacing.sm),
        WizardTextField(
          fieldKey: const Key('address-city'),
          value: address.city,
          onChanged: (String v) => onChanged(address.copyWith(city: v)),
          hintText: l10n.requestsAddressCity,
        ),
        const SizedBox(height: AppSpacing.sm),
        _Optional(
          label: l10n.requestsAddressZone,
          child: WizardTextField(
            value: address.zone ?? '',
            onChanged: (String v) => onChanged(
              v.trim().isEmpty
                  ? address.copyWith(clearZone: true)
                  : address.copyWith(zone: v),
            ),
          ),
        ),
        _Optional(
          label: l10n.requestsAddressDistrict,
          child: WizardTextField(
            value: address.district ?? '',
            onChanged: (String v) => onChanged(
              v.trim().isEmpty
                  ? address.copyWith(clearDistrict: true)
                  : address.copyWith(district: v),
            ),
          ),
        ),
        _Optional(
          label: l10n.requestsAddressStreet,
          child: WizardTextField(
            value: address.street ?? '',
            onChanged: (String v) => onChanged(address.copyWith(street: v)),
          ),
        ),
        _Optional(
          label: l10n.requestsAddressBuilding,
          child: WizardTextField(
            value: address.building ?? '',
            onChanged: (String v) => onChanged(address.copyWith(building: v)),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _Optional(
                label: l10n.requestsAddressFloor,
                child: WizardTextField(
                  value: address.floor ?? '',
                  onChanged: (String v) =>
                      onChanged(address.copyWith(floor: v)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Optional(
                label: l10n.requestsAddressApartment,
                child: WizardTextField(
                  value: address.apartment ?? '',
                  onChanged: (String v) =>
                      onChanged(address.copyWith(apartment: v)),
                ),
              ),
            ),
          ],
        ),
        _Optional(
          label: l10n.requestsAddressLandmark,
          child: WizardTextField(
            value: address.landmark ?? '',
            onChanged: (String v) => onChanged(address.copyWith(landmark: v)),
          ),
        ),
        _Optional(
          label: l10n.requestsAddressNotes,
          child: WizardTextField(
            value: address.notes ?? '',
            onChanged: (String v) => onChanged(address.copyWith(notes: v)),
            minLines: 2,
            maxLines: 3,
          ),
        ),

        const SizedBox(height: AppSpacing.md),
        SectionHeader(title: l10n.requestsAddressContactName),
        WizardTextField(
          value: address.contactName ?? '',
          onChanged: (String v) => onChanged(
            v.trim().isEmpty
                ? address.copyWith(
                    clearContactName: true,
                    clearContactPhone: true,
                  )
                : address.copyWith(contactName: v),
          ),
          hintText: l10n.commonOptional,
          errorText: contactPairInvalid
              ? l10n.requestsAddressContactPairError
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        WizardTextField(
          value: address.contactPhone ?? '',
          onChanged: (String v) => onChanged(
            v.trim().isEmpty
                ? address.copyWith(clearContactPhone: true)
                : address.copyWith(contactPhone: v),
          ),
          keyboardType: TextInputType.phone,
          hintText: address.contactName == null
              ? l10n.commonOptional
              : l10n.requestsAddressContactPhone,
        ),

        if (coordsMissing) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          AppChip(
            label: l10n.requestsAddressCoordsMissing,
            icon: 'assets/icons/alert.svg',
            color: colors.warning,
          ),
        ],
      ],
    );
  }
}

class _Optional extends StatelessWidget {
  const _Optional({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: context.text.caption.copyWith(
              color: AppColors.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          child,
        ],
      ),
    );
  }
}
