import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../core/network/json_readers.dart';

/// A service category from `GET /api/v1/services` or the nested `catalogue`.
///
/// `nameAr`/`nameEn` and `descriptionAr` come from the backend because the
/// catalogue is admin-editable content; UI chrome stays in ARB.
class ServiceCategory extends Equatable {
  const ServiceCategory({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.nameEn,
    this.descriptionAr,
    this.iconKey = 'wrench',
    this.colorHex = '#2557D6',
    this.softBackgroundHex = '#EEF4FF',
    this.sortOrder = 0,
    this.estimatedDurationMinutes = 120,
    this.requiresInspectionDefault = false,
    this.problems = const <ProblemType>[],
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: json.strOr('id', ''),
      code: json.strOr('code', ''),
      nameAr: json.strOr('name_ar', ''),
      nameEn: json.strOr('name_en', ''),
      descriptionAr: json.str('description_ar'),
      iconKey: json.strOr('icon_key', 'wrench'),
      colorHex: json.strOr('color_hex', '#2557D6'),
      softBackgroundHex: json.strOr('soft_background_hex', '#EEF4FF'),
      sortOrder: json.intOr('sort_order', 0),
      estimatedDurationMinutes: json.intOr('estimated_duration_minutes', 120),
      requiresInspectionDefault: json.flag('requires_inspection_default'),
      problems: json
          .mapList('problems')
          .map(ProblemType.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final String code;
  final String nameAr;
  final String nameEn;
  final String? descriptionAr;
  final String iconKey;
  final String colorHex;
  final String softBackgroundHex;
  final int sortOrder;
  final int estimatedDurationMinutes;
  final bool requiresInspectionDefault;

  /// Only populated by `GET /api/v1/catalogue`; the plain `services` list
  /// leaves it empty and the client fetches problems per category on demand.
  final List<ProblemType> problems;

  /// Admin-supplied hex drives the tile colour so the grid matches the brand's
  /// per-service palette. Returns null when the stored value is malformed, and
  /// the caller falls back to the theme colour rather than throwing inside a
  /// build method.
  Color? get accentColor => parseHexColor(colorHex);

  Color? get softBackgroundColor => parseHexColor(softBackgroundHex);

  @override
  List<Object?> get props => <Object?>[
    id,
    code,
    nameAr,
    nameEn,
    iconKey,
    colorHex,
    sortOrder,
    estimatedDurationMinutes,
    problems,
  ];
}

/// A problem type, the only sub-service mapping the backend has.
///
/// `problem_type_id` on create is validated against `category_id`
/// server-side, so the client must never offer one from another category.
class ProblemType extends Equatable {
  const ProblemType({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.nameEn,
    this.descriptionAr,
    this.sortOrder = 0,
    this.requiresInspectionDefault = false,
    this.defaultDurationMinutes = 90,
    this.hintAr,
  });

  factory ProblemType.fromJson(Map<String, dynamic> json) {
    return ProblemType(
      id: json.strOr('id', ''),
      code: json.strOr('code', ''),
      nameAr: json.strOr('name_ar', ''),
      nameEn: json.strOr('name_en', ''),
      descriptionAr: json.str('description_ar'),
      sortOrder: json.intOr('sort_order', 0),
      requiresInspectionDefault: json.flag('requires_inspection_default'),
      defaultDurationMinutes: json.intOr('default_duration_minutes', 90),
      hintAr: json.str('hint_ar'),
    );
  }

  final String id;
  final String code;
  final String nameAr;
  final String nameEn;
  final String? descriptionAr;
  final int sortOrder;
  final bool requiresInspectionDefault;
  final int defaultDurationMinutes;
  final String? hintAr;

  @override
  List<Object?> get props => <Object?>[
    id,
    code,
    nameAr,
    nameEn,
    sortOrder,
    defaultDurationMinutes,
  ];
}

/// The address snapshot submitted with a request.
///
/// This is a required field of `POST /requests` and is copied verbatim onto the
/// order, so later edits to the property never rewrite history (§61).
class AddressSnapshot extends Equatable {
  const AddressSnapshot({
    required this.governorate,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.zone,
    this.district,
    this.street,
    this.building,
    this.floor,
    this.apartment,
    this.landmark,
    this.notes,
    this.contactName,
    this.contactPhone,
  });

  factory AddressSnapshot.fromJson(Map<String, dynamic> json) {
    return AddressSnapshot(
      governorate: json.strOr('governorate', ''),
      city: json.strOr('city', ''),
      latitude: json.decimal('latitude') ?? 0,
      longitude: json.decimal('longitude') ?? 0,
      zone: json.str('zone'),
      district: json.str('district'),
      street: json.str('street'),
      building: json.str('building'),
      floor: json.str('floor'),
      apartment: json.str('apartment'),
      landmark: json.str('landmark'),
      notes: json.str('notes'),
      contactName: json.str('contact_name'),
      contactPhone: json.str('contact_phone'),
    );
  }

  final String governorate;
  final String city;
  final double latitude;
  final double longitude;
  final String? zone;
  final String? district;
  final String? street;
  final String? building;
  final String? floor;
  final String? apartment;
  final String? landmark;
  final String? notes;
  final String? contactName;
  final String? contactPhone;

  /// The four fields the backend requires. Used to gate the wizard's next step
  /// before spending a round trip on a guaranteed 422.
  bool get isSubmittable =>
      governorate.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  /// `contact_phone` is required whenever `contact_name` is set, so a half
  /// filled contact pair must block submission too.
  bool get contactPairIsValid =>
      (contactName == null || contactName!.trim().isEmpty) ||
      (contactPhone != null && contactPhone!.trim().isNotEmpty);

  /// Builds the exact `AddressSnapshotPayload` the API expects.
  ///
  /// Keys are dropped when null rather than sent as explicit nulls, because the
  /// schema sets `extra="forbid"` and validates lengths.
  Map<String, dynamic> toPayload() => <String, dynamic>{
    'governorate': governorate.trim(),
    'city': city.trim(),
    'latitude': latitude,
    'longitude': longitude,
    if (zone != null && zone!.trim().isNotEmpty) 'zone': zone!.trim(),
    if (district != null && district!.trim().isNotEmpty)
      'district': district!.trim(),
    if (street != null && street!.trim().isNotEmpty) 'street': street!.trim(),
    if (building != null && building!.trim().isNotEmpty)
      'building': building!.trim(),
    if (floor != null && floor!.trim().isNotEmpty) 'floor': floor!.trim(),
    if (apartment != null && apartment!.trim().isNotEmpty)
      'apartment': apartment!.trim(),
    if (landmark != null && landmark!.trim().isNotEmpty)
      'landmark': landmark!.trim(),
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    if (contactName != null && contactName!.trim().isNotEmpty)
      'contact_name': contactName!.trim(),
    if (contactPhone != null && contactPhone!.trim().isNotEmpty)
      'contact_phone': contactPhone!.trim(),
  };

  AddressSnapshot copyWith({
    String? governorate,
    String? city,
    double? latitude,
    double? longitude,
    String? zone,
    String? district,
    String? street,
    String? building,
    String? floor,
    String? apartment,
    String? landmark,
    String? notes,
    String? contactName,
    String? contactPhone,
    bool clearZone = false,
    bool clearDistrict = false,
    bool clearContactName = false,
    bool clearContactPhone = false,
  }) {
    return AddressSnapshot(
      governorate: governorate ?? this.governorate,
      city: city ?? this.city,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      zone: clearZone ? null : (zone ?? this.zone),
      district: clearDistrict ? null : (district ?? this.district),
      street: street ?? this.street,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      apartment: apartment ?? this.apartment,
      landmark: landmark ?? this.landmark,
      notes: notes ?? this.notes,
      contactName: clearContactName ? null : (contactName ?? this.contactName),
      contactPhone: clearContactPhone
          ? null
          : (contactPhone ?? this.contactPhone),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    governorate,
    city,
    latitude,
    longitude,
    zone,
    district,
    street,
    building,
    floor,
    apartment,
    landmark,
    notes,
    contactName,
    contactPhone,
  ];
}

/// One row of the customer's request list.
///
/// Mirrors `ServiceRequestResponse`. `status` stays a raw `String` so an unknown
/// backend state still renders: `AppRequestStatus.fromCode` returns null and
/// the UI falls back to showing the code.
class ServiceRequest extends Equatable {
  const ServiceRequest({
    required this.id,
    required this.referenceCode,
    required this.categoryNameAr,
    required this.status,
    required this.urgency,
    required this.inspectionOnly,
    required this.inspectionRequired,
    required this.problemDescription,
    required this.createdAt,
    this.categoryId,
    this.categoryIconKey = 'wrench',
    this.problemTypeId,
    this.problemNameAr,
    this.propertyId,
    this.preferredDate,
    this.preferredTimeWindow,
    this.customerNotes,
    this.submittedAt,
    this.completedAt,
    this.hasComplaint = false,
    this.hasRework = false,
    this.ratedAt,
    this.mediaCount = 0,
    this.expectedArrivalStart,
    this.expectedArrivalEnd,
    this.technicianName,
    this.technicianCompanyAr,
    this.addressSummaryAr,
    this.hasUnreadUpdates = false,
    this.media = const <RequestMedia>[],
    this.address,
  });

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> arrival =
        json.objOrNull('expected_arrival') ?? const <String, dynamic>{};
    final Map<String, dynamic> tech =
        json.objOrNull('technician') ?? const <String, dynamic>{};
    return ServiceRequest(
      id: json.strOr('id', ''),
      referenceCode: json.strOr('reference_code', ''),
      categoryNameAr: json.strOr('category_name_ar', ''),
      status: json.strOr('status', ''),
      urgency: json.strOr('urgency', 'NORMAL'),
      inspectionOnly: json.flag('inspection_only'),
      inspectionRequired: json.flag('inspection_required'),
      problemDescription: json.strOr('problem_description', ''),
      createdAt: json.time('created_at'),
      categoryId: json.str('category_id'),
      categoryIconKey: json.strOr('category_icon_key', 'wrench'),
      problemTypeId: json.str('problem_type_id'),
      problemNameAr: json.str('problem_name_ar'),
      propertyId: json.str('property_id'),
      preferredDate: json.time('preferred_date'),
      preferredTimeWindow: json.str('preferred_time_window'),
      customerNotes: json.str('customer_notes'),
      submittedAt: json.time('submitted_at'),
      completedAt: json.time('completed_at'),
      hasComplaint: json.flag('has_complaint'),
      hasRework: json.flag('has_rework'),
      ratedAt: json.time('rated_at'),
      mediaCount: json.intOr('media_count', 0),
      expectedArrivalStart: arrival.time('start'),
      expectedArrivalEnd: arrival.time('end'),
      technicianName: tech.str('display_name'),
      technicianCompanyAr: tech.str('company_label_ar'),
      addressSummaryAr: json.str('address_summary_ar'),
      hasUnreadUpdates: json.flag('has_unread_updates'),
      media: json
          .mapList('media')
          .map(RequestMedia.fromJson)
          .toList(growable: false),
      address: json.objOrNull('address') == null
          ? null
          : AddressSnapshot.fromJson(json.obj('address')),
    );
  }

  final String id;
  final String referenceCode;
  final String categoryNameAr;
  final String status;
  final String urgency;
  final bool inspectionOnly;
  final bool inspectionRequired;
  final String problemDescription;
  final DateTime? createdAt;
  final String? categoryId;
  final String categoryIconKey;
  final String? problemTypeId;
  final String? problemNameAr;
  final String? propertyId;
  final DateTime? preferredDate;
  final String? preferredTimeWindow;
  final String? customerNotes;
  final DateTime? submittedAt;
  final DateTime? completedAt;
  final bool hasComplaint;
  final bool hasRework;
  final DateTime? ratedAt;
  final int mediaCount;
  final DateTime? expectedArrivalStart;
  final DateTime? expectedArrivalEnd;
  final String? technicianName;
  final String? technicianCompanyAr;
  final String? addressSummaryAr;
  final bool hasUnreadUpdates;
  final List<RequestMedia> media;
  final AddressSnapshot? address;

  bool get isUrgent => urgency.toUpperCase() == 'URGENT';

  /// The title a list row shows: the problem type when known, else the category.
  String get displayTitle => problemNameAr != null && problemNameAr!.isNotEmpty
      ? problemNameAr!
      : categoryNameAr;

  @override
  List<Object?> get props => <Object?>[
    id,
    referenceCode,
    categoryNameAr,
    status,
    urgency,
    problemDescription,
    createdAt,
    mediaCount,
    hasUnreadUpdates,
  ];
}

/// A photo attached to a request.
class RequestMedia extends Equatable {
  const RequestMedia({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    required this.sortOrder,
    this.width = 0,
    this.height = 0,
    this.url,
    this.annotationCount = 0,
  });

  factory RequestMedia.fromJson(Map<String, dynamic> json) {
    return RequestMedia(
      id: json.strOr('id', ''),
      kind: json.strOr('kind', 'IMAGE'),
      mimeType: json.strOr('mime_type', ''),
      sizeBytes: json.intOr('size_bytes', 0),
      width: json.intOr('width', 0),
      height: json.intOr('height', 0),
      sortOrder: json.intOr('sort_order', 0),
      url: json.str('url'),
      annotationCount: json.mapList('annotations').length,
    );
  }

  final String id;
  final String kind;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
  final int sortOrder;
  final String? url;

  /// The detail payload carries full annotation objects; the list only needs to
  /// know whether the photo was marked up.
  final int annotationCount;

  /// Photo count limit enforced server-side, mirrored so the picker can stop
  /// before the upload fails.
  static const int maxPerRequest = 8;

  /// 12 MiB, the enforced server limit. The OpenAPI description says 10 MB but
  /// `MAX_MEDIA_BYTES` is 12 * 1024 * 1024.
  static const int maxBytes = 12 * 1024 * 1024;

  static const Set<String> allowedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  @override
  List<Object?> get props => <Object?>[
    id,
    kind,
    mimeType,
    sizeBytes,
    sortOrder,
  ];
}

/// One entry of `GET /requests/{id}/timeline`.
class RequestEvent extends Equatable {
  const RequestEvent({
    required this.id,
    required this.eventType,
    required this.occurredAt,
    this.fromStatus,
    this.toStatus,
    this.actorType,
    this.note,
  });

  factory RequestEvent.fromJson(Map<String, dynamic> json) {
    return RequestEvent(
      id: json.strOr('id', ''),
      eventType: json.strOr('event_type', ''),
      occurredAt: json.time('occurred_at'),
      fromStatus: json.str('from_status'),
      toStatus: json.str('to_status'),
      actorType: json.str('actor_type'),
      note: json.str('note'),
    );
  }

  final String id;
  final String eventType;
  final DateTime? occurredAt;
  final String? fromStatus;
  final String? toStatus;
  final String? actorType;
  final String? note;

  @override
  List<Object?> get props => <Object?>[id, eventType, occurredAt, toStatus];
}

/// The customer-visible quote.
///
/// `total`, `deposit_amount` and every cost line are computed server-side; the
/// client never sends them, it only renders them.
class Quote extends Equatable {
  const Quote({
    required this.id,
    required this.requestId,
    required this.revisionNumber,
    required this.status,
    required this.urgency,
    required this.serviceCost,
    required this.materialsCost,
    required this.urgencyFee,
    required this.inspectionFee,
    required this.discount,
    required this.subtotal,
    required this.total,
    required this.depositAmount,
    required this.requiresDeposit,
    required this.estimatedDurationMinutes,
    this.notes,
    this.expiresAt,
    this.sentAt,
    this.decidedAt,
    this.items = const <QuoteItem>[],
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      id: json.strOr('id', ''),
      requestId: json.strOr('request_id', ''),
      revisionNumber: json.intOr('revision_number', 1),
      status: json.strOr('status', ''),
      urgency: json.strOr('urgency', 'NORMAL'),
      serviceCost: json.decimal('service_cost') ?? 0,
      materialsCost: json.decimal('materials_cost') ?? 0,
      urgencyFee: json.decimal('urgency_fee') ?? 0,
      inspectionFee: json.decimal('inspection_fee') ?? 0,
      discount: json.decimal('discount') ?? 0,
      subtotal: json.decimal('subtotal') ?? 0,
      total: json.decimal('total') ?? 0,
      depositAmount: json.decimal('deposit_amount') ?? 0,
      requiresDeposit: json.flag('requires_deposit'),
      estimatedDurationMinutes: json.intOr('estimated_duration_minutes', 0),
      notes: json.str('notes'),
      expiresAt: json.time('expires_at'),
      sentAt: json.time('sent_at'),
      decidedAt: json.time('decided_at'),
      items: json
          .mapList('items')
          .map(QuoteItem.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final String requestId;
  final int revisionNumber;
  final String status;
  final String urgency;
  final double serviceCost;
  final double materialsCost;
  final double urgencyFee;
  final double inspectionFee;
  final double discount;
  final double subtotal;
  final double total;
  final double depositAmount;
  final bool requiresDeposit;
  final int estimatedDurationMinutes;
  final String? notes;
  final DateTime? expiresAt;
  final DateTime? sentAt;
  final DateTime? decidedAt;
  final List<QuoteItem> items;

  bool get isOpen => status == 'SENT' || status == 'AWAITING_CUSTOMER_APPROVAL';

  @override
  List<Object?> get props => <Object?>[id, revisionNumber, status, total];
}

class QuoteItem extends Equatable {
  const QuoteItem({
    required this.labelAr,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.itemType = 'SERVICE',
  });

  factory QuoteItem.fromJson(Map<String, dynamic> json) {
    return QuoteItem(
      labelAr: json.strOr('label_ar', ''),
      quantity: json.decimal('quantity') ?? 0,
      unitPrice: json.decimal('unit_price') ?? 0,
      lineTotal: json.decimal('line_total') ?? 0,
      itemType: json.strOr('item_type', 'SERVICE'),
    );
  }

  final String labelAr;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String itemType;

  @override
  List<Object?> get props => <Object?>[labelAr, quantity, lineTotal];
}

/// What cancelling would cost, from
/// `GET /requests/{id}/cancellation-preview`.
class CancellationPreview extends Equatable {
  const CancellationPreview({
    required this.requestId,
    required this.depositRequired,
    required this.depositPaid,
    required this.refundPercent,
    required this.refundableAmount,
    required this.deductionAmount,
    required this.requiresApproval,
    this.policyNoteAr,
  });

  factory CancellationPreview.fromJson(Map<String, dynamic> json) {
    return CancellationPreview(
      requestId: json.strOr('request_id', ''),
      depositRequired: json.flag('deposit_required'),
      depositPaid: json.flag('deposit_paid'),
      refundPercent: json.decimal('refund_percent') ?? 0,
      refundableAmount: json.decimal('refundable_amount') ?? 0,
      deductionAmount: json.decimal('deduction_amount') ?? 0,
      requiresApproval: json.flag('requires_approval'),
      policyNoteAr: json.str('policy_note_ar'),
    );
  }

  final String requestId;
  final bool depositRequired;
  final bool depositPaid;
  final double refundPercent;
  final double refundableAmount;
  final double deductionAmount;
  final bool requiresApproval;
  final String? policyNoteAr;

  @override
  List<Object?> get props => <Object?>[
    requestId,
    refundPercent,
    refundableAmount,
    deductionAmount,
    requiresApproval,
  ];
}

/// Parses a `#RRGGBB` / `#AARRGGBB` string from the catalogue.
///
/// Returns null for anything malformed rather than throwing, because the value
/// is admin-editable in the database and a bad row must not break the grid.
Color? parseHexColor(String? value) {
  if (value == null) return null;
  final String hex = value.trim().replaceFirst('#', '');
  final int? parsed = switch (hex.length) {
    6 => int.tryParse('FF$hex', radix: 16),
    8 => int.tryParse(hex, radix: 16),
    _ => null,
  };
  return parsed == null ? null : Color(parsed);
}
