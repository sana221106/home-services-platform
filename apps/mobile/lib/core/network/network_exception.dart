import 'package:dio/dio.dart';

import '../errors/error_mapper.dart';

/// Network-layer facade over the app error types.
///
/// Repositories and pages import this so they get the transport bridge without
/// depending on Dio directly. The mapping itself lives in [ErrorMapper] and the
/// error vocabulary in `core/errors`, keeping one owner per concern (§95).
export '../errors/app_exception.dart'
    show
        AppException,
        DomainRuleException,
        ForbiddenException,
        NetworkException,
        RateLimitedException,
        ServerException,
        UnauthorisedException,
        ValidationException;

/// Whether a [DioException] can be retried unchanged.
///
/// Only idempotent read failures and timeouts qualify. A 409 conflict or a 422
/// validation error will fail the same way on retry, so retrying them just
/// burns battery and hides the real problem from the customer (§96).
bool isRetryableDioError(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => true,
    DioExceptionType.badResponse => (error.response?.statusCode ?? 0) >= 500,
    DioExceptionType.cancel ||
    DioExceptionType.badCertificate ||
    DioExceptionType.unknown ||
    DioExceptionType.transformTimeout => false,
  };
}

/// Number of retries for a transient failure, kept small so a customer is not
/// left staring at a spinner.
const int maxNetworkRetries = 1;
