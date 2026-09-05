import 'scanner_point.dart';

final class CaptureResult {
  const CaptureResult({
    required this.path,
    this.mimeType,
    this.displayName,
    this.previewCorners,
  });

  final String path;
  final String? mimeType;
  final String? displayName;
  /// Stable preview corners frozen when the camera shutter was triggered.
  final List<ScannerPoint>? previewCorners;

  factory CaptureResult.fromMap(Object? value) {
    if (value is! Map ||
        value['path'] is! String ||
        (value['path'] as String).isEmpty) {
      throw const FormatException('Capture result has no valid path');
    }
    return CaptureResult(
      path: value['path'] as String,
      mimeType: value['mimeType'] as String?,
      displayName: value['displayName'] as String?,
      previewCorners: value['previewCorners'] is! List
          ? null
          : (value['previewCorners'] as List<Object?>)
              .map(ScannerPoint.fromMap)
              .toList(growable: false),
    );
  }
}
