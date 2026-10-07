import 'package:equatable/equatable.dart';

/// Customer profile returned by the auth and profile endpoints.
///
/// Technician identity is deliberately absent: the customer app has no
/// technician fields at all, so a staff-name leak cannot be constructed here
/// even by accident (§9).
class CustomerProfile extends Equatable {
  const CustomerProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    this.avatarUrl,
    this.preferredLanguage = 'ar',
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    return CustomerProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      // Null for a customer who signed in without volunteering a phone.
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? 'ar',
    );
  }

  final String id;
  final String fullName;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final String preferredLanguage;

  /// First name only, for the home greeting.
  String get firstName {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return fullName;
    return trimmed.split(RegExp(r'\s+')).first;
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    fullName,
    phone,
    email,
    avatarUrl,
    preferredLanguage,
  ];
}

/// Result of `POST /api/v1/auth/request-otp`.
///
/// The OTP code itself is never returned to the client in production, so this
/// carries only the confirmation copy and whether the address is new.
class OtpChallenge extends Equatable {
  const OtpChallenge({
    required this.message,
    required this.expiresInSeconds,
    required this.isNewCustomer,
  });

  factory OtpChallenge.fromJson(Map<String, dynamic> json) {
    return OtpChallenge(
      message: json['message'] as String,
      expiresInSeconds: json['expires_in_seconds'] as int,
      isNewCustomer: json['is_new_customer'] as bool,
    );
  }

  final String message;
  final int expiresInSeconds;
  final bool isNewCustomer;

  @override
  List<Object?> get props => <Object?>[
    message,
    expiresInSeconds,
    isNewCustomer,
  ];
}
