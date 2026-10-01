import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/errors/failure.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/models/auth_models.dart';
import '../../data/repositories/auth_repository.dart';

final Provider<AuthRemoteDataSource> authRemoteDataSourceProvider =
    Provider<AuthRemoteDataSource>(
      (Ref ref) => AuthRemoteDataSource(ref.watch(apiClientProvider).raw),
      name: 'authRemoteDataSource',
    );

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => AuthRepository(
        remote: ref.watch(authRemoteDataSourceProvider),
        tokenStore: ref.watch(tokenStoreProvider),
        client: ref.watch(apiClientProvider),
      ),
      name: 'authRepository',
    );

/// Failures the client detects itself, before the backend can answer. Rendered
/// through the ARB strings so no user-facing copy lives in a controller.
enum AuthErrorCode {
  /// The OTP screen is open but the phone it was sent to is gone, which means
  /// the session was reset and the customer has to enter the number again.
  phoneRequired,
}

/// Where the customer is in the sign-in flow.
enum AuthStage {
  /// Reading the token store. Nothing is rendered yet.
  restoring,

  /// No usable session: the customer must sign in.
  unauthenticated,

  /// A code was sent and is awaiting entry.
  awaitingOtp,

  /// A session exists.
  authenticated,
}

class AuthState extends Equatable {
  const AuthState({
    required this.stage,
    this.customer,
    this.phone,
    this.isNewCustomer = false,
    this.isSubmitting = false,
    this.otpExpiresInSeconds = 0,
    this.error,
    this.errorCode,
    this.resendAvailableAt,
  });

  const AuthState.restoring() : this(stage: AuthStage.restoring);

  final AuthStage stage;
  final CustomerProfile? customer;

  /// Phone the current OTP was sent to; retained so a resend does not need
  /// the form to still be mounted.
  final String? phone;

  final bool isNewCustomer;
  final bool isSubmitting;
  final int otpExpiresInSeconds;

  /// Message from the backend, already localized by the server. Prefer
  /// [errorCode] when the message would otherwise have to be authored in a
  /// controller, which has no access to the active locale.
  final String? error;

  /// Client-side failure that has no server message to show.
  final AuthErrorCode? errorCode;

  /// Wall-clock time a resend becomes allowed. The backend enforces the rate
  /// limit; this only keeps the UI from sending a request it knows will fail.
  final DateTime? resendAvailableAt;

  bool get isAuthenticated => stage == AuthStage.authenticated;
  bool get isRestoring => stage == AuthStage.restoring;
  bool get isAwaitingOtp => stage == AuthStage.awaitingOtp;

  bool get canResend {
    final at = resendAvailableAt;
    if (at == null) return false;
    return !DateTime.now().isBefore(at);
  }

  AuthState copyWith({
    AuthStage? stage,
    CustomerProfile? customer,
    String? phone,
    bool? isNewCustomer,
    bool? isSubmitting,
    int? otpExpiresInSeconds,
    String? error,
    AuthErrorCode? errorCode,
    bool clearError = false,
    DateTime? resendAvailableAt,
    bool clearResend = false,
  }) {
    return AuthState(
      stage: stage ?? this.stage,
      customer: customer ?? this.customer,
      phone: phone ?? this.phone,
      isNewCustomer: isNewCustomer ?? this.isNewCustomer,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      otpExpiresInSeconds: otpExpiresInSeconds ?? this.otpExpiresInSeconds,
      error: clearError ? null : (error ?? this.error),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      resendAvailableAt: clearResend
          ? null
          : (resendAvailableAt ?? this.resendAvailableAt),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    stage,
    customer,
    phone,
    isNewCustomer,
    isSubmitting,
    otpExpiresInSeconds,
    error,
    errorCode,
    resendAvailableAt,
  ];
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // The router waits on this provider to decide the first screen, so start in
    // the restoring stage and resolve it from [restoreSession].
    Future<void>.microtask(restoreSession);
    return const AuthState.restoring();
  }

  Future<void> restoreSession() async {
    // Yield once before touching `state`. [build] returns the restoring stage
    // synchronously and this method is reached from a microtask, so the element
    // may still be mounting — or already gone — on the first turn.
    //
    // A microtask is deliberate rather than Future.delayed: the latter leaves a
    // real Timer behind, which trips flutter_test's pending-timer assertion.
    await Future<void>.microtask(() {});
    if (!ref.mounted) return;
    state = state.copyWith(stage: AuthStage.restoring, clearError: true);
    try {
      final profile = await ref.read(authRepositoryProvider).restoreSession();
      if (profile == null) {
        state = state.copyWith(stage: AuthStage.unauthenticated);
        return;
      }
      state = state.copyWith(stage: AuthStage.authenticated, customer: profile);
    } on ApiFailure catch (failure) {
      // A network blip must not wipe the sign-in screen; the token is still
      // stored and the customer can retry.
      AppLogger.error(
        'session restore failed',
        context: <String, Object?>{
          'code': failure.code,
          'status': failure.statusCode,
        },
      );
      state = state.copyWith(
        stage: AuthStage.unauthenticated,
        error: failure.message,
      );
    }
  }

  Future<bool> requestOtp({required String phone, String? fullName}) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final challenge = await ref
          .read(authRepositoryProvider)
          .requestOtp(phone: phone, fullName: fullName);
      if (!ref.mounted) return false;
      state = state.copyWith(
        stage: AuthStage.awaitingOtp,
        isSubmitting: false,
        phone: phone,
        isNewCustomer: challenge.isNewCustomer,
        otpExpiresInSeconds: challenge.expiresInSeconds,
        resendAvailableAt: DateTime.now().add(
          Duration(seconds: challenge.expiresInSeconds),
        ),
      );
      return true;
    } on ApiFailure catch (failure) {
      state = state.copyWith(isSubmitting: false, error: failure.message);
      return false;
    }
  }

  Future<bool> verifyOtp({required String code, String? fullName}) async {
    final phone = state.phone;
    if (phone == null) {
      state = state.copyWith(errorCode: AuthErrorCode.phoneRequired);
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final customer = await ref
          .read(authRepositoryProvider)
          .verifyOtp(phone: phone, code: code, fullName: fullName);
      if (!ref.mounted) return false;
      state = state.copyWith(
        stage: AuthStage.authenticated,
        customer: customer,
        isSubmitting: false,
        clearResend: true,
      );
      return true;
    } on ApiFailure catch (failure) {
      state = state.copyWith(isSubmitting: false, error: failure.message);
      return false;
    }
  }

  /// Returns the customer to phone entry, e.g. from the "change number" action.
  void backToPhoneEntry() {
    state = const AuthState(stage: AuthStage.unauthenticated);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    if (!ref.mounted) return;
    state = const AuthState(stage: AuthStage.unauthenticated);
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

final NotifierProvider<AuthController, AuthState> authProvider =
    NotifierProvider<AuthController, AuthState>(
      AuthController.new,
      name: 'auth',
    );
