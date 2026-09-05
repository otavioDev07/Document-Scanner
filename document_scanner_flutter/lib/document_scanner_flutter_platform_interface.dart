import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'document_scanner_flutter_method_channel.dart';
import 'src/models/camera_preview_info.dart';
import 'src/models/capture_result.dart';
import 'src/models/crop_result.dart';
import 'src/models/detection_result.dart';
import 'src/models/native_status.dart';
import 'src/models/ocr_result.dart';
import 'src/models/scanner_options.dart';
import 'src/models/scanner_point.dart';
import 'src/models/scanner_camera_state.dart';
import 'src/models/scanner_diagnostics.dart';
import 'src/models/scanner_event.dart';

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

  /// Lets camera implementations validate the stable low-resolution candidate
  /// against the captured photo before falling back to a full image search.
  Future<DetectionResult> detectDocumentWithPreviewHint(
    String imagePath,
    ScannerOptions options, {
    List<ScannerPoint>? previewCorners,
  }) =>
      detectDocument(imagePath, options);
  Future<CropResult> cropDocument(
    String imagePath,
    List<ScannerPoint> corners,
    ScannerOptions options,
  );
  Future<CropResult> applyFilter(
    String imagePath,
    String outputPath,
    String filter, {
    int jpegQuality = 92,
  });
  Future<OcrResult> recognizeText(
    String imagePath, {
    List<String> languages = const <String>[],
  });
  Future<String> enqueueImageUpload(String imagePath, String destination) =>
      throw UnimplementedError(
          'Cloud upload is not available on this platform');
  Stream<ScannerEvent> get events;
  Future<CameraPreviewInfo> startPreview(ScannerOptions options);
  Future<void> stopPreview();
  Future<void> pausePreview();
  Future<CameraPreviewInfo> resumePreview();
  Future<CameraPreviewInfo> switchCamera();
  Future<void> setFlashMode(ScannerFlashMode mode);
  Future<void> setAutoCapture(bool enabled);
  Future<CaptureResult> capture();
  Future<ScannerDiagnostics> getDiagnostics();
  Future<void> dispose();
}
