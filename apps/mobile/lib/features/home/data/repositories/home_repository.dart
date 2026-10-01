import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/network/api_client.dart';
import '../datasources/home_remote_data_source.dart';
import '../models/home_models.dart';

/// Repository for the home dashboard.
///
/// It translates transport failures into [ApiFailure] and does nothing else.
/// Pricing and recommendation rules stay on the backend (§8, §12).
class HomeRepository {
  HomeRepository(this._remote, this._client);

  final HomeRemoteDataSource _remote;
  final ApiClient _client;

  Future<HomeDashboard> dashboard() => _guard(_remote.loadDashboard);

  /// Runs [action] and maps any failure onto the app's error type, so widgets
  /// only ever see [ApiFailure].
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiFailure {
      rethrow;
    } on DioException catch (error) {
      throw _client.translate(error);
    } catch (error) {
      throw ApiFailure(
        code: 'UNEXPECTED',
        message: 'حدث خطأ غير متوقع.',
        details: <String, String>{'reason': error.runtimeType.toString()},
      );
    }
  }
}

/// Convenience providers so pages never build the object graph by hand.
final Provider<HomeRemoteDataSource> homeRemoteDataSourceProvider =
    Provider<HomeRemoteDataSource>(
      (Ref ref) => HomeRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'homeRemoteDataSource',
    );

final Provider<HomeRepository> homeRepositoryProvider = Provider<HomeRepository>(
  (Ref ref) => HomeRepository(
    ref.watch(homeRemoteDataSourceProvider),
    ref.watch(apiClientProvider),
  ),
  name: 'homeRepository',
);
