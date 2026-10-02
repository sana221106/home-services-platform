import 'package:equatable/equatable.dart';

import '../../../../core/network/json_readers.dart';

/// A rating the customer left, from `GET /reviews`.
///
/// `publicationStatus` is the moderation state, not the star count: the customer
/// needs to know that a five-star review may not be public yet.
class CustomerReview extends Equatable {
  const CustomerReview({
    required this.id,
    required this.requestId,
    required this.rating,
    required this.publicationStatus,
    required this.createdAt,
    this.text,
    this.imageUrl,
  });

  factory CustomerReview.fromJson(Map<String, dynamic> json) {
    return CustomerReview(
      id: json.strOr('id', ''),
      requestId: json.strOr('request_id', ''),
      rating: json.intOr('rating', 0),
      text: json.str('text'),
      publicationStatus: json.strOr('publication_status', 'PENDING'),
      imageUrl: json.str('image_url'),
      createdAt: json.time('created_at'),
    );
  }

  final String id;
  final String requestId;
  final int rating;
  final String? text;
  final String publicationStatus;
  final String? imageUrl;
  final DateTime? createdAt;

  bool get hasText => text != null && text!.isNotEmpty;

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  bool get isPublic => publicationStatus == 'APPROVED';

  /// The backend bounds a rating to 1..5; anything else is clamped so the stars
  /// render rather than throwing on a bad payload.
  int get clampedRating => rating.clamp(1, 5);

  @override
  List<Object?> get props => <Object?>[
    id,
    requestId,
    rating,
    text,
    publicationStatus,
    imageUrl,
    createdAt,
  ];
}
