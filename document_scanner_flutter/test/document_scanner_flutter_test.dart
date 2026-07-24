import 'dart:async';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:document_scanner_flutter/document_scanner_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeScannerPlatform extends DocumentScannerFlutterPlatform {
  bool disposed = false;
  int initializeCalls = 0;
  Completer<NativeStatus>? initializationGate;
  final StreamController<ScannerEvent> eventController =
      StreamController<ScannerEvent>.broadcast();

  static const NativeStatus status = NativeStatus(
    platform: 'test',
    pluginVersion: '0.2.0',
    opencvVersion: 'test',
    detectorAvailable: true,
    staticImageSupported: true,
    cameraPreviewSupported: true,
  );

  @override
  Stream<ScannerEvent> get events => eventController.stream;

  @override
  Future<NativeStatus> getNativeStatus() async => status;

  @override
  Future<NativeStatus> initialize() async {
    initializeCalls++;
    final Completer<NativeStatus>? gate = initializationGate;
    if (gate != null) return gate.future;
    return status;
  }

  @override
  Future<CaptureResult?> pickImage() async =>
      const CaptureResult(path: '/tmp/input.jpg');

  @override
  Future<DetectionResult> detectDocument(
    String imagePath,
    ScannerOptions options,
  ) async =>
      DetectionResult(
        corners: const <ScannerPoint>[
          ScannerPoint(.1, .1),
          ScannerPoint(.9, .1),
          ScannerPoint(.9, .9),
          ScannerPoint(.1, .9),
        ],
        imageWidth: 1000,
        imageHeight: 800,
        rotationDegrees: 0,
        mirrored: false,
        source: 'fake',
      );

  @override
  Future<CropResult> cropDocument(
    String imagePath,
    List<ScannerPoint> corners,
    ScannerOptions options,
  ) async =>
      const CropResult(path: '/tmp/crop.jpg', width: 800, height: 600);

  @override
  Future<CropResult> applyFilter(
    String imagePath,
    String outputPath,
    String filter, {
    int jpegQuality = 92,
  }) async =>
      CropResult(path: outputPath, width: 800, height: 600);

  @override
  Future<OcrResult> recognizeText(
    String imagePath, {
    List<String> languages = const <String>[],
  }) async =>
      OcrResult(
        text: 'Invoice 123',
        blocks: const <OcrTextBlock>[],
        languages: languages,
        durationMilliseconds: 12,
      );

  @override
  Future<CameraPreviewInfo> startPreview(ScannerOptions options) async =>
      const CameraPreviewInfo(
        textureId: 7,
        width: 1280,
        height: 720,
        rotationDegrees: 90,
        mirrored: false,
      );

  @override
  Future<void> stopPreview() async {}

  @override
  Future<void> pausePreview() async {}

  @override
  Future<CameraPreviewInfo> resumePreview() =>
      startPreview(const ScannerOptions());

  @override
  Future<CameraPreviewInfo> switchCamera() async => const CameraPreviewInfo(
        textureId: 7,
        width: 1280,
        height: 720,
        rotationDegrees: 90,
        mirrored: true,
      );

  @override
  Future<void> setFlashMode(ScannerFlashMode mode) async {}

  @override
  Future<void> setAutoCapture(bool enabled) async {}

  @override
  Future<CaptureResult> capture() async =>
      const CaptureResult(path: '/tmp/camera.jpg');

  @override
  Future<ScannerDiagnostics> getDiagnostics() async => const ScannerDiagnostics(
        framesReceived: 10,
        framesProcessed: 8,
        framesDropped: 2,
        candidatesFound: 4,
        cameraFps: 30,
        analysisFps: 12,
        averageProcessingTimeMs: 22,
        backpressureStrategy: 'KEEP_ONLY_LATEST',
      );

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  test('operations join an initialization already in progress', () async {
    final FakeScannerPlatform platform = FakeScannerPlatform();
    final Completer<NativeStatus> gate = Completer<NativeStatus>();
    platform.initializationGate = gate;
    final DocumentScannerController controller = DocumentScannerController(
      platform: platform,
    );

    final Future<NativeStatus> initialization = controller.initialize();
    final Future<DetectionResult> detection = controller.detectDocument(
      '/tmp/input.jpg',
    );
    expect(controller.state, ScannerCameraState.initializing);
    expect(platform.initializeCalls, 1);

    gate.complete(FakeScannerPlatform.status);
    await initialization;
    expect((await detection).documentFound, isTrue);
    expect(platform.initializeCalls, 1);
    await controller.close();
  });

  test(
    'controller initializes lazily, detects, crops, and closes safely',
    () async {
      final FakeScannerPlatform platform = FakeScannerPlatform();
      final DocumentScannerController controller = DocumentScannerController(
        platform: platform,
      );

      final DetectionResult detection = await controller.detectDocument(
        '/tmp/input.jpg',
      );
      expect(platform.initializeCalls, 1);
      expect(controller.state, ScannerCameraState.ready);
      expect(detection.documentFound, isTrue);

      final CropResult crop = await controller.cropDocument('/tmp/input.jpg');
      expect(crop.width, 800);
      final CropResult filtered = await controller.applyFilter(
        '/tmp/crop.jpg',
        '/tmp/filtered.jpg',
        'grayscale',
      );
      expect(filtered.path, '/tmp/filtered.jpg');
      final OcrResult ocr = await controller.recognizeText(
        '/tmp/crop.jpg',
        languages: const <String>['en-US'],
      );
      expect(ocr.text, 'Invoice 123');
      expect(ocr.languages, <String>['en-US']);
      await controller.close();
      expect(platform.disposed, isTrue);
      expect(controller.isDisposed, isTrue);
      expect(
        () => controller.getNativeStatus(),
        throwsA(isA<ScannerException>()),
      );
    },
  );

  test('camera lifecycle exposes Texture metadata and capture', () async {
    final DocumentScannerController controller = DocumentScannerController(
      platform: FakeScannerPlatform(),
    );
    final CameraPreviewInfo preview = await controller.startPreview();
    expect(preview.textureId, 7);
    expect(preview.orientedWidth, 720);
    expect(controller.state, ScannerCameraState.previewing);
    final CaptureResult capture = await controller.capture();
    expect(capture.path, '/tmp/camera.jpg');
    expect(controller.state, ScannerCameraState.previewing);
    await controller.pausePreview();
    expect(controller.state, ScannerCameraState.paused);
    await controller.resumePreview();
    await controller.stopPreview();
    expect(controller.state, ScannerCameraState.ready);
    await controller.close();
  });

  test('controller converts invalid crop geometry to a typed error', () async {
    final DocumentScannerController controller = DocumentScannerController(
      platform: FakeScannerPlatform(),
    );
    await expectLater(
      controller.cropDocument(
        '/tmp/input.jpg',
        corners: const <ScannerPoint>[
          ScannerPoint(.1, .1),
          ScannerPoint(.9, .9),
          ScannerPoint(.9, .1),
          ScannerPoint(.1, .9),
        ],
      ),
      throwsA(
        isA<ScannerException>().having(
          (ScannerException e) => e.code,
          'code',
          'INVALID_ARGUMENT',
        ),
      ),
    );
    controller.dispose();
  });
}
