import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../controllers/reviews_controller.dart';
import '../../data/models/review_models.dart';
import '../widgets/review_widgets.dart';

/// Spec screen 18: the customer's own ratings.
///
/// Read-only on purpose. A submitted rating goes to moderation, so editing it
/// here would offer an action the backend does not support.
class ReviewsPage extends ConsumerStatefulWidget {
  const ReviewsPage({super.key});

  @override
  ConsumerState<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends ConsumerState<ReviewsPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => ref.read(reviewsProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ReviewsState state = ref.watch(reviewsProvider);

    return AppPageScaffold(
      title: l10n.reviewsTitle,
      onBack: () => Navigator.of(context).maybePop(),
      body: switch (state.status) {
        ReviewsStatus.initial || ReviewsStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        ReviewsStatus.failed => ErrorRetry(
          message: state.errorMessage ?? l10n.commonSomethingWentWrong,
          onRetry: () => ref.read(reviewsProvider.notifier).load(),
        ),
        ReviewsStatus.ready =>
          state.reviews.isEmpty
              ? EmptyState(
                  title: l10n.reviewNoneTitle,
                  body: l10n.reviewNoneBody,
                  icon: 'assets/icons/star.svg',
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(reviewsProvider.notifier).load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenHorizontal,
                      AppSpacing.md,
                      AppSpacing.screenHorizontal,
                      AppSpacing.xxl,
                    ),
                    itemCount: state.reviews.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (BuildContext context, int index) {
                      return ReviewTile(
                        key: Key('review-${state.reviews[index].id}'),
                        review: state.reviews[index],
                      );
                    },
                  ),
                ),
      },
    );
  }
}

/// The rating form.
///
/// Stars are mandatory and the comment is not, because that is the shape the
/// backend enforces: submitting is blocked until a score exists.
class RateServiceForm extends ConsumerStatefulWidget {
  const RateServiceForm({required this.requestId, super.key});

  final String requestId;

  @override
  ConsumerState<RateServiceForm> createState() => _RateServiceFormState();
}

class _RateServiceFormState extends ConsumerState<RateServiceForm> {
  final TextEditingController _comment = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Returns the created review, or null when the backend refused it. The host
  /// decides what to do with the result.
  Future<CustomerReview?> submit() async {
    if (_rating == 0) return null;
    return ref
        .read(reviewsProvider.notifier)
        .submit(
          requestId: widget.requestId,
          rating: _rating,
          text: _comment.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final ReviewsState state = ref.watch(reviewsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.reviewsRatingLabel, style: context.text.title),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: StarRating(
            rating: _rating,
            onChanged: (int value) => setState(() => _rating = value),
          ),
        ),

        const SizedBox(height: AppSpacing.md),
        Text(
          '${l10n.reviewCommentLabel} (${l10n.reviewCommentOptional})',
          style: context.text.labelStrong,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          key: const Key('review-comment'),
          controller: _comment,
          minLines: 3,
          maxLines: 6,
          // The backend allows 2000 characters; the counter stops the customer
          // hitting that ceiling blind.
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: l10n.reviewsCommentHint,
            border: const OutlineInputBorder(),
          ),
        ),

        if (state.errorMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            state.errorMessage!,
            style: context.text.caption.copyWith(color: colors.danger),
          ),
        ],

        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('review-submit'),
            onPressed: _rating == 0 || state.isSubmitting
                ? null
                : _submitAndPop,
            child: Text(l10n.reviewsSubmit),
          ),
        ),
      ],
    );
  }

  Future<void> _submitAndPop() async {
    final CustomerReview? review = await submit();
    if (review != null && mounted) Navigator.of(context).pop(review);
  }
}

/// The rating form as a bottom sheet, opened from the finished request.
class RateServiceSheet extends StatelessWidget {
  const RateServiceSheet({required this.requestId, super.key});

  final String requestId;

  /// Returns the created review, or null when dismissed or rejected.
  static Future<CustomerReview?> show(
    BuildContext context, {
    required String requestId,
  }) {
    return showModalBottomSheet<CustomerReview>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RateServiceSheet(requestId: requestId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: RateServiceForm(requestId: requestId),
      ),
    );
  }
}

/// The rating form as a full page, so the route can be opened directly.
class RateServicePage extends StatelessWidget {
  const RateServicePage({required this.requestId, super.key});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return AppPageScaffold(
      title: l10n.reviewsRatingLabel,
      onBack: () => Navigator.of(context).maybePop(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.md,
          AppSpacing.screenHorizontal,
          AppSpacing.xxl,
        ),
        children: <Widget>[RateServiceForm(requestId: requestId)],
      ),
    );
  }
}
