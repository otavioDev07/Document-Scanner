import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:document_scanner_flutter/document_scanner_flutter_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelDocumentScannerFlutter platform =
      MethodChannelDocumentScannerFlutter();
  const MethodChannel channel = MethodChannel('document_scanner_flutter');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('parses native status and a no-document response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall call) async => switch (call.method) {
        'getNativeStatus' => <String, Object>{
            'platform': 'android',
            'pluginVersion': '0.1.0',
            'opencvVersion': '4.12.0',
            'detectorAvailable': true,
            'staticImageSupported': true,
            'cameraPreviewSupported': false,
          },
        'detectDocument' => <String, Object?>{
            'corners': null,
            'imageWidth': 640,
            'imageHeight': 480,
            'rotationDegrees': 0,
            'mirrored': false,
            'source': 'legacy_contour_detector',
            'confidence': null,
          },
        'applyFilter' => <String, Object>{
            'path': '/tmp/filtered.jpg',
            'width': 640,
            'height': 480,
          },
        'recognizeText' => <String, Object>{
            'text': 'Total 42.00',
            'blocks': <Object>[
              <String, Object>{
                'text': 'Total 42.00',
                'left': .1,
                'top': .2,
                'width': .4,
                'height': .1,
              },
            ],
            'languages': <String>['en'],
            'durationMilliseconds': 21,
          },
        _ => null,
      },
    );

    expect((await platform.getNativeStatus()).detectorAvailable, isTrue);
    final DetectionResult result = await platform.detectDocument(
      '/tmp/a.jpg',
      const ScannerOptions(),
    );
    expect(result.documentFound, isFalse);
    final CropResult filtered = await platform.applyFilter(
      '/tmp/a.jpg',
      '/tmp/filtered.jpg',
      'grayscale',
    );
    expect(filtered.width, 640);
    final OcrResult ocr = await platform.recognizeText('/tmp/a.jpg');
    expect(ocr.text, 'Total 42.00');
    expect(ocr.blocks.single.left, .1);
    expect(ocr.languages, <String>['en']);
  });

  test('turns malformed native payloads into typed exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (_) async => <String, Object>{
        'imageWidth': -1,
        'imageHeight': 10,
        'rotationDegrees': 0,
      },
    );
    await expectLater(
      platform.detectDocument('/tmp/a.jpg', const ScannerOptions()),
      throwsA(
        isA<ScannerException>().having(
          (ScannerException e) => e.code,
          'code',
          'INVALID_NATIVE_PAYLOAD',
        ),
      ),
    );
  });

  test('preserves native error codes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'FILE_NOT_FOUND',
        message: 'missing',
      ),
    );
    await expectLater(
      platform.detectDocument('/tmp/missing.jpg', const ScannerOptions()),
      throwsA(
        isA<ScannerException>().having(
          (ScannerException e) => e.code,
          'code',
          'FILE_NOT_FOUND',
        ),
      ),
    );
  });
}
