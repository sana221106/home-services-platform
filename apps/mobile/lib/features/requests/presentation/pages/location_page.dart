import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../properties/data/models/property_models.dart';
import '../../data/models/coverage_models.dart';
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

    // Mirrors `AddressSnapshot.isSubmittable`: a 0,0 pair means no point was
    // ever resolved, so the customer is warned before the button stays disabled.
    final bool coordsMissing = !address.hasCoordinates;

    return Column(
      children: <Widget>[
        const _CoverageZonePicker(),
        const SizedBox(height: AppSpacing.md),
        _AddressSearch(address: address, onChanged: onChanged),
        if (coordsMissing) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          AppChip(
            label: l10n.requestsAddressCoordsMissing,
            icon: 'assets/icons/alert.svg',
            color: colors.warning,
          ),
        ],
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
      ],
    );
  }
}

/// Picks the served area from `GET /coverage-zones`.
///
/// This replaces the free-text governorate and city fields. They had to match
/// the database exactly, so an Arabic address was rejected for spelling rather
/// than for being unserviceable. Choosing from a server-provided list means the
/// customer writes Arabic and the backend still knows the area (§29).
class _CoverageZonePicker extends ConsumerWidget {
  const _CoverageZonePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AddressSnapshot? address = ref.watch(requestWizardProvider).address;
    final AsyncValue<List<CoverageZone>> zones = ref.watch(
      coverageZonesProvider,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.requestsAddressAreaLabel,
          style: context.text.caption.copyWith(
            color: AppColors.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        zones.when(
          loading: () => const LinearProgressIndicator(),
          error: (Object error, StackTrace stack) => ErrorRetry(
            message: l10n.commonSomethingWentWrong,
            onRetry: () => ref.invalidate(coverageZonesProvider),
          ),
          data: (List<CoverageZone> list) {
            if (list.isEmpty) {
              return AppChip(
                label: l10n.requestsAddressAreaRequired,
                icon: 'assets/icons/alert.svg',
                color: AppColors.of(context).warning,
              );
            }
            return _ZoneDropdown(
              zones: list,
              selected: address?.zoneCode,
              onChanged: (CoverageZone? zone) {
                if (address == null) return;
                final RequestWizardController controller = ref.read(
                  requestWizardProvider.notifier,
                );
                if (zone == null) {
                  controller.updateAddress(
                    address.copyWith(clearZoneCode: true, clearZone: true),
                  );
                  return;
                }
                controller.selectCoverageZone(zone);
              },
            );
          },
        ),
      ],
    );
  }
}

class _ZoneDropdown extends StatelessWidget {
  const _ZoneDropdown({
    required this.zones,
    required this.selected,
    required this.onChanged,
  });

  final List<CoverageZone> zones;
  final String? selected;
  final ValueChanged<CoverageZone?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Guard against a stale code: a zone that was deactivated server-side must
    // not leave the field asserting a value its items no longer contain, which
    // throws at build time.
    final String? current =
        zones.any((CoverageZone z) => z.code == selected) ? selected : null;

    return DropdownButtonFormField<String>(
      key: const Key('address-coverage-zone'),
      initialValue: current,
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: <DropdownMenuItem<String>>[
        for (final CoverageZone zone in zones)
          DropdownMenuItem<String>(
            value: zone.code,
            child: Text(
              zone.nameAr,
              overflow: TextOverflow.ellipsis,
              style: context.text.body,
            ),
          ),
      ],
      onChanged: (String? code) => onChanged(
        code == null
            ? null
            : zones.firstWhere((CoverageZone z) => z.code == code),
      ),
    );
  }
}

/// Searches the typed address and fills the form from the chosen hit.
///
/// The customer types ordinary Arabic; the server resolves it to a point and
/// says which served area it belongs to. The map is gone from the required path
/// because dragging a pin is not something everyone can do (§31).
class _AddressSearch extends ConsumerStatefulWidget {
  const _AddressSearch({required this.address, required this.onChanged});

  final AddressSnapshot address;
  final ValueChanged<AddressSnapshot> onChanged;

