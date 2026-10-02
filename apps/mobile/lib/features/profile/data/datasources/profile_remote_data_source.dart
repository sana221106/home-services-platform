import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/profile_models.dart';

/// Reads and updates the customer's own profile.
class ProfileRemoteDataSource {
  ProfileRemoteDataSource(this._client);

  final ApiClient _client;

  Future<ProfileDetails> profile() async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.profile,
    );
    return ProfileDetails.fromJson(response.data ?? const <String, dynamic>{});
  }

  /// The endpoint is a PATCH, so only the fields the customer actually changed
  /// are sent; an omitted field is left as it was on the server.
  Future<ProfileDetails> update({
    String? fullName,
    String? email,
    String? preferredLanguage,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.patch(
      ApiEndpoints.profile,
      data: <String, dynamic>{
        'full_name': ?fullName,
        'email': ?email,
        'preferred_language': ?preferredLanguage,
      },
    );
    return ProfileDetails.fromJson(response.data ?? const <String, dynamic>{});
  }
}
