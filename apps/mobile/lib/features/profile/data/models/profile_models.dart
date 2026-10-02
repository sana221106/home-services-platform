import 'package:equatable/equatable.dart';

import '../../../../core/network/json_readers.dart';

/// The customer's profile as returned by `GET /profile`.
///
/// Carries the lifetime totals as well as the identity fields, so the account
/// screen does not need a second round trip for the counters under the header.
class ProfileDetails extends Equatable {
  const ProfileDetails({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    this.avatarUrl,
    this.preferredLanguage = 'ar',
    this.propertiesCount = 0,
    this.requestsCount = 0,
    this.completedOrdersCount = 0,
    this.memberSince,
  });

  factory ProfileDetails.fromJson(Map<String, dynamic> json) {
    return ProfileDetails(
      id: json.strOr('id', ''),
      fullName: json.strOr('full_name', ''),
      phone: json.strOr('phone', ''),
      email: json.str('email'),
      avatarUrl: json.str('avatar_url'),
      preferredLanguage: json.strOr('preferred_language', 'ar'),
      propertiesCount: json.intOr('properties_count', 0),
      requestsCount: json.intOr('requests_count', 0),
      completedOrdersCount: json.intOr('completed_orders_count', 0),
      memberSince: json.time('member_since'),
    );
  }

  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final String? avatarUrl;
  final String preferredLanguage;
  final int propertiesCount;
  final int requestsCount;
  final int completedOrdersCount;
  final DateTime? memberSince;

  /// Initials for the avatar fallback. Arabic names split on whitespace the same
  /// way Latin ones do, so the first letters of the first two words are enough.
  String get initials {
    final List<String> parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1);
    return '${parts[0].substring(0, 1)}${parts[1].substring(0, 1)}';
  }

  bool get hasAvatar => avatarUrl != null && avatarUrl!.isNotEmpty;

  @override
  List<Object?> get props => <Object?>[
    id,
    fullName,
    phone,
    email,
    avatarUrl,
    preferredLanguage,
    propertiesCount,
    requestsCount,
    completedOrdersCount,
    memberSince,
  ];
}
