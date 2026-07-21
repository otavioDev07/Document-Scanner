import 'dart:ui';

/// A normalized point where both axes are in the inclusive 0–1 range.
final class ScannerPoint {
  const ScannerPoint(this.x, this.y);

  final double x;
  final double y;

  bool get isNormalized =>
      x.isFinite && y.isFinite && x >= 0 && x <= 1 && y >= 0 && y <= 1;

  ScannerPoint clamped() => ScannerPoint(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

  Offset toOffset() => Offset(x, y);

  Map<String, double> toMap() => <String, double>{'x': x, 'y': y};

  factory ScannerPoint.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Point must be a map');
    }
    final Object? rawX = value['x'];
    final Object? rawY = value['y'];
    if (rawX is! num || rawY is! num) {
      throw const FormatException('Point x and y must be numbers');
    }
    final ScannerPoint point = ScannerPoint(rawX.toDouble(), rawY.toDouble());
    if (!point.isNormalized) {
      throw const FormatException('Point must be normalized');
    }
    return point;
  }

  @override
  bool operator ==(Object other) =>
      other is ScannerPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'ScannerPoint($x, $y)';
}
