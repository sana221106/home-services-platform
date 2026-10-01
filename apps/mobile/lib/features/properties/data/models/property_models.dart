import 'package:equatable/equatable.dart';

import '../../../../core/network/json_readers.dart';

/// A property the customer owns. Address fields are copied onto every request
/// as a snapshot (§61), so this stays editable while history does not.
class Property extends Equatable {
  const Property({
    required this.id,
    this.label,
    this.addressLine,
    this.city,
    this.governorate,
    this.district,
    this.zone,
    this.latitude,
    this.longitude,
    this.isDefault = false,
    this.contacts = const <PropertyContact>[],
  });

  factory Property.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> address = json.obj('address');
    return Property(
      id: json.strOr('id', ''),
      label: json.str('label'),
      addressLine: json.str('address_line') ?? address.str('line'),
      city: json.str('city') ?? address.str('city'),
      governorate: json.str('governorate') ?? address.str('governorate'),
      district: json.str('district') ?? address.str('district'),
      zone: json.str('zone') ?? address.str('zone'),
      latitude: json.decimal('latitude'),
      longitude: json.decimal('longitude'),
      isDefault: json.flag('is_default'),
      contacts: json
          .mapList('contacts')
          .map(PropertyContact.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final String? label;
  final String? addressLine;
  final String? city;
  final String? governorate;
  final String? district;
  final String? zone;
  final double? latitude;
  final double? longitude;
  final bool isDefault;
  final List<PropertyContact> contacts;

  /// Single-line address for cards.
  String get displayAddress {
    final List<String> parts = <String>[
      if (addressLine != null && addressLine!.isNotEmpty) addressLine!,
      if (district != null && district!.isNotEmpty) district!,
      if (city != null && city!.isNotEmpty) city!,
    ];
    return parts.isEmpty ? '—' : parts.join('، ');
  }

  String get displayLabel =>
      label != null && label!.isNotEmpty ? label! : displayAddress;

  @override
  List<Object?> get props => <Object?>[id, label, displayAddress, isDefault];
}

class PropertyContact extends Equatable {
  const PropertyContact({required this.name, this.phone, this.role});

  factory PropertyContact.fromJson(Map<String, dynamic> json) =>
      PropertyContact(
        name: json.strOr('name', ''),
        phone: json.str('phone'),
        role: json.str('role'),
      );

  final String name;
  final String? phone;
  final String? role;

  @override
  List<Object?> get props => <Object?>[name, phone, role];
}

/// One completed or in-flight service at a property.
///
/// This is the maintenance health record (§17): a major differentiator, so the
/// model keeps diagnosis, resolution, materials and price rather than only a
/// status.
class MaintenanceHistoryItem extends Equatable {
  const MaintenanceHistoryItem({
    required this.requestId,
    required this.status,
    this.createdAt,
    this.completedAt,
    this.categoryName,
    this.categoryIconKey,
    this.problemTypeName,
    this.problemDescription,
    this.finalDiagnosis,
    this.resolution,
    this.materials = const <String>[],
    this.finalPrice,
    this.currency = 'EGP',
    this.photoUrls = const <String>[],
    this.inspectionOnly = false,
    this.recurringIssueId,
    this.hasComplaint = false,
    this.reworkRequired = false,
    this.urgency = 'NORMAL',
    this.inspectionRequired = false,
  });

  factory MaintenanceHistoryItem.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> category = json.obj('category');
    final Map<String, dynamic> problem = json.obj('problem_type');
    final Map<String, dynamic> price = json.obj('final_price');

    return MaintenanceHistoryItem(
      requestId: json.strOr('request_id', json.strOr('id', '')),
      status: json.strOr('status', 'UNKNOWN'),
      createdAt: json.time('created_at'),
      completedAt: json.time('completed_at') ?? json.time('closed_at'),
      categoryName: json.str('category_name') ?? category.str('name'),
      categoryIconKey:
          json.str('category_icon_key') ?? category.str('icon_key'),
      problemTypeName: json.str('problem_type_name') ?? problem.str('name'),
      problemDescription: json.str('problem_description'),
      finalDiagnosis: json.str('final_diagnosis') ?? json.str('diagnosis'),
      resolution: json.str('resolution'),
      materials: json.stringList('materials'),
      finalPrice:
          json.str('final_price_amount') ??
          json.str('final_price') ??
          (price['amount'] as String?) ??
          (json.decimal('final_price')?.toString()),
      currency: json.strOr('currency', 'EGP'),
      photoUrls: json
          .mapList('photos')
          .map((Map<String, dynamic> m) => m.strOr('url', ''))
          .where((String u) => u.isNotEmpty)
          .toList(growable: false),
      inspectionOnly: json.flag('inspection_only'),
      recurringIssueId: json.str('recurring_issue_id'),
      hasComplaint: json.flag('has_complaint'),
      reworkRequired: json.flag('rework_required'),
      urgency: json.strOr('urgency', 'NORMAL'),
      inspectionRequired: json.flag('inspection_required'),
    );
  }

  final String requestId;
  final String status;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String? categoryName;
  final String? categoryIconKey;
  final String? problemTypeName;
  final String? problemDescription;
  final String? finalDiagnosis;
  final String? resolution;
  final List<String> materials;
  final String? finalPrice;
  final String currency;
  final List<String> photoUrls;

  /// True when operations marked this request as inspection-only or
  /// inspection-required (§7), so the customer can see why no work happened yet.
  final bool inspectionOnly;
  final String? recurringIssueId;
  final bool hasComplaint;
  final bool reworkRequired;
  final String urgency;
  final bool inspectionRequired;

  bool get isRecurring => recurringIssueId != null;

  @override
  List<Object?> get props => <Object?>[requestId, status, completedAt];
}
