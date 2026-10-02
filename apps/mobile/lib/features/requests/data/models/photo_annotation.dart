import 'dart:ui' show Offset;

import 'package:equatable/equatable.dart';

/// How a mark is interpreted by the backend (`AnnotationType`, §80).
enum PhotoAnnotationTool { freehand, circle }

/// A mark drawn over a photo, stored as normalized geometry.
///
/// Coordinates are 0..1 relative to the stored image, so a mark survives any
/// display size. This mirrors the backend `AnnotationPayload`: it validates
/// `geometry.x`/`geometry.y` are within [0, 1] and stores the rest verbatim.
class PhotoAnnotation extends Equatable {
  const PhotoAnnotation({
    required this.tool,
    required this.geometry,
    this.note,
  });

  factory PhotoAnnotation.freehand(List<Offset> points, {String? note}) {
    return PhotoAnnotation(
      tool: PhotoAnnotationTool.freehand,
      geometry: <String, dynamic>{
        'points': <Map<String, double>>[
          for (final Offset point in points)
            <String, double>{'x': point.dx, 'y': point.dy},
        ],
      },
      note: note,
    );
  }

  /// [radius] is normalized against the image's shorter side so the mark stays
  /// a circle in pixels regardless of the photo's aspect ratio.
  factory PhotoAnnotation.circle(Offset center, double radius, {String? note}) {
    return PhotoAnnotation(
      tool: PhotoAnnotationTool.circle,
      geometry: <String, dynamic>{'x': center.dx, 'y': center.dy, 'r': radius},
      note: note,
    );
  }

  final PhotoAnnotationTool tool;
  final Map<String, dynamic> geometry;
  final String? note;

  bool get isEmpty => tool == PhotoAnnotationTool.freehand
      ? (geometry['points'] as List<dynamic>?)?.length != 2
      : false;

  String get type => switch (tool) {
    PhotoAnnotationTool.freehand => 'freehand',
    PhotoAnnotationTool.circle => 'circle',
  };

  Map<String, dynamic> toPayload() => <String, dynamic>{
    'annotation_type': type,
    'geometry': geometry,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
  };

  @override
  List<Object?> get props => <Object?>[tool, geometry, note];
}