  @override
  ConsumerState<_AddressSearch> createState() => _AddressSearchState();
}

class _AddressSearchState extends ConsumerState<_AddressSearch> {
  /// Long enough to skip a request per keystroke, short enough that the customer
  /// has not moved on. The backend throttles and caches as well; this is only
  /// about not asking on every letter.
  static const Duration _debounce = Duration(milliseconds: 450);

  final TextEditingController _controller = TextEditingController();

  Timer? _debounceTimer;
  List<AddressSuggestion> _results = const <AddressSuggestion>[];
  bool _searching = false;
  bool _failed = false;
  bool _searchedEmpty = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    final String query = value.trim();

    if (query.length < 3) {
      setState(() {
        _results = const <AddressSuggestion>[];
        _searching = false;
        _failed = false;
        _searchedEmpty = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounceTimer = Timer(_debounce, () => _run(query));
  }

  Future<void> _run(String query) async {
    final RequestsRepository repository = ref.read(requestsRepositoryProvider);
    try {
      final List<AddressSuggestion> hits = await repository.searchAddress(
        query,
      );
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _results = hits;
        _searching = false;
        _failed = false;
        _searchedEmpty = hits.isEmpty;
      });
    } on ApiFailure {
      if (!mounted) return;
      setState(() {
        _results = const <AddressSuggestion>[];
        _searching = false;
        _failed = true;
        _searchedEmpty = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const <AddressSuggestion>[];
        _searching = false;
        _failed = true;
        _searchedEmpty = false;
      });
    }
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() {
      _results = const <AddressSuggestion>[];
      _searching = false;
      _failed = false;
      _searchedEmpty = false;
    });
  }

  /// Fills the address from one search hit.
  ///
  /// Detail the hit did not resolve is left alone, so a search result never
  /// silently rewrites something the customer already corrected. The served area
  /// is taken from the hit when it matched one; an unserved hit keeps the area
  /// the customer picked, because the point alone cannot invalidate their choice
  /// and the backend still resolves the final area on submit (§30).
  void _apply(AddressSuggestion hit) {
    widget.onChanged(
      widget.address.copyWith(
        latitude: hit.latitude,
        longitude: hit.longitude,
        street: hit.street ?? widget.address.street,
        district: hit.district ?? widget.address.district,
        governorate: hit.governorate ?? widget.address.governorate,
        city: hit.city ?? widget.address.city,
        zoneCode: hit.zoneCode ?? widget.address.zoneCode,
        zone: hit.zoneNameAr ?? widget.address.zone,
      ),
    );
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.requestsAddressSearchLabel,
          style: context.text.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        TextField(
          key: const Key('address-search'),
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: l10n.requestsAddressSearchHint,
            border: const OutlineInputBorder(),
            // Watches the controller rather than a field flag: the clear button
            // has to disappear the moment the text is emptied, including when
            // the text was cleared programmatically after picking a result.
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (
                BuildContext context,
                TextEditingValue value,
                Widget? child,
              ) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: l10n.requestsAddressSearchClear,
                      icon: const Icon(Icons.close),
                      onPressed: _clear,
                    ),
            ),
          ),
        ),
        if (_searching) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          const LinearProgressIndicator(),
        ],
        if (_failed) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          AppChip(
            label: l10n.requestsAddressSearchError,
            icon: 'assets/icons/alert.svg',
            color: colors.danger,
          ),
        ],
        if (_searchedEmpty && !_failed) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          AppChip(
            label: l10n.requestsAddressSearchEmpty,
            icon: 'assets/icons/alert.svg',
            color: colors.textSecondary,
          ),
        ],
        for (final AddressSuggestion hit in _results)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: WizardSelectTile(
              title: hit.displayName,
              subtitle: hit.isOutsideCoverage
                  ? l10n.requestsAddressSearchOutsideCoverage
                  : hit.zoneNameAr,
              selected: widget.address.hasCoordinates &&
                  widget.address.latitude == hit.latitude &&
                  widget.address.longitude == hit.longitude,
              onTap: () => _apply(hit),
            ),
          ),
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
