import 'package:dio/dio.dart';

import 'app_exception.dart';
import 'failure.dart';

/// Converts transport failures into the app's own error types.
///
/// Kept out of `ApiClient` so the mapping is testable on its own and so no
/// widget ever needs to interpret a [DioException] (§95).
abstract final class ErrorMapper {
  /// Maps a Dio failure onto the closest [AppException].
  static AppException toException(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => const NetworkException(
        'استغرق الطلب وقتًا طويلًا. حاول مرة أخرى.',
        code: 'REQUEST_TIMEOUT',
      ),
      DioExceptionType.cancel => const NetworkException(
        'تم إلغاء الطلب.',
        code: 'REQUEST_CANCELLED',
      ),
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => const NetworkException(
        'تعذر الاتصال بالخادم. تحقق من اتصالك وحاول مرة أخرى.',
        code: 'NETWORK_UNAVAILABLE',
      ),
      DioExceptionType.badCertificate => const NetworkException(
        'تعذر التحقق من اتصال الخادم الآمن.',
        code: 'BAD_CERTIFICATE',
      ),
      DioExceptionType.badResponse => exceptionFromResponse(error.response),
    };
  }

  /// Builds the displayable [ApiFailure] straight from a non-2xx reply.
  ///
  /// Reads the envelope directly rather than going through [toException],
  /// because `correlationId` and `fieldErrors` are diagnostic data that must
  /// survive whatever exception subtype the code maps to. Support cannot trace a
  /// validation failure that lost its id on the way (§93).
  static ApiFailure failureFromResponse(Response<dynamic>? response) {
    final _Envelope envelope = _readEnvelope(response);
    return ApiFailure(
      code: envelope.code,
      message: envelope.message,
      statusCode: response?.statusCode,
      details: envelope.details,
      fieldErrors: _fieldErrors(envelope.rawDetails),
      correlationId: _correlationId(response),
    );
  }

  /// Maps a non-2xx reply using the backend envelope `{code, message, details}`.
  static AppException exceptionFromResponse(Response<dynamic>? response) {
    final _Envelope envelope = _readEnvelope(response);
    final int? status = response?.statusCode;

    return switch (envelope.code) {
      ApiErrorCodes.unauthenticated ||
      ApiErrorCodes.tokenExpired ||
      ApiErrorCodes.tokenRevoked => UnauthorisedException(envelope.message),
      ApiErrorCodes.forbidden => ForbiddenException(envelope.message),
      ApiErrorCodes.validationError => ValidationException(envelope.message),
      ApiErrorCodes.rateLimited => RateLimitedException(envelope.message),
      ApiErrorCodes.domainError ||
      ApiErrorCodes.invalidStateTransition ||
      ApiErrorCodes.notCancellable => DomainRuleException(
        envelope.message,
        code: envelope.code,
        statusCode: status,
        details: envelope.details,
      ),
      _ => ServerException(
        envelope.message,
        code: envelope.code,
        statusCode: status,
        fieldErrors: _fieldErrors(envelope.rawDetails),
        correlationId: _correlationId(response),
      ),
    };
  }

  /// Produces the displayable [ApiFailure] the repositories throw.
  static ApiFailure toFailure(DioException error) {
    if (error.response != null) return failureFromResponse(error.response);

    // Dio can raise a transport-level failure with no response at all; there is
    // no envelope to read, so the typed mapping supplies the vocabulary.
    final AppException mapped = toException(error);
    return ApiFailure(
      code: mapped.code ?? defaultCode(error.response?.statusCode),
      message: mapped.message,
      statusCode: mapped.statusCode,
      details: mapped is DomainRuleException
          ? mapped.details
          : const <String, dynamic>{},
      fieldErrors: mapped is ServerException
          ? mapped.fieldErrors
          : const <String, String>{},
      correlationId: mapped is ServerException ? mapped.correlationId : null,
    );
  }

  /// The parsed backend error envelope.
  static _Envelope _readEnvelope(Response<dynamic>? response) {
    final int? status = response?.statusCode;
    final Object? data = response?.data;
    final Map<String, dynamic> body = data is Map
        ? data.cast<String, dynamic>()
        : const <String, dynamic>{};
    final Object? rawDetails = body['details'];

    return _Envelope(
      code: body['code'] as String? ?? defaultCode(status),
      message: body['message'] as String? ?? fallbackMessage(status),
      rawDetails: rawDetails,
      details:
          (rawDetails as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }

  static String? _correlationId(Response<dynamic>? response) {
    final String? fromHeader = response?.headers.value('X-Correlation-ID');
    if (fromHeader != null && fromHeader.isNotEmpty) return fromHeader;
    final Object? fromRequest =
        response?.requestOptions.headers['X-Correlation-ID'];
    return fromRequest is String && fromRequest.isNotEmpty ? fromRequest : null;
  }

  static Map<String, String> _fieldErrors(Object? details) {
    if (details is! Map) return const <String, String>{};
    final Map<String, String> out = <String, String>{};
    details.forEach((Object? key, Object? value) {
      if (key is! String) return;
      if (value is String && value.isNotEmpty) {
        out[key] = value;
      } else if (value is List && value.isNotEmpty) {
        out[key] = value.first.toString();
      }
    });
    return out;
  }

  static String defaultCode(int? status) => switch (status) {
    400 || 422 => ApiErrorCodes.validationError,
    401 => ApiErrorCodes.unauthenticated,
    403 => ApiErrorCodes.forbidden,
    404 => ApiErrorCodes.notFound,
    409 => ApiErrorCodes.conflict,
    413 => ApiErrorCodes.uploadRejected,
    429 => ApiErrorCodes.rateLimited,
    null => 'NETWORK_UNAVAILABLE',
    _ => 'HTTP_$status',
  };

  static String fallbackMessage(int? status) {
    if (status == null) return 'تعذر الاتصال بالخادم.';
    if (status >= 500) return 'خدمة غير متاحة مؤقتًا. حاول مرة أخرى.';
    return switch (status) {
      401 => 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      403 => 'ليس لديك صلاحية للقيام بهذا الإجراء.',
      404 => 'العنصر المطلوب غير موجود.',
      409 => 'تم تعديل البيانات بالفعل. حدّث الصفحة وحاول مجددًا.',
      429 => 'طلبات كثيرة جدًا. حاول مرة أخرى بعد قليل.',
      _ => 'حدث خطأ غير متوقع.',
    };
  }
}

/// The parsed `{code, message, details}` envelope, with defaults already applied.
class _Envelope {
  const _Envelope({
    required this.code,
    required this.message,
    required this.rawDetails,
    required this.details,
  });

  final String code;
  final String message;

  /// `details` exactly as the backend sent it, before casting.
  ///
  /// Kept because a 422 uses a field-keyed map and a 409 uses structured
  /// context, so the two consumers need the raw shape, not one lossy version.
  final Object? rawDetails;

  final Map<String, dynamic> details;
}
