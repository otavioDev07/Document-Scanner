import 'package:flutter/painting.dart';

import '../models/scanner_point.dart';

/// Maps normalized source-image coordinates to a fitted Flutter viewport.
final class ScannerCoordinateMapper {
  ScannerCoordinateMapper({
    required this.sourceSize,
    required this.viewportSize,
    this.fit = BoxFit.contain,
    this.rotationDegrees = 0,
    this.mirrored = false,
  }) {
    if (sourceSize.isEmpty || viewportSize.isEmpty) {
      throw ArgumentError('Source and viewport sizes must be positive');
    }
    if (!<int>{0, 90, 180, 270}.contains(rotationDegrees)) {
      throw ArgumentError.value(rotationDegrees, 'rotationDegrees');
    }
  }

  final Size sourceSize;
  final Size viewportSize;
  final BoxFit fit;
  final int rotationDegrees;
  final bool mirrored;

  Size get orientedSourceSize => rotationDegrees == 90 || rotationDegrees == 270
      ? Size(sourceSize.height, sourceSize.width)
      : sourceSize;

  Rect get destinationRect {
    final FittedSizes sizes = applyBoxFit(
      fit,
      orientedSourceSize,
      viewportSize,
    );
    final Size fullImageSize = Size(
      orientedSourceSize.width * sizes.destination.width / sizes.source.width,
      orientedSourceSize.height *
          sizes.destination.height /
          sizes.source.height,
    );
    return Alignment.center.inscribe(fullImageSize, Offset.zero & viewportSize);
  }

  Offset toViewport(ScannerPoint sourcePoint) {
    ScannerPoint oriented = _rotateForward(sourcePoint);
    if (mirrored) oriented = ScannerPoint(1 - oriented.x, oriented.y);
    final Rect destination = destinationRect;
    return Offset(
      destination.left + oriented.x * destination.width,
      destination.top + oriented.y * destination.height,
    );
  }

  ScannerPoint fromViewport(Offset viewportPoint, {bool clamp = true}) {
    final Rect destination = destinationRect;
    ScannerPoint oriented = ScannerPoint(
      (viewportPoint.dx - destination.left) / destination.width,
      (viewportPoint.dy - destination.top) / destination.height,
    );
    if (clamp) oriented = oriented.clamped();
    if (mirrored) oriented = ScannerPoint(1 - oriented.x, oriented.y);
    final ScannerPoint source = _rotateInverse(oriented);
    return clamp ? source.clamped() : source;
  }

  ScannerPoint _rotateForward(ScannerPoint point) => switch (rotationDegrees) {
        90 => ScannerPoint(1 - point.y, point.x),
        180 => ScannerPoint(1 - point.x, 1 - point.y),
        270 => ScannerPoint(point.y, 1 - point.x),
        _ => point,
      };

  ScannerPoint _rotateInverse(ScannerPoint point) => switch (rotationDegrees) {
        90 => ScannerPoint(point.y, 1 - point.x),
        180 => ScannerPoint(1 - point.x, 1 - point.y),
        270 => ScannerPoint(1 - point.y, point.x),
        _ => point,
      };
}
