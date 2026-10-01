import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_failure.dart';
import 'models/home_models.dart';

/// Reads the home dashboard.
///
/// `GET /api/v1/home` is declared `response_model=dict` on the backend, so the
/// envelope is untyped. Parsing defensively here is deliberate: a missing
/// optional block must degrade the home screen, not crash it.
class HomeRemoteDataSource {
  HomeRemoteDataSource(this._dio);

  final Dio _dio;

  Future<HomeDashboard> fetch() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiEndpoints.home);
    final data = response.data;
    if (data == null) {
      throw const ApiFailure(
        code: 'EMPTY_RESPONSE',
        message: 'استجابة غير متوقعة من الخادم.',
      );
    }
    return HomeDashboard.fromJson(data);
  }
}

class HomeRepository {
  HomeRepository({
    required HomeRemoteDataSource remote,
    required ApiClient client,
  }) : _remote = remote,
       _client = client;

  final HomeRemoteDataSource _remote;
  final ApiClient _client;

  Future<HomeDashboard> load() async {
    try {
      return await _remote.fetch();
    } on DioException catch (error) {
      throw _client.translate(error);
    }
  }
}
