import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:home_services_app/app/localization/app_localizations.dart';
import 'package:home_services_app/app/theme/app_theme.dart';
import 'package:home_services_app/core/errors/failure.dart';

import 'package:home_services_app/features/reviews/data/models/review_models.dart';
import 'package:home_services_app/features/reviews/data/repositories/reviews_repository.dart';
import 'package:home_services_app/features/reviews/presentation/controllers/reviews_controller.dart';
import 'package:home_services_app/features/reviews/presentation/pages/reviews_page.dart';

void main() {
  group('CustomerReview', () {
    test('parses the payload including moderation state', () {
      final CustomerReview review = CustomerReview.fromJson(<String, dynamic>{
        'id': 'rev-1',
        'request_id': 'req-1',
        'rating': 5,
        'text': 'Excellent work',
        'publication_status': 'APPROVED',
        'image_url': 'https://cdn.example/rev.jpg',
        'created_at': '2026-01-02T10:00:00Z',
      });

      expect(review.rating, 5);
      expect(review.isPublic, isTrue);
      expect(review.hasText, isTrue);
      expect(review.hasImage, isTrue);
    });

    test('a pending review is not reported as public', () {
      final CustomerReview review = CustomerReview.fromJson(<String, dynamic>{
        'id': 'rev-2',
        'rating': 4,
        'publication_status': 'PENDING',
        'created_at': '2026-01-02T10:00:00Z',
      });

      expect(review.isPublic, isFalse);
      expect(review.hasText, isFalse);
      expect(review.clampedRating, 4);
    });

    test('an out-of-range rating is clamped so the stars still render', () {
      final CustomerReview review = CustomerReview.fromJson(<String, dynamic>{
        'id': 'rev-3',
        'rating': 9,
        'publication_status': 'APPROVED',
        'created_at': '2026-01-02T10:00:00Z',
      });

      expect(review.clampedRating, 5);
    });
  });

  group('ReviewsController', () {
    test('load fills the list', () async {
      final ProviderContainer container = _container(_FakeReviewsRepository());
      addTearDown(container.dispose);

      await container.read(reviewsProvider.notifier).load();

      final ReviewsState state = container.read(reviewsProvider);
      expect(state.status, ReviewsStatus.ready);
      expect(state.reviews, hasLength(1));
    });

    test('a failed load offers the message', () async {
      final ProviderContainer container = _container(
        _FakeReviewsRepository()
          ..listError = const ApiFailure(
            code: 'NETWORK',
            message: 'Unavailable',
          ),
      );
      addTearDown(container.dispose);

      await container.read(reviewsProvider.notifier).load();

      expect(container.read(reviewsProvider).errorMessage, 'Unavailable');
    });

    test('submit puts the new rating first without refetching', () async {
      final _FakeReviewsRepository repository = _FakeReviewsRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      await container.read(reviewsProvider.notifier).load();
      final CustomerReview? created = await container
          .read(reviewsProvider.notifier)
          .submit(requestId: 'req-2', rating: 5, text: 'Great');

      expect(created, isNotNull);
      expect(container.read(reviewsProvider).reviews.first.rating, 5);
      expect(container.read(reviewsProvider).submitted, isNotNull);
      // No extra read: the response already is the row the list shows.
      expect(repository.listCalls, 1);
    });

    test('a rejected submit returns null and keeps the message', () async {
      final ProviderContainer container = _container(
        _FakeReviewsRepository()
          ..createError = const ApiFailure(
            code: 'VALIDATION',
            message: 'Already rated',
          ),
      );
      addTearDown(container.dispose);

      final CustomerReview? created = await container
          .read(reviewsProvider.notifier)
          .submit(requestId: 'req-1', rating: 4);

      expect(created, isNull);
      final ReviewsState state = container.read(reviewsProvider);
      expect(state.errorMessage, 'Already rated');
      expect(state.isSubmitting, isFalse);
    });

    test('a reload does not wipe a just-submitted confirmation', () async {
      final ProviderContainer container = _container(_FakeReviewsRepository());
      addTearDown(container.dispose);

      await container
          .read(reviewsProvider.notifier)
          .submit(requestId: 'req-2', rating: 3);
      await container.read(reviewsProvider.notifier).load();

      expect(container.read(reviewsProvider).submitted, isNotNull);
    });
  });

  group('ReviewsPage', () {
    testWidgets('lists the ratings with their moderation state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_wrap(_FakeReviewsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Excellent work'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
    });

    testWidgets('a pending rating says it is awaiting moderation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakeReviewsRepository()
            ..listValue = <CustomerReview>[
              CustomerReview(
                id: 'rev-1',
                requestId: 'req-1',
                rating: 4,
                publicationStatus: 'PENDING',
                createdAt: DateTime(2026, 1, 2),
              ),
            ],
        ),
      );
      await tester.pumpAndSettle();

      // Must not read as live when it is still being moderated.
      expect(find.text('Awaiting moderation'), findsOneWidget);
    });

    testWidgets('explains itself when there are no ratings', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_FakeReviewsRepository()..listValue = <CustomerReview>[]),
      );
      await tester.pumpAndSettle();

      expect(find.text('No reviews yet'), findsOneWidget);
    });

    testWidgets('a failed load offers a retry that refetches', (
      WidgetTester tester,
    ) async {
      final _FakeReviewsRepository repository = _FakeReviewsRepository()
        ..listError = const ApiFailure(code: 'NETWORK', message: 'Unavailable');
      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('Unavailable'), findsOneWidget);

      repository.listError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Excellent work'), findsOneWidget);
    });
  });

  group('RateServicePage', () {
    testWidgets('submit is blocked until a star is chosen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _FakeReviewsRepository(),
          child: const RateServicePage(requestId: 'req-2'),
        ),
      );
      await tester.pumpAndSettle();

      FilledButton button() =>
          tester.widget<FilledButton>(find.byKey(const Key('review-submit')));

      expect(button().onPressed, isNull);

      await tester.tap(find.byKey(const Key('rating-star-4')));
      await tester.pumpAndSettle();

      expect(button().onPressed, isNotNull);
    });

    testWidgets('submitting sends the score and the comment', (
      WidgetTester tester,
    ) async {
      final _FakeReviewsRepository repository = _FakeReviewsRepository();
      await tester.pumpWidget(
        _wrap(repository, child: const RateServicePage(requestId: 'req-2')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('rating-star-5')));
      await tester.enterText(
        find.byKey(const Key('review-comment')),
        'Excellent work',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-submit')));
      await tester.pumpAndSettle();

      expect(repository.createdRating, 5);
      expect(repository.createdText, 'Excellent work');
    });

    testWidgets('a rejected rating keeps the customer on the form', (
      WidgetTester tester,
    ) async {
      final _FakeReviewsRepository repository = _FakeReviewsRepository()
        ..createError = const ApiFailure(
          code: 'VALIDATION',
          message: 'Already rated',
        );
      await tester.pumpWidget(
        _wrap(repository, child: const RateServicePage(requestId: 'req-2')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('rating-star-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Already rated'), findsOneWidget);
    });
  });
}

