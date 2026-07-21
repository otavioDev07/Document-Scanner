import 'dart:math' as math;

import 'scanner_point.dart';

/// Validation and ordering helpers for TL, TR, BR, BL corner lists.
abstract final class ScannerCorners {
  static const double _minimumArea = 0.0001;

  static List<ScannerPoint> validate(List<ScannerPoint> corners) {
    if (corners.length != 4) {
      throw const FormatException('Exactly four corners are required');
    }
    if (corners.any((ScannerPoint point) => !point.isNormalized)) {
      throw const FormatException('All corners must be normalized');
    }
    final double area = signedArea(corners).abs();
    if (area < _minimumArea) {
      throw const FormatException('Corners form a degenerate polygon');
    }

    double? sign;
    for (int index = 0; index < 4; index++) {
      final ScannerPoint a = corners[index];
      final ScannerPoint b = corners[(index + 1) % 4];
      final ScannerPoint c = corners[(index + 2) % 4];
      final double cross =
          (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-9) {
        throw const FormatException('Corners must be strictly convex');
      }
      sign ??= cross.sign;
      if (cross.sign != sign) {
        throw const FormatException('Corners must not self-intersect');
      }
    }
    return List<ScannerPoint>.unmodifiable(corners);
  }

  /// Orders arbitrary normalized corners as top-left, top-right, bottom-right, bottom-left.
  static List<ScannerPoint> order(Iterable<ScannerPoint> input) {
    final List<ScannerPoint> points = input.toList(growable: false);
    if (points.length != 4) {
      throw const FormatException('Exactly four corners are required');
    }
    final double centerX =
        points.fold(0.0, (double sum, ScannerPoint p) => sum + p.x) / 4;
    final double centerY =
        points.fold(0.0, (double sum, ScannerPoint p) => sum + p.y) / 4;
    final List<ScannerPoint> sorted = List<ScannerPoint>.of(points)
      ..sort((ScannerPoint a, ScannerPoint b) {
        final double angleA = math.atan2(a.y - centerY, a.x - centerX);
        final double angleB = math.atan2(b.y - centerY, b.x - centerX);
        return angleA.compareTo(angleB);
      });
    final int topLeftIndex = sorted.indexWhere(
      (ScannerPoint point) =>
          point ==
          sorted.reduce(
            (ScannerPoint a, ScannerPoint b) => a.x + a.y <= b.x + b.y ? a : b,
          ),
    );
    final List<ScannerPoint> rotated = <ScannerPoint>[
      ...sorted.skip(topLeftIndex),
      ...sorted.take(topLeftIndex),
    ];
    if (signedArea(rotated) < 0) {
      return validate(<ScannerPoint>[
        rotated[0],
        rotated[3],
        rotated[2],
        rotated[1],
      ]);
    }
    return validate(rotated);
  }

  static double signedArea(List<ScannerPoint> points) {
    double sum = 0;
    for (int index = 0; index < points.length; index++) {
      final ScannerPoint current = points[index];
      final ScannerPoint next = points[(index + 1) % points.length];
      sum += current.x * next.y - next.x * current.y;
    }
    return sum / 2;
  }
}
