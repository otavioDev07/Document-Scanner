import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orders corners as TL, TR, BR, BL and rejects invalid shapes', () {
    const ScannerPoint tl = ScannerPoint(.1, .1);
    const ScannerPoint tr = ScannerPoint(.9, .1);
    const ScannerPoint br = ScannerPoint(.9, .9);
    const ScannerPoint bl = ScannerPoint(.1, .9);
    expect(ScannerCorners.order(<ScannerPoint>[br, tl, bl, tr]), <ScannerPoint>[
      tl,
      tr,
      br,
      bl,
    ]);
    expect(
      () => ScannerCorners.validate(const <ScannerPoint>[tl, br, tr, bl]),
      throwsFormatException,
    );
    expect(
      () => ScannerPoint.fromMap(<String, double>{'x': 2, 'y': 0}),
      throwsFormatException,
    );
  });

  for (final int rotation in <int>[0, 90, 180, 270]) {
    test('coordinate mapping round-trips at $rotation degrees with mirror', () {
      final ScannerCoordinateMapper mapper = ScannerCoordinateMapper(
        sourceSize: const Size(400, 200),
        viewportSize: const Size(300, 500),
        rotationDegrees: rotation,
        mirrored: true,
        fit: BoxFit.contain,
      );
      const ScannerPoint point = ScannerPoint(.2, .7);
      final ScannerPoint restored = mapper.fromViewport(
        mapper.toViewport(point),
        clamp: false,
      );
      expect(restored.x, closeTo(point.x, 1e-9));
      expect(restored.y, closeTo(point.y, 1e-9));
    });
  }

  test('contain letterboxes while cover crops around the same center', () {
    final ScannerCoordinateMapper contain = ScannerCoordinateMapper(
      sourceSize: const Size(400, 200),
      viewportSize: const Size(200, 200),
    );
    final ScannerCoordinateMapper cover = ScannerCoordinateMapper(
      sourceSize: const Size(400, 200),
      viewportSize: const Size(200, 200),
      fit: BoxFit.cover,
    );
    expect(contain.destinationRect, const Rect.fromLTWH(0, 50, 200, 100));
    expect(cover.destinationRect, const Rect.fromLTWH(-100, 0, 400, 200));
    expect(
      contain.toViewport(const ScannerPoint(.5, .5)),
      const Offset(100, 100),
    );
    expect(
      cover.toViewport(const ScannerPoint(.5, .5)),
      const Offset(100, 100),
    );
  });

  test('camera event parses normalized corners, preview, and diagnostics', () {
    final ScannerEvent event = ScannerEvent.fromMap(<String, Object>{
      'event': 'documentDetected',
      'state': 'stabilizing',
      'timestampMicros': 123,
      'corners': <Map<String, double>>[
        <String, double>{'x': .1, 'y': .1},
        <String, double>{'x': .9, 'y': .1},
        <String, double>{'x': .9, 'y': .9},
        <String, double>{'x': .1, 'y': .9},
      ],
      'imageWidth': 720,
      'imageHeight': 1280,
      'rotationDegrees': 0,
      'mirrored': false,
      'stability': .6,
      'stableFrames': 8,
      'preview': <String, Object>{
        'textureId': 3,
        'width': 1280,
        'height': 720,
        'rotationDegrees': 90,
        'mirrored': false,
      },
      'diagnostics': <String, Object>{
        'framesReceived': 12,
        'framesProcessed': 10,
        'framesDropped': 2,
        'candidatesFound': 7,
        'cameraFps': 30.0,
        'analysisFps': 14.0,
        'averageProcessingTimeMs': 21.5,
        'backpressureStrategy': 'KEEP_ONLY_LATEST',
      },
    });

    expect(event.type, ScannerEventType.documentDetected);
    expect(event.state, ScannerDetectionState.stabilizing);
    expect(event.detection!.corners!.length, 4);
    expect(event.stability, .6);
    expect(event.previewInfo!.orientedWidth, 720);
    expect(event.diagnostics!.framesDropped, 2);
  });
}
