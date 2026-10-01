import 'package:equatable/equatable.dart';

/// Counts the home screen shows in its greeting cards.
class GreetingCounts extends Equatable {
  const GreetingCounts({
    required this.activeRequests,
    required this.awaitingPayment,
    required this.awaitingRating,
    required this.openQuotes,
  });

  factory GreetingCounts.fromJson(Map<String, dynamic> json) {
    return GreetingCounts(
      activeRequests: _asInt(json['active_requests']),
      awaitingPayment: _asInt(json['awaiting_payment']),
      awaitingRating: _asInt(json['awaiting_rating']),
      openQuotes: _asInt(json['open_quotes']),
    );
  }

  final int activeRequests;
  final int awaitingPayment;
  final int awaitingRating;
  final int openQuotes;

  /// Total badge count for the notifications bell.
  int get attentionCount =>
      activeRequests + awaitingPayment + awaitingRating + openQuotes;

  @override
  List<Object?> get props => <Object?>[
    activeRequests,
    awaitingPayment,
    awaitingRating,
    openQuotes,
  ];
}

/// A service category offered by the catalogue.
class ServiceCategorySummary extends Equatable {
  const ServiceCategorySummary({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.iconKey,
    this.colorHex,
  });

  factory ServiceCategorySummary.fromJson(Map<String, dynamic> json) {
    return ServiceCategorySummary(
      id: json['id'] as String,
      code: json['code'] as String,
      nameAr: json['name_ar'] as String,
      iconKey: json['icon_key'] as String? ?? 'wrench',
      colorHex: json['color_hex'] as String?,
    );
  }

  final String id;
  final String code;

  /// Arabic name from the catalogue. The catalogue is bilingual, so the
  /// backend already resolved the right language for the customer.
  final String nameAr;

  /// Key such as `faucet` or `bolt`, mapped to a bundled SVG locally.
  final String iconKey;

  final String? colorHex;

  @override
  List<Object?> get props => <Object?>[id, code, nameAr, iconKey, colorHex];
}

/// Server-driven quick action.
class QuickAction extends Equatable {
  const QuickAction({required this.code, required this.labelAr});

  factory QuickAction.fromJson(Map<String, dynamic> json) {
    return QuickAction(
      code: json['code'] as String,
      labelAr: json['label_ar'] as String,
    );
  }

  final String code;
  final String labelAr;

  @override
  List<Object?> get props => <Object?>[code, labelAr];
}

/// One of the customer's in-flight requests, as shown on the home screen.
class ActiveRequestSummary extends Equatable {
  const ActiveRequestSummary({
    required this.requestId,
    required this.referenceCode,
    required this.status,
    required this.categoryNameAr,
    required this.nextStepAr,
  });

  factory ActiveRequestSummary.fromJson(Map<String, dynamic> json) {
    return ActiveRequestSummary(
      requestId: json['request_id'] as String,
      referenceCode: json['reference_code'] as String,
      status: json['status'] as String,
      categoryNameAr: json['category_name_ar'] as String,
      nextStepAr: json['next_step_ar'] as String? ?? '',
    );
  }

  final String requestId;
  final String referenceCode;
  final String status;

  /// The server supplies the human next step, so the lifecycle copy cannot
  /// drift between app versions and the backend state machine.
  final String categoryNameAr;
  final String nextStepAr;

  @override
  List<Object?> get props => <Object?>[
    requestId,
    referenceCode,
    status,
    categoryNameAr,
    nextStepAr,
  ];
}

class HomeDashboard extends Equatable {
  const HomeDashboard({
    required this.greeting,
    required this.categories,
    required this.quickActions,
    required this.activeRequests,
    required this.unreadNotifications,
    required this.unreadChat,
  });

  factory HomeDashboard.fromJson(Map<String, dynamic> json) {
    return HomeDashboard(
      greeting: GreetingCounts.fromJson(
        json['greeting'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      categories: _list(json['categories'], ServiceCategorySummary.fromJson),
      quickActions: _list(json['quick_actions'], QuickAction.fromJson),
      activeRequests: _list(
        json['active_requests'],
        ActiveRequestSummary.fromJson,
      ),
      unreadNotifications: _asInt(json['unread_notifications']),
      unreadChat: _asInt(json['unread_chat']),
    );
  }

  final GreetingCounts greeting;
  final List<ServiceCategorySummary> categories;
  final List<QuickAction> quickActions;
  final List<ActiveRequestSummary> activeRequests;
  final int unreadNotifications;
  final int unreadChat;

  int get unreadTotal => unreadNotifications + unreadChat;

  @override
  List<Object?> get props => <Object?>[
    greeting,
    categories,
    quickActions,
    activeRequests,
    unreadNotifications,
    unreadChat,
  ];
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw is! List) return const <Never>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList(growable: false);
}

int _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  _ => 0,
};
