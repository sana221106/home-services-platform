import 'package:equatable/equatable.dart';

/// Backend error codes the client reacts to programmatically.
///
/// The backend exposes exactly one error shape (§12): `{code, message, details}`.
/// Codes are stable identifiers, so behaviour keys off the code and never off
/// the human-readable message.
abstract final class ApiErrorCodes {
  static const String unauthenticated = 'UNAUTHENTICATED';
  static const String accountInactive = 'ACCOUNT_INACTIVE';
  static const String forbidden = 'FORBIDDEN';
  static const String notFound = 'NOT_FOUND';
  static const String conflict = 'CONFLICT';
  static const String domainError = 'DOMAIN_ERROR';
  static const String validationError = 'VALIDATION_ERROR';
  static const String rateLimited = 'RATE_LIMITED';
  static const String tokenExpired = 'TOKEN_EXPIRED';
  static const String tokenRevoked = 'TOKEN_REVOKED';
  static const String invalidCredentials = 'INVALID_CREDENTIALS';
  static const String otpExpired = 'OTP_EXPIRED';
  static const String otpAttemptsExceeded = 'OTP_ATTEMPTS_EXCEEDED';
  static const String invalidStateTransition = 'INVALID_STATE_TRANSITION';
  static const String quoteExpired = 'QUOTE_EXPIRED';
  static const String quoteAlreadyDecided = 'QUOTE_ALREADY_DECIDED';
  static const String quoteRevisionConflict = 'QUOTE_REVISION_CONFLICT';
  static const String paymentNotOpen = 'PAYMENT_NOT_OPEN';
  static const String paymentAlreadyDecided = 'PAYMENT_ALREADY_DECIDED';
  static const String idempotencyConflict = 'IDEMPOTENCY_CONFLICT';
  static const String notCancellable = 'NOT_CANCELLABLE';
  static const String mediaLocked = 'MEDIA_LOCKED';
  static const String uploadRejected = 'UPLOAD_REJECTED';
  static const String outOfCoverage = 'OUT_OF_COVERAGE';
  static const String integrationUnavailable = 'INTEGRATION_UNAVAILABLE';
  static const String aiNotConfigured = 'AI_NOT_CONFIGURED';
}

/// Failure surfaced to the presentation layer.
///
/// Every repository throws this instead of [DioException] so widgets never
/// need to know about HTTP and never show a raw status code to a customer.
class ApiFailure extends Equatable implements Exception {
  const ApiFailure({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const <String, dynamic>{},
    this.fieldErrors = const <String, String>{},
    this.correlationId,
  });

  const ApiFailure.network()
    : code = 'NETWORK_UNAVAILABLE',
      message = 'تعذر الاتصال بالخادم. تحقق من اتصالك وحاول مرة أخرى.',
      statusCode = null,
      details = const <String, dynamic>{},
      fieldErrors = const <String, String>{},
      correlationId = null;

  const ApiFailure.timeout()
    : code = 'REQUEST_TIMEOUT',
      message = 'استغرق الطلب وقتًا طويلًا. حاول مرة أخرى.',
      statusCode = null,
      details = const <String, dynamic>{},
      fieldErrors = const <String, String>{},
      correlationId = null;

  const ApiFailure.cancelled()
    : code = 'REQUEST_CANCELLED',
      message = 'تم إلغاء الطلب.',
      statusCode = null,
      details = const <String, dynamic>{},
      fieldErrors = const <String, String>{},
      correlationId = null;

  /// Stable machine-readable code from the backend.
  final String code;

  /// Arabic message safe to display. Never a raw stack trace or status line.
  final String message;

  final int? statusCode;

  /// Structured context such as cancellation-policy reasons.
  final Map<String, dynamic> details;

  /// Per-field messages for form validation.
  final Map<String, String> fieldErrors;

  /// Support can trace this in logs; shown only in debug builds.
  final String? correlationId;

  bool get isUnauthorized =>
      statusCode == 401 ||
      code == ApiErrorCodes.unauthenticated ||
      code == ApiErrorCodes.tokenExpired ||
      code == ApiErrorCodes.tokenRevoked;

  bool get isForbidden => statusCode == 403 || code == ApiErrorCodes.forbidden;

  bool get isNotFound => statusCode == 404 || code == ApiErrorCodes.notFound;

  bool get isConflict =>
      statusCode == 409 ||
      code == ApiErrorCodes.conflict ||
      code == ApiErrorCodes.invalidStateTransition;

  bool get isValidation =>
      statusCode == 422 || code == ApiErrorCodes.validationError;

  bool get isRateLimited =>
      statusCode == 429 || code == ApiErrorCodes.rateLimited;

  bool get isRetriable =>
      !isUnauthorized &&
      !isValidation &&
      code != ApiErrorCodes.invalidCredentials &&
      code != ApiErrorCodes.otpAttemptsExceeded;

  @override
  String toString() =>
      'ApiFailure($code, status: $statusCode, correlation: $correlationId)';

  @override
  List<Object?> get props => <Object?>[
    code,
    message,
    statusCode,
    details,
    fieldErrors,
    correlationId,
  ];
}
