import 'package:equatable/equatable.dart';

import '../../../../core/network/json_readers.dart';
import '../../../requests/data/models/request_models.dart';

/// One row of `GET /orders`.
///
/// Deliberately thinner than `ServiceRequest`: the order list answers "where is
/// my job right now", so it carries the status, the accepted total and the
/// unread marker, and nothing that only a detail screen would show.
class OrderSummary extends Equatable {
  const OrderSummary({
    required this.requestId,
    required this.referenceCode,
    required this.status,
    required this.categoryNameAr,
    required this.urgency,
    required this.propertyLabel,
    required this.createdAt,
    this.categoryIconKey = 'wrench',
    this.submittedAt,
    this.completedAt,
    this.total,
    this.hasComplaint = false,
    this.hasUnreadUpdates = false,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    return OrderSummary(
      requestId: json.strOr('request_id', ''),
      referenceCode: json.strOr('reference_code', ''),
      status: json.strOr('status', ''),
      // The backend ships Arabic labels; they are shown verbatim because they
      // are part of the payload the client is a reader for, not copy this app
      // owns.
      categoryNameAr: json.strOr('category_name_ar', ''),
      urgency: json.strOr('urgency', 'NORMAL'),
      propertyLabel: json.strOr('property_label', ''),
      createdAt: json.time('created_at'),
      categoryIconKey: json.strOr('category_icon_key', 'wrench'),
      submittedAt: json.time('submitted_at'),
      completedAt: json.time('completed_at'),
      total: json.str('total'),
      hasComplaint: json.flag('has_complaint'),
      hasUnreadUpdates: json.flag('has_unread_updates'),
    );
  }

  final String requestId;
  final String referenceCode;
  final String status;
  final String categoryNameAr;
  final String categoryIconKey;
  final String urgency;
  final String propertyLabel;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? completedAt;

  /// Kept as the server's decimal string so no rounding drift is introduced on
  /// an amount the customer already agreed to.
  final String? total;

  final bool hasComplaint;
  final bool hasUnreadUpdates;

  bool get isUrgent => urgency.toUpperCase() == 'URGENT';

  @override
  List<Object?> get props => <Object?>[
    requestId,
    status,
    categoryNameAr,
    urgency,
    propertyLabel,
    total,
    hasComplaint,
    hasUnreadUpdates,
  ];
}

/// `GET /orders/{request_id}`: the tracking view of one order.
///
/// The three action flags come from the server and are the only authority on
/// which buttons appear; the client never recomputes them (§8, §12).
class OrderTracking extends Equatable {
  const OrderTracking({
    required this.requestId,
    required this.referenceCode,
    required this.status,
    required this.statusDescriptionAr,
    required this.urgency,
    required this.canCancel,
    required this.canOpenComplaint,
    required this.canRate,
    this.statusLabelAr,
    this.expectedArrivalStart,
    this.expectedArrivalEnd,
    this.actualArrival,
    this.workStartedAt,
    this.workCompletedAt,
    this.serviceCompletedAt,
    this.technicianName,
    this.technicianCompanyAr,
    this.addressSummaryAr,
    this.events = const <RequestEvent>[],
  });

  factory OrderTracking.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> arrival =
        json.objOrNull('expected_arrival') ?? const <String, dynamic>{};
    final Map<String, dynamic> tech =
        json.objOrNull('technician') ?? const <String, dynamic>{};
    return OrderTracking(
      requestId: json.strOr('request_id', ''),
      referenceCode: json.strOr('reference_code', ''),
      status: json.strOr('status', ''),
      statusLabelAr: json.str('status_label_ar'),
      statusDescriptionAr: json.strOr('status_description_ar', ''),
      urgency: json.strOr('urgency', 'NORMAL'),
      // The arrival window is a range on purpose; a single ETA would promise a
      // precision dispatch cannot make (§10).
      expectedArrivalStart: arrival.time('start'),
      expectedArrivalEnd: arrival.time('end'),
      actualArrival: json.time('actual_arrival'),
      workStartedAt: json.time('work_started_at'),
      workCompletedAt: json.time('work_completed_at'),
      serviceCompletedAt: json.time('service_completed_at'),
      technicianName: tech.str('display_name'),
      technicianCompanyAr: tech.str('company_label_ar'),
      addressSummaryAr: json.str('address_summary_ar'),
      events: json
          .mapList('events')
          .map(RequestEvent.fromJson)
          .toList(growable: false),
      canCancel: json.flag('can_cancel'),
      canOpenComplaint: json.flag('can_open_complaint'),
      canRate: json.flag('can_rate'),
    );
  }

  final String requestId;
  final String referenceCode;
  final String status;

  /// The server's Arabic label. Preferred over the client mirror when present
  /// so staff wording changes reach the customer without a release.
  final String? statusLabelAr;

  /// One line explaining what happens next, also server-authored.
  final String statusDescriptionAr;

  final String urgency;
  final DateTime? expectedArrivalStart;
  final DateTime? expectedArrivalEnd;
  final DateTime? actualArrival;
  final DateTime? workStartedAt;
  final DateTime? workCompletedAt;
  final DateTime? serviceCompletedAt;
  final String? technicianName;
  final String? technicianCompanyAr;
  final String? addressSummaryAr;
  final List<RequestEvent> events;
  final bool canCancel;
  final bool canOpenComplaint;
  final bool canRate;

  bool get isUrgent => urgency.toUpperCase() == 'URGENT';

  /// Whether an arrival window has been promised. A dispatched order without one
  /// says so rather than showing an empty card.
  bool get hasExpectedArrival =>
      expectedArrivalStart != null || expectedArrivalEnd != null;

  /// Whether the technician has arrived, which is what turns the ETA card into a
  /// confirmation.
  bool get hasArrived => actualArrival != null;

  bool get hasAnyAction => canCancel || canOpenComplaint || canRate;

  @override
  List<Object?> get props => <Object?>[
    requestId,
    status,
    statusDescriptionAr,
    expectedArrivalStart,
    expectedArrivalEnd,
    actualArrival,
    workStartedAt,
    workCompletedAt,
    serviceCompletedAt,
    technicianName,
    addressSummaryAr,
    events,
    canCancel,
    canOpenComplaint,
    canRate,
  ];
}
