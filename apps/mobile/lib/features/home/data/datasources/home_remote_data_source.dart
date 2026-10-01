import 'package:dio/dio.dart';

import '../../../../../core/network/api_client.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../models/home_models.dart';

/// Reads the home dashboard.
///
/// `GET /api/v1/home` is declared `response_model=dict` on the backend, so the
/// envelope is untyped. Parsing defensively in [HomeDashboard.fromJson] is
/// deliberate: a missing optional block must degrade the home screen, not crash
/// it.
class HomeRemoteDataSource {
  HomeRemoteDataSource(this._client);

  final ApiClient _client;

  Future<HomeDashboard> loadDashboard() async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.home,
    );
    return HomeDashboard.fromJson(response.data ?? const <String, dynamic>{});
  }
}
