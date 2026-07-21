import 'scanner_corners.dart';
import 'scanner_point.dart';

final class DetectionResult {
  DetectionResult({
    required List<ScannerPoint>? corners,
    required this.imageWidth,
    required this.imageHeight,
    required this.rotationDegrees,
    required this.mirrored,
    required this.source,
    this.confidence,
  }) : corners = corners == null ? null : ScannerCorners.validate(corners) {
    if (imageWidth <= 0 || imageHeight <= 0) {
      throw const FormatException('Image dimensions must be positive');
    }
    if (!<int>{0, 90, 180, 270}.contains(rotationDegrees)) {
      throw const FormatException('Rotation must be 0, 90, 180, or 270');
    }
  }

  final List<ScannerPoint>? corners;
  final int imageWidth;
  final int imageHeight;
  final int rotationDegrees;
  final bool mirrored;
  final String source;

  /// Null while the preserved legacy contour detector has no calibrated score.
  final double? confidence;

  bool get documentFound => corners != null;

  factory DetectionResult.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Detection result must be a map');
    }
    final Object? rawCorners = value['corners'];
    final Object? width = value['imageWidth'];
    final Object? height = value['imageHeight'];
    final Object? rotation = value['rotationDegrees'];
    if (width is! num || height is! num || rotation is! num) {
      throw const FormatException('Detection metadata is invalid');
    }
    return DetectionResult(
      corners: rawCorners == null
          ? null
          : (rawCorners as List<Object?>)
              .map(ScannerPoint.fromMap)
              .toList(growable: false),
      imageWidth: width.toInt(),
      imageHeight: height.toInt(),
      rotationDegrees: rotation.toInt(),
      mirrored: value['mirrored'] == true,
      source: value['source'] as String? ?? 'unknown',
      confidence: (value['confidence'] as num?)?.toDouble(),
    );
  }
}
