import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/auth_models.dart';

/// Authentication use case boundary.
///
/// Owns the invariant that matters most: after this returns, the token store
/// and the in-memory session agree. Nothing else is allowed to write tokens.
class AuthRepository {
  AuthRepository({
    required AuthRemoteDataSource remote,
    required TokenStore tokenStore,
    required ApiClient client,
  }) : _remote = remote,
       _tokenStore = tokenStore,
       _client = client;

  final AuthRemoteDataSource _remote;
  final TokenStore _tokenStore;
  final ApiClient _client;

  Future<OtpChallenge> requestOtp({required String phone, String? fullName}) {
    return _guard(() => _remote.requestOtp(phone: phone, fullName: fullName));
  }

  Future<CustomerProfile> verifyOtp({
    required String phone,
    required String code,
    String? fullName,
  }) {
    return _guard(() async {
      final session = await _remote.verifyOtp(
        phone: phone,
        code: code,
        fullName: fullName,
      );
      await _tokenStore.write(
        TokenPair(
          accessToken: session.tokens.accessToken,
          refreshToken: session.tokens.refreshToken,
          expiresAt: session.tokens.expiresAt,
        ),
      );
      return session.customer;
    });
  }

  /// Restores a session at app start.
  ///
  /// Returns null when there is no token or the token is unusable. A failure
  /// here must never block the app: the customer is simply sent to sign in.
  Future<CustomerProfile?> restoreSession() async {
    final TokenPair? tokens = await _tokenStore.read();
    if (tokens == null || tokens.accessToken.isEmpty) return null;

    try {
      final CustomerProfile profile = await _remote.me();
      return profile;
    } on ApiFailure catch (failure) {
      if (failure.isUnauthorized) {
        await _tokenStore.clear();
        return null;
      }
      rethrow;
    } on DioException {
      // Offline start with a valid token: keep it, let the UI show its own
      // empty/error states rather than forcing a sign-in.
      return null;
    }
  }

  Future<void> logout() async {
    final TokenPair? tokens = await _tokenStore.read();
    await _remote.logout(refreshToken: tokens?.refreshToken);
    await _tokenStore.clear();
  }

  /// Converts any transport error into an [ApiFailure] at the boundary.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw _client.translate(error);
    }
  }
}
