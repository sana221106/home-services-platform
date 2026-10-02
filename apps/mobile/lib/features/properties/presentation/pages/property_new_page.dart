import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/location_picker.dart';
import '../controllers/properties_controller.dart';

/// Adds a property (§31). The backend requires a map point because every
/// request snapshots the coordinates for area intelligence (§18), so the form
/// gates saving on both the required address fields and a picked location.
class PropertyNewPage extends ConsumerStatefulWidget {
  const PropertyNewPage({this.enableMap = true, super.key});

  /// Tests disable the basemap because `flutter_test` blocks network images.
  final bool enableMap;

  @override
  ConsumerState<PropertyNewPage> createState() => _PropertyNewPageState();
}

class _PropertyNewPageState extends ConsumerState<PropertyNewPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _label = TextEditingController();
  final TextEditingController _governorate = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _zone = TextEditingController();
  final TextEditingController _district = TextEditingController();
  final TextEditingController _street = TextEditingController();
  final TextEditingController _building = TextEditingController();
  final TextEditingController _floor = TextEditingController();
  final TextEditingController _apartment = TextEditingController();
  final TextEditingController _landmark = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _contactName = TextEditingController();
  final TextEditingController _contactPhone = TextEditingController();

  String _propertyType = 'apartment';
  bool _isDefault = true;
  LatLng? _point;
  bool _showLocationError = false;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _label,
      _governorate,
      _city,
      _zone,
      _district,
      _street,
      _building,
      _floor,
      _apartment,
      _landmark,
      _notes,
      _contactName,
      _contactPhone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final bool fieldsValid = _formKey.currentState?.validate() ?? false;
    final bool locationValid = _point != null;
    setState(() => _showLocationError = !locationValid);
    if (!fieldsValid || !locationValid) return;

    final String? failure = await ref
        .read(propertiesProvider.notifier)
        .create(
          label: _label.text.trim(),
          governorate: _governorate.text.trim(),
          city: _city.text.trim(),
          latitude: _point!.latitude,
          longitude: _point!.longitude,
          propertyType: _propertyType,
          zone: _emptyToNull(_zone.text),
          district: _emptyToNull(_district.text),
          street: _emptyToNull(_street.text),
          building: _emptyToNull(_building.text),
          floor: _emptyToNull(_floor.text),
          apartment: _emptyToNull(_apartment.text),
          landmark: _emptyToNull(_landmark.text),
          notes: _emptyToNull(_notes.text),
          isDefault: _isDefault,
          contactName: _emptyToNull(_contactName.text),
          contactPhone: _emptyToNull(_contactPhone.text),
        )
        .then((_) => ref.read(propertiesProvider).error);
    if (!mounted || failure != null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.propertyCreatedMessage)),
    );
    Navigator.of(context).maybePop();
  }

  static String? _emptyToNull(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final PropertiesState state = ref.watch(propertiesProvider);

    return AppPageScaffold(
      title: l10n.propertyNewTitle,
      onBack: () => Navigator.of(context).maybePop(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.md,
            AppSpacing.screenHorizontal,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            _field('property-label', _label, l10n.propertiesLabel),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.propertyTypeLabel,
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: <Widget>[
                for (final MapEntry<String, String> type in _propertyTypes(
                  l10n,
                ).entries)
                  ChoiceChip(
                    label: Text(type.value),
                    selected: _propertyType == type.key,
                    onSelected: (_) => setState(() => _propertyType = type.key),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _field(
              'property-governorate',
              _governorate,
              l10n.propertyGovernorateLabel,
            ),
            const SizedBox(height: AppSpacing.md),
            _field('property-city', _city, l10n.propertyCityLabel),
            const SizedBox(height: AppSpacing.md),
            _field('property-district', _district, l10n.propertyDistrictLabel),
            const SizedBox(height: AppSpacing.md),
            _field('property-zone', _zone, l10n.propertyZoneLabel),
            const SizedBox(height: AppSpacing.md),
            _field('property-street', _street, l10n.propertyStreetLabel),
            const SizedBox(height: AppSpacing.md),
            _field('property-building', _building, l10n.propertyBuildingLabel),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: _field(
                    'property-floor',
                    _floor,
                    l10n.propertyFloorLabel,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _field(
                    'property-apartment',
                    _apartment,
                    l10n.propertyApartmentLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _field('property-landmark', _landmark, l10n.propertyLandmarkLabel),
            const SizedBox(height: AppSpacing.md),
            _field(
              'property-notes',
              _notes,
              l10n.propertyNotesLabel,
              minLines: 2,
              maxLines: 3,
            ),

            const SizedBox(height: AppSpacing.lg),
            SectionHeader(title: l10n.propertyLocationTitle),
            Text(
              l10n.propertyLocationHint,
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            LocationPicker(
              initial: _point,
              enabled: widget.enableMap,
              onChanged: (LatLng point) => setState(() {
                _point = point;
                _showLocationError = false;
              }),
            ),
            if (_showLocationError) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.propertyLocationRequired,
                style: context.text.caption.copyWith(color: colors.danger),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            SectionHeader(title: l10n.propertyContactsTitle),
            const SizedBox(height: AppSpacing.sm),
            _field(
              'property-contact-name',
              _contactName,
              l10n.propertyContactNameLabel,
            ),
            const SizedBox(height: AppSpacing.md),
            _field(
              'property-contact-phone',
              _contactPhone,
              l10n.propertyContactPhoneLabel,
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              onChanged: (bool value) => setState(() => _isDefault = value),
              title: Text(l10n.propertiesSetDefault),
            ),

            if (state.error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                state.error!,
                style: context.text.caption.copyWith(color: colors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('property-save'),
                onPressed: state.isMutating ? null : _save,
                child: state.isMutating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.propertyCreateAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String key,
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextFormField(
      key: Key(key),
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (String? value) => (value == null || value.trim().isEmpty)
          ? context.l10n.commonRequiredField
          : null,
    );
  }

  Map<String, String> _propertyTypes(AppLocalizations l10n) => <String, String>{
    'apartment': l10n.propertyTypeApartment,
    'house': l10n.propertyTypeHouse,
    'villa': l10n.propertyTypeVilla,
    'office': l10n.propertyTypeOffice,
    'shop': l10n.propertyTypeShop,
  };
}
