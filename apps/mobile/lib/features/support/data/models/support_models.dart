import 'package:equatable/equatable.dart';

import '../../../../core/network/json_readers.dart';

/// A support thread.
///
/// `unread_count` counts only messages the customer has not read, which is what
/// the badge shows; the customer's own messages never make a thread look unread.
class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.subject,
    required this.isOpen,
    this.requestId,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json.strOr('id', ''),
      subject: json.strOr('subject', ''),
      isOpen: json.flag('is_open'),
      requestId: json.str('request_id'),
      lastMessageAt: json.time('last_message_at'),
      lastMessagePreview: json.str('last_message_preview'),
      unreadCount: json.intOr('unread_count', 0),
    );
  }

  final String id;
  final String subject;
  final bool isOpen;
  final String? requestId;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadCount;

  bool get isUnread => unreadCount > 0;

  @override
  List<Object?> get props => <Object?>[
    id,
    subject,
    isOpen,
    requestId,
    lastMessageAt,
    lastMessagePreview,
    unreadCount,
  ];
}

/// One message inside a thread.
///
/// `senderType` is `customer` or `support`; the client never invents a third
/// sender, and it never renders the support agent's identity because the backend
/// does not publish one (§9).
class SupportMessage extends Equatable {
  const SupportMessage({
    required this.id,
    required this.body,
    required this.senderType,
    this.sentAt,
    this.attachmentUrls = const <String>[],
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: json.strOr('id', ''),
      body: json.strOr('body', ''),
      senderType: json.strOr('sender_type', 'support'),
      sentAt: json.time('sent_at'),
      attachmentUrls: json.stringList('attachment_urls'),
    );
  }

  final String id;
  final String body;

  /// `customer` for the user's own messages, anything else for the team.
  final String senderType;

  final DateTime? sentAt;
  final List<String> attachmentUrls;

  bool get isFromCustomer => senderType.toLowerCase() == 'customer';

  @override
  List<Object?> get props => <Object?>[id, body, senderType, sentAt];
}

/// Why a complaint was raised, mirroring the backend `ComplaintReason` enum.
///
/// The backend sends codes, not display text, so this holds codes only and the
/// wording lives in the ARB files. `fromCode` keeps an unrecognised code as-is
/// rather than dropping the complaint, which is what happens if the server adds
/// a reason before the app ships support for it.
class ComplaintReasonCode {
  const ComplaintReasonCode(this.code);

  final String code;

  static const List<ComplaintReasonCode> all = <ComplaintReasonCode>[
    ComplaintReasonCode('WORK_NOT_DONE'),
    ComplaintReasonCode('POOR_QUALITY'),
    ComplaintReasonCode('OVERCHARGE'),
    ComplaintReasonCode('TECHNICIAN_LATE'),
    ComplaintReasonCode('DAMAGE'),
    ComplaintReasonCode('RECURRING_FAULT'),
    ComplaintReasonCode('OTHER'),
  ];

  static ComplaintReasonCode fromCode(String? code) {
    if (code == null || code.isEmpty) return const ComplaintReasonCode('');
    for (final ComplaintReasonCode reason in all) {
      if (reason.code == code) return reason;
    }
    return ComplaintReasonCode(code);
  }
}

/// One complaint the customer filed.
class Complaint extends Equatable {
  const Complaint({
    required this.id,
    required this.referenceCode,
    required this.reason,
    required this.description,
    required this.status,
    required this.createdAt,
    this.requestId,
    this.resolution,
    this.resolvedAt,
    this.closedAt,
    this.requiresRework = false,
    this.attachmentUrls = const <String>[],
  });

  factory Complaint.fromJson(Map<String, dynamic> json) {
    return Complaint(
      id: json.strOr('id', ''),
      referenceCode: json.strOr('reference_code', ''),
      reason: json.strOr('reason', ''),
      description: json.strOr('description', ''),
      status: json.strOr('status', ''),
      createdAt: json.time('created_at'),
      requestId: json.str('request_id'),
      resolution: json.str('resolution'),
      resolvedAt: json.time('resolved_at'),
      closedAt: json.time('closed_at'),
      requiresRework: json.flag('requires_rework'),
      attachmentUrls: json.stringList('attachment_urls'),
    );
  }

  final String id;
  final String referenceCode;
  final String reason;
  final String description;
  final String status;
  final DateTime? createdAt;
  final String? requestId;
  final String? resolution;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final bool requiresRework;
  final List<String> attachmentUrls;

  ComplaintReasonCode get reasonLabel => ComplaintReasonCode.fromCode(reason);

  /// Only `RESOLVED` and `CLOSED` are final; everything else is still moving,
  /// so the customer should not be told it is finished.
  bool get isSettled => status == 'RESOLVED' || status == 'CLOSED';

  @override
  List<Object?> get props => <Object?>[
    id,
    referenceCode,
    reason,
    description,
    status,
    resolution,
    resolvedAt,
    requiresRework,
  ];
}
