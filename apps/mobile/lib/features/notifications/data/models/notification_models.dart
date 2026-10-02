import '../../../../core/network/json_readers.dart';

/// A customer notification.
///
/// The backend composes `title`/`body` per event, so the copy is server-owned
/// and shown verbatim. Re-keying it in the ARB would add a second place to keep
/// in step with the backend wording and gain nothing: the text is already in the
/// customer's language and already accounts for the request it belongs to.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.requestId,
    this.payload = const <String, dynamic>{},
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json.strOr('id', ''),
      requestId: json.str('request_id'),
      type: NotificationType.fromCode(json.strOr('type', '')),
      title: json.strOr('title_ar', ''),
      body: json.strOr('body_ar', ''),
      payload: json.obj('payload'),
      isRead: json.flag('is_read'),
      readAt: json.time('read_at'),
      createdAt:
          json.time('created_at') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;

  /// Null for events that are not tied to a request, such as a general
  /// announcement.
  final String? requestId;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get hasRequest => requestId != null && requestId!.isNotEmpty;

  AppNotification copyWith({bool? isRead, DateTime? readAt}) {
    return AppNotification(
      id: id,
      requestId: requestId,
      type: type,
      title: title,
      body: body,
      payload: payload,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }
}

/// The notification kinds the backend can raise.
///
/// Carries an [unknown] fallback because the backend gains event types without a
/// client release, and a new kind must still render rather than throw.
enum NotificationType {
  requestReceived('REQUEST_RECEIVED'),
  needMoreInformation('NEED_MORE_INFORMATION'),
  quoteReady('QUOTE_READY'),
  quoteRevised('QUOTE_REVISED'),
  depositRequired('DEPOSIT_REQUIRED'),
  depositVerified('DEPOSIT_VERIFIED'),
  requestConfirmed('REQUEST_CONFIRMED'),
  appointmentScheduled('APPOINTMENT_SCHEDULED'),
  technicianAssigned('TECHNICIAN_ASSIGNED'),
  expectedArrivalUpdated('EXPECTED_ARRIVAL_UPDATED'),
  onTheWay('ON_THE_WAY'),
  serviceStarted('SERVICE_STARTED'),
  serviceCompleted('SERVICE_COMPLETED'),
  paymentRequired('PAYMENT_REQUIRED'),
  paymentConfirmed('PAYMENT_CONFIRMED'),
  complaintUpdate('COMPLAINT_UPDATE'),
  ratingReminder('RATING_REMINDER'),
  unknown('');

  const NotificationType(this.code);

  final String code;

  static NotificationType fromCode(String code) {
    for (final NotificationType value in NotificationType.values) {
      if (value != NotificationType.unknown && value.code == code) {
        return value;
      }
    }
    return NotificationType.unknown;
  }

  /// The asset that matches the event, so the row reads at a glance instead of
  /// needing to be opened.
  String get iconAsset => switch (this) {
    NotificationType.requestReceived ||
    NotificationType.requestConfirmed ||
    NotificationType.appointmentScheduled ||
    NotificationType.serviceCompleted ||
    NotificationType.depositVerified => 'assets/icons/check.svg',
    NotificationType.needMoreInformation ||
    NotificationType.complaintUpdate => 'assets/icons/chat.svg',
    NotificationType.quoteReady ||
    NotificationType.quoteRevised => 'assets/icons/receipt.svg',
    NotificationType.depositRequired ||
    NotificationType.paymentRequired => 'assets/icons/wallet.svg',
    NotificationType.paymentConfirmed => 'assets/icons/card.svg',
    NotificationType.technicianAssigned => 'assets/icons/user.svg',
    NotificationType.expectedArrivalUpdated ||
    NotificationType.serviceStarted => 'assets/icons/clock.svg',
    NotificationType.onTheWay => 'assets/icons/truck.svg',
    NotificationType.ratingReminder => 'assets/icons/star.svg',
    NotificationType.unknown => 'assets/icons/bell.svg',
  };
}
