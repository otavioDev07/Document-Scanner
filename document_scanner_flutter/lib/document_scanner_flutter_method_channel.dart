import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'document_scanner_flutter_platform_interface.dart';
import 'src/models/capture_result.dart';
import 'src/models/crop_result.dart';
import 'src/models/detection_result.dart';
import 'src/models/native_status.dart';
import 'src/models/scanner_exception.dart';
import 'src/models/scanner_options.dart';
import 'src/models/scanner_point.dart';

class MethodChannelDocumentScannerFlutter
    extends DocumentScannerFlutterPlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    'document_scanner_flutter',
  );

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
