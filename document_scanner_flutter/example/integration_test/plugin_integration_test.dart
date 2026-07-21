import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes and processes a bundled static image', (
    WidgetTester tester,
  ) async {
    final DocumentScannerController controller = DocumentScannerController();
    final NativeStatus status = await controller.initialize();
    expect(status.detectorAvailable, isTrue);
    expect(status.staticImageSupported, isTrue);
    expect(status.cameraPreviewSupported, Platform.isAndroid);

    final ByteData data = await rootBundle.load('assets/test-document.png');
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final File input = File(
      '${Directory.systemTemp.path}/document_scanner_fixture.png',
    );
    await input.writeAsBytes(bytes, flush: true);

    final DetectionResult detection = await controller.detectDocument(
      input.path,
    );
    expect(detection.imageWidth, greaterThan(0));
    expect(detection.imageHeight, greaterThan(0));
    if (detection.corners case final List<ScannerPoint> corners) {
      expect(corners, hasLength(4));
      final CropResult crop = await controller.cropDocument(
        input.path,
        corners: corners,
      );
      expect(await File(crop.path).exists(), isTrue);
      expect(crop.width, greaterThan(0));
      expect(crop.height, greaterThan(0));
    }
    await controller.close();
  });
}
