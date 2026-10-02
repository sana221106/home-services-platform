import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/review_models.dart';

/// Customer rating reads and writes.
class ReviewsRemoteDataSource {
  const ReviewsRemoteDataSource(this._client);

  final ApiClient _client;

  Future<List<CustomerReview>> reviews() async {
    final Response<List<Map<String, dynamic>>> response = await _client.getList(
      ApiEndpoints.reviews,
    );
    return (response.data ?? const <Map<String, dynamic>>[])
        .map(CustomerReview.fromJson)
        .toList(growable: false);
  }

  /// Submits a rating for a completed request.
  ///
  /// The response comes back `PENDING` moderation, never published: publishing
  /// is a staff decision, so the screen says "sent" rather than "live".
  Future<CustomerReview> create({
    required String requestId,
    required int rating,
    String? text,
    bool hasImage = false,
    String? idempotencyKey,
  }) async {
    final Response<Map<String, dynamic>> response = await _client.post(
      ApiEndpoints.reviews,
      data: <String, dynamic>{
        'request_id': requestId,
        'rating': rating,
        if (text != null && text.isNotEmpty) 'text': text,
        'has_image': hasImage,
        'idempotency_key': ?idempotencyKey,
      },
    );
    return CustomerReview.fromJson(response.data ?? const <String, dynamic>{});
  }
}

final Provider<ReviewsRemoteDataSource> reviewsRemoteDataSourceProvider =
    Provider<ReviewsRemoteDataSource>(
      (Ref ref) => ReviewsRemoteDataSource(ref.watch(apiClientProvider)),
      name: 'reviewsRemoteDataSource',
    );
