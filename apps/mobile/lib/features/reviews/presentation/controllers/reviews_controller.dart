import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../data/models/review_models.dart';
import '../../data/repositories/reviews_repository.dart';

enum ReviewsStatus { initial, loading, ready, failed }

class ReviewsState extends Equatable {
  const ReviewsState({
    this.status = ReviewsStatus.initial,
    this.reviews = const <CustomerReview>[],
    this.errorMessage,
    this.isSubmitting = false,
    this.submitted,
  });

  final ReviewsStatus status;
  final List<CustomerReview> reviews;
  final String? errorMessage;
  final bool isSubmitting;

  /// Set once a rating is accepted, so the sheet can confirm and close.
  final CustomerReview? submitted;

  ReviewsState copyWith({
    ReviewsStatus? status,
    List<CustomerReview>? reviews,
    String? errorMessage,
    bool? isSubmitting,
    CustomerReview? submitted,
    bool clearError = false,
    bool clearSubmitted = false,
  }) {
    return ReviewsState(
      status: status ?? this.status,
      reviews: reviews ?? this.reviews,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitted: clearSubmitted ? null : (submitted ?? this.submitted),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    reviews,
    errorMessage,
    isSubmitting,
    submitted,
  ];
}

/// The customer's own ratings, listed most recent first by the backend.
class ReviewsController extends Notifier<ReviewsState> {
  @override
  ReviewsState build() => const ReviewsState();

  Future<void> load() async {
    state = state.copyWith(status: ReviewsStatus.loading, clearError: true);
    try {
      final List<CustomerReview> reviews = await ref
          .read(reviewsRepositoryProvider)
          .reviews();
      state = ReviewsState(
        status: ReviewsStatus.ready,
        reviews: reviews,
        // A reload must not wipe a just-submitted confirmation.
        submitted: state.submitted,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        status: ReviewsStatus.failed,
        errorMessage: failure.message,
      );
    }
  }

  /// Submits a rating, then prepends it to the list.
  ///
  /// No refetch: the response is the same row the list would get back, and the
  /// customer wants to see their rating immediately rather than after a round
  /// trip that returns identical data.
  Future<CustomerReview?> submit({
    required String requestId,
    required int rating,
    String? text,
  }) async {
    if (state.isSubmitting) return null;

    state = state.copyWith(
      isSubmitting: true,
      clearError: true,
      clearSubmitted: true,
    );
    try {
      final CustomerReview review = await ref
          .read(reviewsRepositoryProvider)
          .create(requestId: requestId, rating: rating, text: text);
      state = state.copyWith(
        reviews: <CustomerReview>[review, ...state.reviews],
        isSubmitting: false,
        submitted: review,
      );
      return review;
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: failure.message,
      );
      return null;
    }
  }

  /// Clears the confirmation once the sheet has closed on it.
  void acknowledgeSubmitted() {
    if (state.submitted != null) {
      state = state.copyWith(clearSubmitted: true);
    }
  }
}

final NotifierProvider<ReviewsController, ReviewsState> reviewsProvider =
    NotifierProvider<ReviewsController, ReviewsState>(
      ReviewsController.new,
      name: 'reviews',
    );
