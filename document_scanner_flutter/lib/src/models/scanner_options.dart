final class ScannerOptions {
  const ScannerOptions({
    this.detectionResizeThreshold = 1200,
    this.areaScaleMinFactor = 0.04,
    this.maxOutputDimension = 4096,
    this.jpegQuality = 92,
    this.autoCapture = false,
    this.previewResizeThreshold = 200,
    this.previewAreaScaleMinFactor = 0.04,
    this.autoCaptureDistanceThreshold = 50,
    this.autoCaptureDelayMs = 1000,
    this.autoCaptureDurationMs = 1000,
    this.autoCaptureCooldownMs = 1500,
    this.diagnosticsEnabled = false,
  })  : assert(detectionResizeThreshold >= 0),
        assert(areaScaleMinFactor >= 0 && areaScaleMinFactor <= 1),
        assert(maxOutputDimension > 0),
        assert(jpegQuality >= 1 && jpegQuality <= 100),
        assert(previewResizeThreshold >= 0),
        assert(
            previewAreaScaleMinFactor >= 0 && previewAreaScaleMinFactor <= 1),
        assert(autoCaptureDistanceThreshold >= 0),
        assert(autoCaptureDelayMs >= 0),
        assert(autoCaptureDurationMs > 0),
        assert(autoCaptureCooldownMs >= 0);

  final int detectionResizeThreshold;
  final double areaScaleMinFactor;
  final int maxOutputDimension;
  final int jpegQuality;

  final bool autoCapture;
  final int previewResizeThreshold;
  final double previewAreaScaleMinFactor;

  /// Maximum movement of any corner in oriented analysis-image pixels.
  final double autoCaptureDistanceThreshold;
  final int autoCaptureDelayMs;
  final int autoCaptureDurationMs;
  final int autoCaptureCooldownMs;
  final bool diagnosticsEnabled;

  Map<String, Object> toMap() => <String, Object>{
        'detectionResizeThreshold': detectionResizeThreshold,
        'areaScaleMinFactor': areaScaleMinFactor,
        'maxOutputDimension': maxOutputDimension,
        'jpegQuality': jpegQuality,
        'autoCapture': autoCapture,
        'previewResizeThreshold': previewResizeThreshold,
        'previewAreaScaleMinFactor': previewAreaScaleMinFactor,
        'autoCaptureDistanceThreshold': autoCaptureDistanceThreshold,
        'autoCaptureDelayMs': autoCaptureDelayMs,
        'autoCaptureDurationMs': autoCaptureDurationMs,
        'autoCaptureCooldownMs': autoCaptureCooldownMs,
        'diagnosticsEnabled': diagnosticsEnabled,
      };
}
