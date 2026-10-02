import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/paginated.dart';
import '../datasources/orders_remote_data_source.dart';
import '../models/order_models.dart';

/// Repository for the orders feature.
///
/// Read-only: cancelling, rating and complaining all live on the request
/// endpoints, so nothing here writes (§30).
class OrdersRepository {
  OrdersRepository(this._orders, this._client);

  final OrdersRemoteDataSource _orders;
  final ApiClient _client;

  Future<Paginated<OrderSummary>> list({int page = 1, int perPage = 20}) =>
      _guard(() => _orders.list(page: page, perPage: perPage));

  Future<OrderTracking> track(String requestId) =>
      _guard(() => _orders.track(requestId));

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

final Provider<OrdersRemoteDataSource> ordersRemoteDataSourceProvider =
    Provider<OrdersRemoteDataSource>(
      (Ref ref) => OrdersRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'ordersRemoteDataSource',
    );

final Provider<OrdersRepository> ordersRepositoryProvider =
    Provider<OrdersRepository>(
      (Ref ref) => OrdersRepository(
        ref.watch(ordersRemoteDataSourceProvider),
        ref.watch(apiClientProvider),
      ),
      name: 'ordersRepository',
    );
