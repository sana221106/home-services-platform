import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../data/models/photo_annotation.dart';

/// Full-screen editor for marking a problem area on a photo (§80).
///
/// Coordinates are captured relative to the displayed image box, which is a
/// [AspectRatio] of the decoded image, so the normalized geometry maps 1:1 onto
/// the stored image with no letterboxing maths. Pops with the mark list.
class PhotoAnnotationEditor extends StatefulWidget {
  const PhotoAnnotationEditor({
    required this.bytes,
    required this.initial,
    super.key,
  });

  final Uint8List bytes;
  final List<PhotoAnnotation> initial;

  @override
  State<PhotoAnnotationEditor> createState() => _PhotoAnnotationEditorState();
}

class _PhotoAnnotationEditorState extends State<PhotoAnnotationEditor> {
  PhotoAnnotationTool _tool = PhotoAnnotationTool.freehand;
  late final List<PhotoAnnotation> _annotations = <PhotoAnnotation>[
    ...widget.initial,
  ];

  List<Offset> _freehand = <Offset>[];
  Offset? _circleCenter;
  Offset? _circleEdge;

  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final ui.Codec codec = await ui.instantiateImageCodec(widget.bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final double ratio = frame.image.width / frame.image.height;
    frame.image.dispose();
    if (mounted) setState(() => _aspectRatio = ratio);
  }

  Offset _normalize(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void _start(Offset local, Size size) {
    final Offset point = _normalize(local, size);
    setState(() {
      if (_tool == PhotoAnnotationTool.freehand) {
        _freehand = <Offset>[point];
      } else {
        _circleCenter = point;
        _circleEdge = point;
      }
    });
  }

  void _update(Offset local, Size size) {
    final Offset point = _normalize(local, size);
    setState(() {
      if (_tool == PhotoAnnotationTool.freehand) {
        _freehand = <Offset>[..._freehand, point];
      } else {
        _circleEdge = point;
      }
    });
  }

  void _end(Size size) {
    setState(() {
      if (_tool == PhotoAnnotationTool.freehand) {
        if (_freehand.length >= 2) {
          _annotations.add(PhotoAnnotation.freehand(_freehand));
        }
        _freehand = <Offset>[];
      } else {
        final Offset? center = _circleCenter;
        final Offset? edge = _circleEdge;
        if (center != null && edge != null) {
          final double radius =
              (Offset(edge.dx - center.dx, edge.dy - center.dy)).distance /
              math.min(size.width, size.height);
          if (radius > 0.02) {
            _annotations.add(PhotoAnnotation.circle(center, radius));
          }
        }
        _circleCenter = null;
        _circleEdge = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppColors colors = AppColors.of(context);
    final double? ratio = _aspectRatio;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.requestsAnnotateTitle),
        actions: <Widget>[
          TextButton(
            key: const Key('annotate-done'),
            onPressed: () => Navigator.of(context).pop(_annotations),
            child: Text(
              l10n.requestsAnnotateDone,
              style: TextStyle(color: colors.primary),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              l10n.requestsAnnotateHint,
              style: context.text.caption.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ratio == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: AspectRatio(
                      aspectRatio: ratio,
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints c) {
                          final Size size = c.biggest;
                          return GestureDetector(
                            onPanStart: (DragStartDetails d) =>
                                _start(d.localPosition, size),
                            onPanUpdate: (DragUpdateDetails d) =>
                                _update(d.localPosition, size),
                            onPanEnd: (DragEndDetails _) => _end(size),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                Image.memory(widget.bytes, fit: BoxFit.fill),
                                CustomPaint(
                                  painter: _AnnotationPainter(
                                    annotations: _annotations,
                                    freehand: _freehand,
                                    circleCenter: _circleCenter,
                                    circleEdge: _circleEdge,
                                    color: colors.primary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _ToolButton(
                    label: l10n.requestsAnnotateFreehand,
                    icon: Icons.gesture,
                    selected: _tool == PhotoAnnotationTool.freehand,
                    onTap: () =>
                        setState(() => _tool = PhotoAnnotationTool.freehand),
                  ),
                  _ToolButton(
                    label: l10n.requestsAnnotateCircle,
                    icon: Icons.circle_outlined,
                    selected: _tool == PhotoAnnotationTool.circle,
                    onTap: () =>
                        setState(() => _tool = PhotoAnnotationTool.circle),
                  ),
                  _ToolButton(
                    label: l10n.requestsAnnotateUndo,
                    icon: Icons.undo,
                    selected: false,
                    onTap: _annotations.isEmpty
                        ? null
                        : () => setState(_annotations.removeLast),
                  ),
                  _ToolButton(
                    label: l10n.requestsAnnotateClear,
                    icon: Icons.delete_sweep_outlined,
                    selected: false,
                    onTap: _annotations.isEmpty
                        ? null
                        : () => setState(_annotations.clear),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = onTap == null
        ? Colors.white24
        : (selected ? AppColors.of(context).primary : Colors.white);
    return TextButton(
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter({
    required this.annotations,
    required this.freehand,
    required this.circleCenter,
    required this.circleEdge,
    required this.color,
  });

  final List<PhotoAnnotation> annotations;
  final List<Offset> freehand;
  final Offset? circleCenter;
  final Offset? circleEdge;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final PhotoAnnotation annotation in annotations) {
      _paintAnnotation(canvas, size, paint, annotation);
    }

    if (freehand.length >= 2) {
      _paintPath(canvas, size, paint, freehand);
    }
    if (circleCenter != null && circleEdge != null) {
      _paintCircle(canvas, size, paint, circleCenter!, circleEdge!);
    }
  }

  void _paintAnnotation(
    Canvas canvas,
    Size size,
    Paint paint,
    PhotoAnnotation annotation,
  ) {
    if (annotation.tool == PhotoAnnotationTool.freehand) {
      final List<dynamic> raw =
          (annotation.geometry['points'] as List<dynamic>?) ?? <dynamic>[];
      final List<Offset> points = <Offset>[
        for (final dynamic item in raw)
          Offset(
            (item as Map<String, dynamic>)['x'] as double,
            item['y'] as double,
          ),
      ];
      if (points.length >= 2) _paintPath(canvas, size, paint, points);
    } else {
      final double x = (annotation.geometry['x'] as num).toDouble();
      final double y = (annotation.geometry['y'] as num).toDouble();
      final double r = (annotation.geometry['r'] as num).toDouble();
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        r * math.min(size.width, size.height),
        paint,
      );
    }
  }

  void _paintPath(Canvas canvas, Size size, Paint paint, List<Offset> points) {
    final Path path = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (final Offset point in points.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  void _paintCircle(
    Canvas canvas,
    Size size,
    Paint paint,
    Offset center,
    Offset edge,
  ) {
    final double radius =
        (Offset(edge.dx - center.dx, edge.dy - center.dy)).distance *
        math.min(size.width, size.height);
    canvas.drawCircle(
      Offset(center.dx * size.width, center.dy * size.height),
      radius,
      paint,
    );
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) => true;
}
