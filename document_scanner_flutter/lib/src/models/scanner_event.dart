import 'capture_result.dart';
import 'camera_preview_info.dart';
import 'detection_result.dart';
import 'scanner_diagnostics.dart';

enum ScannerDetectionState {
  searching,
  detected,
  stabilizing,
  stable,
  capturing,
  processing,
  lost,
  error,
}

enum ScannerEventType {
  cameraState,
  documentDetected,
  documentLost,
  documentBlurred,
  documentBlurCleared,
  stabilityChanged,
  autoCaptureProgress,
  captureStarted,
  captureCompleted,
  processingStarted,
  processingCompleted,
  diagnostics,
  error,
}

final class ScannerEvent {
  const ScannerEvent({
    required this.type,
    required this.state,
    required this.timestampMicros,
    this.detection,
    this.capture,
    this.previewInfo,
    this.stability = 0,
    this.stableFrames = 0,
    this.diagnostics,
    this.errorCode,
    this.errorMessage,
    this.automatic = false,
    this.documentBlurred = false,
  });

  final ScannerEventType type;
  final ScannerDetectionState state;
  final int timestampMicros;
  final DetectionResult? detection;
  final CaptureResult? capture;
  final CameraPreviewInfo? previewInfo;
  final double stability;
  final int stableFrames;
  final ScannerDiagnostics? diagnostics;
  final String? errorCode;
  final String? errorMessage;
  final bool automatic;
  /// True only while a detected quadrilateral is rejected by the FFT blur gate.
  final bool documentBlurred;

  factory ScannerEvent.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Scanner event must be a map');
    }
    final ScannerEventType type = _eventType(value['event']);
    final ScannerDetectionState state = _detectionState(value['state']);
    final Object? rawCorners = value['corners'];
    final DetectionResult? detection = rawCorners == null
        ? null
        : DetectionResult.fromMap(<Object?, Object?>{
            'corners': rawCorners,
            'imageWidth': value['imageWidth'],
            'imageHeight': value['imageHeight'],
            'rotationDegrees': value['rotationDegrees'] ?? 0,
            'mirrored': value['mirrored'] ?? false,
            'source': value['source'] ?? 'camera_contour_detector',
            'confidence': value['confidence'],
          });
    final Object? rawCapture = value['capture'];
    final Object? rawPreview = value['preview'];
    final Object? rawDiagnostics = value['diagnostics'];
    return ScannerEvent(
      type: type,
      state: state,
      timestampMicros: (value['timestampMicros'] as num?)?.toInt() ?? 0,
      detection: detection,
      capture: rawCapture == null ? null : CaptureResult.fromMap(rawCapture),
      previewInfo:
          rawPreview == null ? null : CameraPreviewInfo.fromMap(rawPreview),
      stability: ((value['stability'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 1.0)
          .toDouble(),
      stableFrames: (value['stableFrames'] as num?)?.toInt() ?? 0,
      diagnostics: rawDiagnostics == null
          ? null
          : ScannerDiagnostics.fromMap(rawDiagnostics),
      errorCode: value['code'] as String?,
      errorMessage: value['message'] as String?,
      automatic: value['automatic'] == true,
      documentBlurred: value['documentBlurred'] == true,
    );
  }

  static ScannerEventType _eventType(Object? value) {
    final String name = value as String? ?? 'error';
    return ScannerEventType.values.firstWhere(
      (ScannerEventType item) => item.name == name,
      orElse: () => ScannerEventType.error,
    );
  }

  static ScannerDetectionState _detectionState(Object? value) {
    final String name = value as String? ?? 'searching';
    return ScannerDetectionState.values.firstWhere(
      (ScannerDetectionState item) => item.name == name,
      orElse: () => ScannerDetectionState.error,
    );
  }
}
