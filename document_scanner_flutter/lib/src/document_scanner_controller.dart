import 'dart:async';

import 'package:flutter/foundation.dart';

import '../document_scanner_flutter_platform_interface.dart';
import 'models/capture_result.dart';
import 'models/crop_result.dart';
import 'models/detection_result.dart';
import 'models/native_status.dart';
import 'models/scanner_camera_state.dart';
import 'models/scanner_corners.dart';
import 'models/scanner_exception.dart';
import 'models/scanner_options.dart';
import 'models/scanner_point.dart';

final class DocumentScannerController extends ChangeNotifier {
  DocumentScannerController({
    this.options = const ScannerOptions(),
    DocumentScannerFlutterPlatform? platform,
  }) : _platform = platform ?? DocumentScannerFlutterPlatform.instance;

  final ScannerOptions options;
  final DocumentScannerFlutterPlatform _platform;

  ScannerCameraState _state = ScannerCameraState.uninitialized;
  NativeStatus? _nativeStatus;
  DetectionResult? _lastDetection;

  ScannerCameraState get state => _state;
  NativeStatus? get nativeStatus => _nativeStatus;
  DetectionResult? get lastDetection => _lastDetection;
  bool get isDisposed => _state == ScannerCameraState.disposed;

  Future<NativeStatus> initialize() async {
    _ensureNotDisposed();
    if (_state == ScannerCameraState.ready && _nativeStatus != null) {
      return _nativeStatus!;
    }
    _setState(ScannerCameraState.initializing);
    try {
      _nativeStatus = await _platform.initialize();
      _setState(ScannerCameraState.ready);
      return _nativeStatus!;
    } catch (_) {
      _setState(ScannerCameraState.uninitialized);
      rethrow;
    }
  }

  Future<NativeStatus> getNativeStatus() async {
    _ensureNotDisposed();
    return _nativeStatus = await _platform.getNativeStatus();
  }

  Future<CaptureResult?> pickImage() => _runReady(_platform.pickImage);

  Future<DetectionResult> detectDocument(String imagePath) =>
      _runReady(() async {
        final DetectionResult result = await _platform.detectDocument(
          imagePath,
          options,
        );
        _lastDetection = result;
        return result;
      });

  Future<CropResult> cropDocument(
    String imagePath, {
    List<ScannerPoint>? corners,
  }) =>
      _runReady(() {
        final List<ScannerPoint>? selected = corners ?? _lastDetection?.corners;
        if (selected == null) {
          throw const ScannerException(
            'NO_DOCUMENT',
            'No document corners are available to crop',
          );
        }
        late final List<ScannerPoint> validated;
        try {
          validated = ScannerCorners.validate(selected);
        } on FormatException catch (error) {
          throw ScannerException(
              'INVALID_ARGUMENT', error.message, error.source);
        }
        return _platform.cropDocument(
          imagePath,
          validated,
          options,
        );
      });

  Future<void> startPreview() => _unsupportedCamera('startPreview');
  Future<void> stopPreview() => _unsupportedCamera('stopPreview');
  Future<CaptureResult> capture() => _unsupportedCamera('capture');
  Future<void> setFlashMode(ScannerFlashMode mode) =>
      _unsupportedCamera('setFlashMode');
  Future<void> setAutoCapture(bool enabled) =>
      _unsupportedCamera('setAutoCapture');

  Future<T> _unsupportedCamera<T>(String operation) async {
    _ensureNotDisposed();
    throw ScannerException(
      'CAMERA_PHASE_NOT_IMPLEMENTED',
      '$operation is reserved for the later live-camera phase',
    );
  }

  Future<T> _runReady<T>(Future<T> Function() operation) async {
    _ensureNotDisposed();
    if (_state == ScannerCameraState.uninitialized) await initialize();
    if (_state != ScannerCameraState.ready) {
      throw ScannerException(
        'INVALID_STATE',
        'Scanner is not ready: ${_state.name}',
      );
    }
    _setState(ScannerCameraState.processing);
    try {
      final T value = await operation();
      _ensureNotDisposed();
      return value;
    } finally {
      if (!isDisposed) {
        _setState(ScannerCameraState.ready);
      }
    }
  }

  void _ensureNotDisposed() {
    if (isDisposed) {
      throw const ScannerException(
        'DISPOSED',
        'Scanner controller is disposed',
      );
    }
  }

  void _setState(ScannerCameraState value) {
    _state = value;
    notifyListeners();
  }

  Future<void> close() async {
    if (isDisposed) return;
    _state = ScannerCameraState.disposed;
    notifyListeners();
    try {
      await _platform.dispose();
    } finally {
      super.dispose();
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _state = ScannerCameraState.disposed;
    unawaited(_platform.dispose());
    super.dispose();
  }
}
