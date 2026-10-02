import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../core/network/json_readers.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../data/models/review_models.dart';

/// Moderation wording, mirroring the backend `ReviewStatus` enum.
String reviewModerationLabel(BuildContext context, String status) {
  final AppLocalizations l10n = context.l10n;
  return switch (status) {
    'APPROVED' => l10n.reviewModerationApproved,
    'HIDDEN' => l10n.reviewModerationHidden,
    'REJECTED' => l10n.reviewModerationRejected,
    _ => l10n.reviewModerationPending,
  };
}

/// The five-star row.
///
/// Tappable on the sheets, read-only where it labels an existing review, so the
/// same widget serves both without a mode flag that could be set wrong.
class StarRating extends StatelessWidget {
  const StarRating({
    required this.rating,
    this.onChanged,
    this.size = 28,
    super.key,
  });

  final int rating;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    if (onChanged == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int star = 1; star <= 5; star++)
            Icon(
              star <= rating ? Icons.star : Icons.star_border,
              size: size * 0.7,
              color: star <= rating ? colors.warning : colors.textSecondary,
            ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        for (int star = 1; star <= 5; star++)
          IconButton(
            key: Key('rating-star-$star'),
            onPressed: () => onChanged!(star),
            iconSize: size,
            // Highlighted up to the chosen star so the current score is visible
            // before submitting.
            color: star <= rating ? colors.warning : colors.textSecondary,
            icon: Icon(star <= rating ? Icons.star : Icons.star_border),
            tooltip: context.l10n.reviewStarsLabel(star),
          ),
      ],
    );
  }
}

/// One of the customer's own ratings.
class ReviewTile extends StatelessWidget {
  const ReviewTile({required this.review, super.key});

  final CustomerReview review;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: StarRating(rating: review.clampedRating)),
              const SizedBox(width: AppSpacing.xs),
              AppChip(
                label: reviewModerationLabel(context, review.publicationStatus),
                // A rating that is not public yet must not read as published.
                color: review.isPublic ? colors.success : colors.warning,
              ),
            ],
          ),
          if (review.hasText) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(review.text!, style: context.text.body),
          ],
          if (review.hasImage) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Icon(Icons.image, size: 16, color: colors.textSecondary),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  l10n.reviewsWrite,
                  style: context.text.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (review.createdAt != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              formatDate(review.createdAt),
              style: context.text.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
