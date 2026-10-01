/// Base type for every error the app raises deliberately.
///
/// Repositories throw these instead of transport types, so the presentation
/// layer never imports Dio and never renders a status code (§95, §96).
sealed class AppException implements Exception {
  const AppException(this.message, {this.code, this.statusCode});

  /// Arabic message safe to show a customer.
  final String message;

  /// Stable machine-readable code. Behaviour keys off this, never the message.
  final String? code;

  final int? statusCode;

  @override
  String toString() =>
      '$runtimeType($code${statusCode == null ? '' : ', $statusCode'})';
}

/// The request never reached the server, or the reply never came back.
class NetworkException extends AppException {
  const NetworkException(super.message, {super.code, super.statusCode});
}

/// The server answered, but rejected the call.
class ServerException extends AppException {
  const ServerException(
    super.message, {
    super.code,
    super.statusCode,
    this.fieldErrors = const <String, String>{},
    this.correlationId,
  });

  final Map<String, String> fieldErrors;

  /// Support can trace this; shown in debug builds only (§93).
  final String? correlationId;
}

/// Local input failed a rule the client checks before spending a round trip.
class ValidationException extends AppException {
  const ValidationException(super.message, {this.field});

  final String? field;
}

/// The session is gone and the customer must sign in again.
class UnauthorisedException extends AppException {
  const UnauthorisedException([
    super.message = 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
  ]) : super(code: 'UNAUTHENTICATED', statusCode: 401);
}

/// The signed-in customer lacks permission for this action.
class ForbiddenException extends AppException {
  const ForbiddenException([
    super.message = 'ليس لديك صلاحية للقيام بهذا الإجراء.',
  ]) : super(code: 'FORBIDDEN', statusCode: 403);
}

/// A business rule refused the transition. The message comes from the backend
/// so deposit, cancellation and pricing policy is never decided in the client
/// (§8, §12, §13).
class DomainRuleException extends AppException {
  const DomainRuleException(
    super.message, {
    super.code,
    super.statusCode,
    this.details = const <String, dynamic>{},
  });

  final Map<String, dynamic> details;
}

/// Too many requests; the caller should back off.
class RateLimitedException extends AppException {
  const RateLimitedException([
    super.message = 'طلبات كثيرة جدًا. حاول مرة أخرى بعد قليل.',
  ]) : super(code: 'RATE_LIMITED', statusCode: 429);
}
