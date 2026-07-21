import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'document_scanner_flutter_method_channel.dart';
import 'src/models/capture_result.dart';
import 'src/models/crop_result.dart';
import 'src/models/detection_result.dart';
import 'src/models/native_status.dart';
import 'src/models/scanner_options.dart';
import 'src/models/scanner_point.dart';

abstract class DocumentScannerFlutterPlatform extends PlatformInterface {
  DocumentScannerFlutterPlatform() : super(token: _token);

  static final Object _token = Object();
  static DocumentScannerFlutterPlatform _instance =
      MethodChannelDocumentScannerFlutter();

  static DocumentScannerFlutterPlatform get instance => _instance;

  static set instance(DocumentScannerFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<NativeStatus> getNativeStatus();
  Future<NativeStatus> initialize();
  Future<CaptureResult?> pickImage();
  Future<DetectionResult> detectDocument(
    String imagePath,
    ScannerOptions options,
  );
  Future<CropResult> cropDocument(
    String imagePath,
    List<ScannerPoint> corners,
    ScannerOptions options,
  );
  Future<void> dispose();
}
