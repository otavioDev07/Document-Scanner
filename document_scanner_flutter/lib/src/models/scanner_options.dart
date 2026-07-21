final class ScannerOptions {
  const ScannerOptions({
    this.detectionResizeThreshold = 1200,
    this.areaScaleMinFactor = 0.04,
    this.maxOutputDimension = 4096,
    this.jpegQuality = 92,
    this.autoCapture = false,
  })  : assert(detectionResizeThreshold >= 0),
        assert(areaScaleMinFactor >= 0 && areaScaleMinFactor <= 1),
        assert(maxOutputDimension > 0),
        assert(jpegQuality >= 1 && jpegQuality <= 100);

  final int detectionResizeThreshold;
  final double areaScaleMinFactor;
  final int maxOutputDimension;
  final int jpegQuality;

  /// Reserved for the camera phase; it is not acted on in the static-image phase.
  final bool autoCapture;

  Map<String, Object> toMap() => <String, Object>{
        'detectionResizeThreshold': detectionResizeThreshold,
        'areaScaleMinFactor': areaScaleMinFactor,
        'maxOutputDimension': maxOutputDimension,
        'jpegQuality': jpegQuality,
        'autoCapture': autoCapture,
      };
}
