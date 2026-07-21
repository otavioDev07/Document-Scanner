final class ScannerDiagnostics {
  const ScannerDiagnostics({
    required this.framesReceived,
    required this.framesProcessed,
    required this.framesDropped,
    required this.candidatesFound,
    required this.cameraFps,
    required this.analysisFps,
    required this.averageProcessingTimeMs,
    required this.backpressureStrategy,
  });

  final int framesReceived;
  final int framesProcessed;

  /// Estimated from camera timestamps because CameraX drops frames internally.
  final int framesDropped;
  final int candidatesFound;
  final double cameraFps;
  final double analysisFps;
  final double averageProcessingTimeMs;
  final String backpressureStrategy;

  factory ScannerDiagnostics.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Scanner diagnostics must be a map');
    }
    return ScannerDiagnostics(
      framesReceived: _integer(value, 'framesReceived'),
      framesProcessed: _integer(value, 'framesProcessed'),
      framesDropped: _integer(value, 'framesDropped'),
      candidatesFound: _integer(value, 'candidatesFound'),
      cameraFps: _decimal(value, 'cameraFps'),
      analysisFps: _decimal(value, 'analysisFps'),
      averageProcessingTimeMs: _decimal(value, 'averageProcessingTimeMs'),
      backpressureStrategy:
          value['backpressureStrategy'] as String? ?? 'unknown',
    );
  }

  static int _integer(Map<dynamic, dynamic> map, String key) =>
      (map[key] as num?)?.toInt() ?? 0;
  static double _decimal(Map<dynamic, dynamic> map, String key) =>
      (map[key] as num?)?.toDouble() ?? 0;
}
