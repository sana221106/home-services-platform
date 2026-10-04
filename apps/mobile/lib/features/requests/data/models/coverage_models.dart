import 'package:equatable/equatable.dart';

import '../../../../core/network/json_readers.dart';

/// An area the platform serves, from `GET /api/v1/coverage-zones`.
///
/// The customer picks one of these instead of typing a governorate and city that
/// have to match the database literally. That is what makes the address form
/// work in ordinary Arabic: the geography comes from this list, and only the
/// street-level detail is free text (§29).
class CoverageZone extends Equatable {
  const CoverageZone({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.governorate,
    required this.city,
    required this.centerLatitude,
    required this.centerLongitude,
    this.district,
    this.radiusKm = 0,
  });

  factory CoverageZone.fromJson(Map<String, dynamic> json) {
    return CoverageZone(
      id: json.strOr('id', ''),
      code: json.strOr('code', ''),
      nameAr: json.strOr('name_ar', ''),
      governorate: json.strOr('governorate', ''),
      city: json.strOr('city', ''),
      district: json.str('district'),
      centerLatitude: json.decimal('center_latitude') ?? 0,
      centerLongitude: json.decimal('center_longitude') ?? 0,
      radiusKm: json.decimal('radius_km') ?? 0,
    );
  }

  final String id;
  final String code;

  /// The Arabic label shown in the picker. Preferred over [nameEn]-style fields
  /// because the customer reads this, not the operator.
  final String nameAr;

  /// Canonical English values, kept on the request as the fallback match when no
  /// coordinates are available.
  final String governorate;
  final String city;
  final String? district;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusKm;

  @override
  List<Object?> get props => <Object?>[id, code, nameAr];
}

/// One hit from `GET /api/v1/address-search`.
///
/// [zoneCode] is null when the point falls outside every served area, so the app
/// can say so while the customer is still typing rather than at submit (§30).
class AddressSuggestion extends Equatable {
  const AddressSuggestion({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.street,
    this.district,
    this.city,
    this.governorate,
    this.zoneCode,
    this.zoneNameAr,
  });

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    return AddressSuggestion(
      displayName: json.strOr('display_name', ''),
      latitude: json.decimal('latitude') ?? 0,
      longitude: json.decimal('longitude') ?? 0,
      street: json.str('street'),
      district: json.str('district'),
      city: json.str('city'),
      governorate: json.str('governorate'),
      zoneCode: json.str('zone_code'),
      zoneNameAr: json.str('zone_name_ar'),
    );
  }

  final String displayName;
  final double latitude;
  final double longitude;
  final String? street;
  final String? district;
  final String? city;
  final String? governorate;
  final String? zoneCode;
  final String? zoneNameAr;

  /// A hit outside every served area. Selecting one fills in the street detail
  /// and the point but carries no zone, so the UI can say the address is out of
  /// coverage while the customer is still on the step instead of at submit.
  /// Whether that point is servable is settled by the coordinates the customer
  /// already chose a zone for, not by this flag.
  bool get isOutsideCoverage => zoneCode == null || zoneCode!.isEmpty;

  @override
  List<Object?> get props => <Object?>[displayName, latitude, longitude, zoneCode];
}
