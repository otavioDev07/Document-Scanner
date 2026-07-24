import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'document_scanner_flutter_platform_interface.dart';
import 'src/models/camera_preview_info.dart';
import 'src/models/capture_result.dart';
import 'src/models/crop_result.dart';
import 'src/models/detection_result.dart';
import 'src/models/native_status.dart';
import 'src/models/ocr_result.dart';
import 'src/models/scanner_exception.dart';
import 'src/models/scanner_camera_state.dart';
import 'src/models/scanner_diagnostics.dart';
import 'src/models/scanner_event.dart';
import 'src/models/scanner_options.dart';
import 'src/models/scanner_point.dart';

class MethodChannelDocumentScannerFlutter
    extends DocumentScannerFlutterPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'document_scanner_flutter',
  );

  @visibleForTesting
  final EventChannel eventChannel = const EventChannel(
    'document_scanner_flutter/events',
  );

  Stream<ScannerEvent>? _events;

  @override
  Stream<ScannerEvent> get events => _events ??= eventChannel
          .receiveBroadcastStream()
          .map<ScannerEvent>((Object? value) {
        try {
          return ScannerEvent.fromMap(value);
        } on FormatException catch (error) {
          throw ScannerException(
            'INVALID_NATIVE_PAYLOAD',
            error.message,
            error.source,
          );
        }
      });

  @override
  Future<NativeStatus> getNativeStatus() =>
      _invoke('getNativeStatus', parser: NativeStatus.fromMap);

  @override
  Future<NativeStatus> initialize() =>
      _invoke('initialize', parser: NativeStatus.fromMap);

  @override
  Future<CaptureResult?> pickImage() => _invoke(
        'pickImage',
        parser: (Object? value) =>
            value == null ? null : CaptureResult.fromMap(value),
      );

  @override
  Future<DetectionResult> detectDocument(
    String imagePath,
    ScannerOptions options,
  ) =>
      _invoke(
        'detectDocument',
        arguments: <String, Object>{
          'imagePath': imagePath,
          'options': options.toMap(),
        },
        parser: DetectionResult.fromMap,
      );

  @override
  Future<CropResult> cropDocument(
    String imagePath,
    List<ScannerPoint> corners,
    ScannerOptions options,
  ) =>
      _invoke(
        'cropDocument',
        arguments: <String, Object>{
          'imagePath': imagePath,
          'corners': corners
              .map((ScannerPoint point) => point.toMap())
              .toList(growable: false),
          'options': options.toMap(),
        },
        parser: CropResult.fromMap,
      );

  @override
  Future<CropResult> applyFilter(
    String imagePath,
    String outputPath,
    String filter, {
    int jpegQuality = 92,
  }) =>
      _invoke(
        'applyFilter',
        arguments: <String, Object>{
          'imagePath': imagePath,
          'outputPath': outputPath,
          'filter': filter,
          'outputFormat':
              imagePath.toLowerCase().endsWith('.png') ? 'png' : 'jpeg',
          'jpegQuality': jpegQuality,
        },
        parser: CropResult.fromMap,
      );

  @override
  Future<OcrResult> recognizeText(
    String imagePath, {
    List<String> languages = const <String>[],
  }) =>
      _invoke(
        'recognizeText',
        arguments: <String, Object>{
          'imagePath': imagePath,
          'languages': languages,
        },
        parser: OcrResult.fromMap,
      );

  @override
  Future<CameraPreviewInfo> startPreview(ScannerOptions options) => _invoke(
        'startPreview',
        arguments: <String, Object>{'options': options.toMap()},
        parser: CameraPreviewInfo.fromMap,
      );

  @override
  Future<void> stopPreview() => _invoke<void>('stopPreview', parser: (_) {});

  @override
  Future<void> pausePreview() => _invoke<void>('pausePreview', parser: (_) {});

  @override
  Future<CameraPreviewInfo> resumePreview() =>
      _invoke('resumePreview', parser: CameraPreviewInfo.fromMap);

  @override
  Future<CameraPreviewInfo> switchCamera() =>
      _invoke('switchCamera', parser: CameraPreviewInfo.fromMap);

  @override
  Future<void> setFlashMode(ScannerFlashMode mode) => _invoke<void>(
        'setFlash',
        arguments: <String, Object>{'mode': mode.name},
        parser: (_) {},
      );

  @override
  Future<void> setAutoCapture(bool enabled) => _invoke<void>(
        'setAutoCapture',
        arguments: <String, Object>{'enabled': enabled},
        parser: (_) {},
      );

  @override
  Future<CaptureResult> capture() =>
      _invoke('capture', parser: CaptureResult.fromMap);

  @override
  Future<ScannerDiagnostics> getDiagnostics() =>
      _invoke('getDiagnostics', parser: ScannerDiagnostics.fromMap);

  @override
  Future<void> dispose() => _invoke<void>('dispose', parser: (_) {});

  Future<T> _invoke<T>(
    String method, {
    Object? arguments,
    required T Function(Object? value) parser,
  }) async {
    try {
      final Object? response = await methodChannel.invokeMethod<Object?>(
        method,
        arguments,
      );
      return parser(response);
    } on PlatformException catch (error) {
      throw ScannerException.fromPlatform(error);
    } on FormatException catch (error) {
      throw ScannerException(
        'INVALID_NATIVE_PAYLOAD',
        error.message,
        error.source,
      );
    }
  }
}
