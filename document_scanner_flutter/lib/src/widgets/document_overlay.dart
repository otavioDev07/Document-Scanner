import 'package:flutter/material.dart';

import '../geometry/scanner_coordinate_mapper.dart';
import '../models/scanner_point.dart';

class DocumentOverlay extends StatefulWidget {
  const DocumentOverlay({
    required this.corners,
    required this.sourceSize,
    super.key,
    this.fit = BoxFit.contain,
    this.rotationDegrees = 0,
    this.mirrored = false,
    this.onCornersChanged,
    this.borderColor = const Color(0xFF00D4A6),
    this.scrimColor = const Color(0x66000000),
    this.handleRadius = 11,
  });

  final List<ScannerPoint> corners;
  final Size sourceSize;
  final BoxFit fit;
  final int rotationDegrees;
  final bool mirrored;
  final ValueChanged<List<ScannerPoint>>? onCornersChanged;
  final Color borderColor;
  final Color scrimColor;
  final double handleRadius;

  @override
  State<DocumentOverlay> createState() => _DocumentOverlayState();
}

class _DocumentOverlayState extends State<DocumentOverlay> {
  int? _activeCorner;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size viewport = constraints.biggest;
          final ScannerCoordinateMapper mapper = ScannerCoordinateMapper(
            sourceSize: widget.sourceSize,
            viewportSize: viewport,
            fit: widget.fit,
            rotationDegrees: widget.rotationDegrees,
            mirrored: widget.mirrored,
          );
          final List<Offset> offsets =
              widget.corners.map(mapper.toViewport).toList(growable: false);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.onCornersChanged == null
                ? null
                : (DragStartDetails details) {
                    double bestDistance = double.infinity;
                    int? bestIndex;
                    for (int index = 0; index < offsets.length; index++) {
                      final double distance =
                          (offsets[index] - details.localPosition).distance;
                      if (distance < bestDistance) {
                        bestDistance = distance;
                        bestIndex = index;
                      }
                    }
                    if (bestDistance <= widget.handleRadius * 3) {
                      _activeCorner = bestIndex;
                    }
                  },
            onPanUpdate: widget.onCornersChanged == null
                ? null
                : (DragUpdateDetails details) {
                    final int? index = _activeCorner;
                    if (index == null) return;
                    final List<ScannerPoint> updated = List<ScannerPoint>.of(
                      widget.corners,
                    );
                    updated[index] = mapper.fromViewport(details.localPosition);
                    widget.onCornersChanged!(
                      List<ScannerPoint>.unmodifiable(updated),
                    );
                  },
            onPanEnd: (_) => _activeCorner = null,
            onPanCancel: () => _activeCorner = null,
            child: CustomPaint(
              painter: _DocumentOverlayPainter(
                corners: offsets,
                borderColor: widget.borderColor,
                scrimColor: widget.scrimColor,
                handleRadius: widget.handleRadius,
              ),
              size: viewport,
            ),
          );
        },
      );
}

class _DocumentOverlayPainter extends CustomPainter {
  const _DocumentOverlayPainter({
    required this.corners,
    required this.borderColor,
    required this.scrimColor,
    required this.handleRadius,
  });

  final List<Offset> corners;
  final Color borderColor;
  final Color scrimColor;
  final double handleRadius;

  Path get _documentPath => Path()
    ..moveTo(corners[0].dx, corners[0].dy)
    ..lineTo(corners[1].dx, corners[1].dy)
    ..lineTo(corners[2].dx, corners[2].dy)
    ..lineTo(corners[3].dx, corners[3].dy)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final Path document = _documentPath;
    final Path outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      document,
    );
    canvas.drawPath(outside, Paint()..color = scrimColor);
    canvas.drawPath(
      document,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (final Offset corner in corners) {
      canvas.drawCircle(corner, handleRadius, Paint()..color = Colors.white);
      canvas.drawCircle(
        corner,
        handleRadius,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_DocumentOverlayPainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.scrimColor != scrimColor ||
      oldDelegate.handleRadius != handleRadius;
}
