import 'package:dio/dio.dart';

import '../errors/error_mapper.dart';

/// Uniform result of an API call.
///
/// Repositories return this instead of throwing raw [DioException], so pages
/// have one shape to handle for success and failure (§24, §96).
sealed class ApiResponse<T> {
  const ApiResponse();

  /// Runs [action] and captures its outcome.
  static Future<ApiResponse<T>> guard<T>(Future<T> Function() action) async {
    try {
      return ApiSuccess<T>(await action());
    } on DioException catch (error) {
      return ApiErrorResult<T>(ErrorMapper.toException(error));
    }
  }

  bool get isSuccess => this is ApiSuccess<T>;

  /// The value, or null when the call failed.
  T? get valueOrNull => switch (this) {
    ApiSuccess<T>(:final T value) => value,
    ApiErrorResult<T>() => null,
  };

  /// The failure, or null when the call succeeded.
  Object? get errorOrNull => switch (this) {
    ApiSuccess<T>() => null,
    ApiErrorResult<T>(:final Object error) => error,
  };

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Object error) onError,
  }) => switch (this) {
    ApiSuccess<T>(:final T value) => onSuccess(value),
    ApiErrorResult<T>(:final Object error) => onError(error),
  };
}

class ApiSuccess<T> extends ApiResponse<T> {
  const ApiSuccess(this.value);

  final T value;
}

class ApiErrorResult<T> extends ApiResponse<T> {
  const ApiErrorResult(this.error);

  final Object error;
}
