import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/paginated.dart';
import '../models/order_models.dart';

/// Reads order history and tracking.
///
/// The list endpoint is paginated (`{items, meta}`) and the tracking endpoint is
/// a plain object, so the two are read with different client helpers rather than
/// forced through one shape.
class OrdersRemoteDataSource {
  OrdersRemoteDataSource(this._client);

  final ApiClient _client;

  Future<Paginated<OrderSummary>> list({int page = 1, int perPage = 20}) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.orders,
      query: <String, dynamic>{'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(
      response.data ?? const <String, dynamic>{},
      OrderSummary.fromJson,
    );
  }

  Future<OrderTracking> track(String requestId) async {
    final Response<Map<String, dynamic>> response = await _client.get(
      ApiEndpoints.order(requestId),
    );
    return OrderTracking.fromJson(response.data ?? const <String, dynamic>{});
  }
}
