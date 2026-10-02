import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/app_bootstrap.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../datasources/reviews_remote_data_source.dart';
import '../models/review_models.dart';

/// Repository for the customer's own ratings.
class ReviewsRepository {
  ReviewsRepository(this._reviews, this._client);

  final ReviewsRemoteDataSource _reviews;
  final ApiClient _client;

  Future<List<CustomerReview>> reviews() => _guard(_reviews.reviews);

  Future<CustomerReview> create({
    required String requestId,
    required int rating,
    String? text,
    bool hasImage = false,
    String? idempotencyKey,
  }) => _guard(
    () => _reviews.create(
      requestId: requestId,
      rating: rating,
      text: text,
      hasImage: hasImage,
      idempotencyKey: idempotencyKey,
    ),
  );

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

final Provider<ReviewsRepository> reviewsRepositoryProvider =
    Provider<ReviewsRepository>(
      (Ref ref) => ReviewsRepository(
        ref.watch(reviewsRemoteDataSourceProvider),
        ref.watch(apiClientProvider),
      ),
      name: 'reviewsRepository',
    );
