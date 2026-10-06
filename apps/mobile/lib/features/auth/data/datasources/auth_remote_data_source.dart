import 'package:dio/dio.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/errors/failure.dart';
import '../models/auth_models.dart';

/// Authenticated session: tokens plus the customer they belong to.
class AuthSession {
  const AuthSession({required this.tokens, required this.customer});

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      tokens: TokenPairPayload.fromJson(json['tokens'] as Map<String, dynamic>),
      customer: CustomerProfile.fromJson(
        json['customer'] as Map<String, dynamic>,
      ),
    );
  }

  final TokenPairPayload tokens;
  final CustomerProfile customer;
}

/// Mirrors the backend `TokenPair` contract.
class TokenPairPayload {
  const TokenPairPayload({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory TokenPairPayload.fromJson(Map<String, dynamic> json) {
    return TokenPairPayload(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

/// Translates the four auth endpoints.
///
/// The only job of this class is to turn a backend payload into a domain model
/// and let [ApiFailure] propagate: presentation code must never see a
/// [DioException].
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  Future<OtpChallenge> requestOtp({
    required String phone,
    String? fullName,
  }) async {
    final response = await _post(ApiEndpoints.authRequestOtp, <String, dynamic>{
      'phone': phone,
      if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
    });
    return OtpChallenge.fromJson(response);
  }

  Future<AuthSession> verifyOtp({
    required String phone,
    required String code,
    String? fullName,
  }) async {
    final response = await _post(ApiEndpoints.authVerifyOtp, <String, dynamic>{
      'phone': phone,
      'code': code,
      if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
    });
    return AuthSession.fromJson(response);
  }

  /// Exchanges the ID token Google issued on this device for our own session.
  ///
  /// The token is opaque here: Google's identity is verified server-side and
  /// only the resulting session is trusted.
  Future<AuthSession> signInWithGoogle({required String idToken}) async {
    final response = await _post(ApiEndpoints.authGoogle, <String, dynamic>{
      'id_token': idToken,
    });
    return AuthSession.fromJson(response);
  }

  Future<CustomerProfile> me() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiEndpoints.authMe);
    return CustomerProfile.fromJson(_data(response));
  }

  /// Best-effort: a failed logout must not trap the customer in the app.
  Future<void> logout({String? refreshToken}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.authLogout,
        // The backend declares `refresh_token` as nullable, so an explicit null
        // is a valid "revoke whatever is current" request.
        data: <String, dynamic>{'refresh_token': refreshToken},
      );
    } on DioException {
      // The local session is cleared regardless.
    }
  }

  Map<String, dynamic> _data(Response<Map<String, dynamic>> response) {
    final data = response.data;
    if (data == null) {
      throw const ApiFailure(
        code: 'EMPTY_RESPONSE',
        message: 'استجابة غير متوقعة من الخادم.',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(path, data: body);
    return _data(response);
  }
}