Widget _wrap(
  _FakeReviewsRepository repository, {
  Widget child = const ReviewsPage(),
}) {
  return ProviderScope(
    overrides: <Override>[
      reviewsRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

ProviderContainer _container(_FakeReviewsRepository repository) {
  return ProviderContainer(
    overrides: <Override>[
      reviewsRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

class _FakeReviewsRepository implements ReviewsRepository {
  List<CustomerReview> listValue = <CustomerReview>[
    CustomerReview(
      id: 'rev-1',
      requestId: 'req-1',
      rating: 5,
      text: 'Excellent work',
      publicationStatus: 'APPROVED',
      createdAt: DateTime(2026, 1, 2),
    ),
  ];
  ApiFailure? listError;
  ApiFailure? createError;

  int listCalls = 0;
  int? createdRating;
  String? createdText;

  @override
  Future<List<CustomerReview>> reviews() async {
    listCalls++;
    final ApiFailure? failure = listError;
    if (failure != null) throw failure;
    return listValue;
  }

  @override
  Future<CustomerReview> create({
    required String requestId,
    required int rating,
    String? text,
    bool hasImage = false,
    String? idempotencyKey,
  }) async {
    createdRating = rating;
    createdText = text;
    final ApiFailure? failure = createError;
    if (failure != null) throw failure;
    return CustomerReview(
      id: 'rev-new',
      requestId: requestId,
      rating: rating,
      text: text,
      // Never approved on the way in: moderation is a staff decision.
      publicationStatus: 'PENDING',
      createdAt: DateTime(2026, 1, 3),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
