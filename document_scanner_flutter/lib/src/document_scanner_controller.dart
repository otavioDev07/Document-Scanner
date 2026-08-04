import 'dart:async';

import 'package:flutter/foundation.dart';

import '../document_scanner_flutter_platform_interface.dart';
import 'models/camera_preview_info.dart';
import 'models/capture_result.dart';
import 'models/crop_result.dart';
import 'models/detection_result.dart';
import 'models/native_status.dart';
import 'models/ocr_result.dart';
import 'models/scanner_camera_state.dart';
import 'models/scanner_corners.dart';
import 'models/scanner_diagnostics.dart';
import 'models/scanner_event.dart';
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
  final StreamController<ScannerEvent> _eventController =
      StreamController<ScannerEvent>.broadcast(sync: true);

  ScannerCameraState _state = ScannerCameraState.uninitialized;
  ScannerDetectionState _detectionState = ScannerDetectionState.searching;
  NativeStatus? _nativeStatus;
  CameraPreviewInfo? _previewInfo;
  DetectionResult? _lastDetection;
  CaptureResult? _lastCapture;
  ScannerDiagnostics? _diagnostics;
  ScannerException? _lastError;
  double _stability = 0;
  int _stableFrames = 0;
  Future<NativeStatus>? _initialization;
  StreamSubscription<ScannerEvent>? _nativeEvents;

  ScannerCameraState get state => _state;
  ScannerDetectionState get detectionState => _detectionState;
  NativeStatus? get nativeStatus => _nativeStatus;
  CameraPreviewInfo? get previewInfo => _previewInfo;
  DetectionResult? get lastDetection => _lastDetection;
  CaptureResult? get lastCapture => _lastCapture;
  ScannerDiagnostics? get diagnostics => _diagnostics;
  ScannerException? get lastError => _lastError;
  double get stability => _stability;
  int get stableFrames => _stableFrames;
  Stream<ScannerEvent> get events => _eventController.stream;
  bool get isDisposed => _state == ScannerCameraState.disposed;

  Future<NativeStatus> initialize() {
    _ensureNotDisposed();
    if (_state == ScannerCameraState.ready && _nativeStatus != null) {
      return Future<NativeStatus>.value(_nativeStatus);
    }
    final Future<NativeStatus>? active = _initialization;
    if (active != null) return active;

    _setState(ScannerCameraState.initializing);
    final Future<NativeStatus> operation = _platform.initialize().then(
      (NativeStatus status) {
        _ensureNotDisposed();
        _nativeStatus = status;
        _setState(ScannerCameraState.ready);
        return status;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!isDisposed) _setState(ScannerCameraState.uninitialized);
        Error.throwWithStackTrace(error, stackTrace);
      },
    ).whenComplete(() => _initialization = null);
    _initialization = operation;
    return operation;
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
            'Nenhum vértice de documento está disponível para realizar o corte.',
          );
        }
        late final List<ScannerPoint> validated;
        try {
          validated = ScannerCorners.validate(selected);
        } on FormatException catch (error) {
          throw ScannerException(
            'INVALID_ARGUMENT',
            'Parâmetros de corte inválidos: ${error.message}',
            error.source,
          );
        }
        return _platform.cropDocument(
          imagePath,
          validated,
          options,
        );
      });

  Future<CropResult> applyFilter(
    String imagePath,
    String outputPath,
    String filter, {
    int jpegQuality = 92,
  }) =>
      _runReady(
        () => _platform.applyFilter(
          imagePath,
          outputPath,
          filter,
          jpegQuality: jpegQuality,
        ),
      );

  Future<OcrResult> recognizeText(
    String imagePath, {
    List<String> languages = const <String>[],
  }) =>
      _runReady(
        () => _platform.recognizeText(imagePath, languages: languages),
      );

  Future<CameraPreviewInfo> startPreview() async {
    _ensureNotDisposed();
    if (_state == ScannerCameraState.uninitialized ||
        _state == ScannerCameraState.initializing) {
      await initialize();
    }
    if (_state == ScannerCameraState.previewing && _previewInfo != null) {
      return _previewInfo!;
    }
    if (_state != ScannerCameraState.ready &&
        _state != ScannerCameraState.paused) {
      throw ScannerException(
        'INVALID_STATE',
        'Não foi possível iniciar a visualização porque a câmera está no estado: ${_translateState(_state)}.',
      );
    }
    _ensureEventSubscription();
    _lastError = null;
    _setState(ScannerCameraState.starting);
    try {
      _previewInfo = await _platform.startPreview(options);
      _ensureNotDisposed();
      _setState(ScannerCameraState.previewing);
      return _previewInfo!;
    } catch (error) {
      if (!isDisposed) _setState(ScannerCameraState.error);
      rethrow;
    }
  }

  Future<void> stopPreview() async {
    _ensureNotDisposed();
    if (_state == ScannerCameraState.ready) return;
    await _platform.stopPreview();
    _previewInfo = null;
    _lastDetection = null;
    _detectionState = ScannerDetectionState.searching;
    _setState(ScannerCameraState.ready);
  }

  Future<void> pausePreview() async {
    _ensureNotDisposed();
    if (_state != ScannerCameraState.previewing) {
      throw ScannerException(
        'INVALID_STATE',
        'Não foi possível pausar a visualização porque a câmera está no estado: ${_translateState(_state)}.',
      );
    }
    await _platform.pausePreview();
    _setState(ScannerCameraState.paused);
  }

  Future<CameraPreviewInfo> resumePreview() async {
    _ensureNotDisposed();
    if (_state != ScannerCameraState.paused) {
      throw ScannerException(
        'INVALID_STATE',
        'Não foi possível retomar a visualização porque a câmera está no estado: ${_translateState(_state)}.',
      );
    }
    _previewInfo = await _platform.resumePreview();
    _setState(ScannerCameraState.previewing);
    return _previewInfo!;
  }

  Future<CameraPreviewInfo> switchCamera() async {
    _ensurePreviewing('alternar a câmera');
    _previewInfo = await _platform.switchCamera();
    _lastDetection = null;
    _detectionState = ScannerDetectionState.searching;
    notifyListeners();
    return _previewInfo!;
  }

  Future<CaptureResult> capture() async {
    _ensureNotDisposed();
    
    // Permite disparar se a câmera estiver em preview ou registrando falha momentânea no detector
    if (_state != ScannerCameraState.previewing && _state != ScannerCameraState.error) {
      throw ScannerException(
        'INVALID_STATE',
        'Não foi possível capturar a imagem porque a câmera está no estado: ${_translateState(_state)}.',
      );
    }

    _setState(ScannerCameraState.capturing);
    try {
      final CaptureResult result = await _platform.capture();
      _ensureNotDisposed();
      _lastCapture = result;
      return result;
    } finally {
      if (!isDisposed && _state == ScannerCameraState.capturing) {
        _setState(ScannerCameraState.previewing);
      }
    }
  }

  Future<void> setFlashMode(ScannerFlashMode mode) async {
    _ensurePreviewing('alterar o modo do flash');
    await _platform.setFlashMode(mode);
  }

  Future<void> setAutoCapture(bool enabled) async {
    _ensurePreviewing('configurar a captura automática');
    await _platform.setAutoCapture(enabled);
  }

  Future<ScannerDiagnostics> getDiagnostics() async {
    _ensureNotDisposed();
    final ScannerDiagnostics value = await _platform.getDiagnostics();
    _diagnostics = value;
    notifyListeners();
    return value;
  }

  Future<T> _runReady<T>(Future<T> Function() operation) async {
    _ensureNotDisposed();
    if (_state == ScannerCameraState.uninitialized ||
        _state == ScannerCameraState.initializing) {
      await initialize();
    }
    if (_state != ScannerCameraState.ready) {
      throw ScannerException(
        'INVALID_STATE',
        'O digitalizador não está pronto para o processamento. Estado atual: ${_translateState(_state)}.',
      );
    }
    _setState(ScannerCameraState.processing);
    try {
      final T value = await operation();
      _ensureNotDisposed();
      return value;
    } finally {
      if (!isDisposed) _setState(ScannerCameraState.ready);
    }
  }

  void _ensureEventSubscription() {
    _nativeEvents ??= _platform.events.listen(
      _handleNativeEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (isDisposed) return;
        _lastError = error is ScannerException
            ? error
            : ScannerException(
                'NATIVE_EVENT_ERROR', 
                'Ocorreu uma falha na comunicação nativa: $error'
              );
        _detectionState = ScannerDetectionState.error;
        // Não rebaixamos o estado da câmera para "error" para evitar o bloqueio da UI
      },
    );
  }

  void _handleNativeEvent(ScannerEvent event) {
    if (isDisposed) return;
    _detectionState = event.state;
    _stability = event.stability;
    _stableFrames = event.stableFrames;
    if (event.detection != null) _lastDetection = event.detection;
    if (event.type == ScannerEventType.documentLost) _lastDetection = null;
    if (event.capture != null) _lastCapture = event.capture;
    if (event.previewInfo != null) _previewInfo = event.previewInfo;
    if (event.diagnostics != null) _diagnostics = event.diagnostics;

    switch (event.type) {
      case ScannerEventType.captureStarted:
        _state = ScannerCameraState.capturing;
      case ScannerEventType.captureCompleted:
        if (_state != ScannerCameraState.processing) {
          _state = ScannerCameraState.previewing;
        }
      case ScannerEventType.processingStarted:
        _state = ScannerCameraState.processing;
      case ScannerEventType.processingCompleted:
        _state = ScannerCameraState.previewing;
      case ScannerEventType.error:
        _lastError = ScannerException(
          event.errorCode ?? 'NATIVE_EVENT_ERROR',
          _translateErrorMessage(
            event.errorCode, 
            event.errorMessage ?? 'Ocorreu uma falha no evento do digitalizador.',
          ),
        );
        // Atualiza a detecção para erro, mas preserva a câmera ativa para permitir foto manual
        _detectionState = ScannerDetectionState.error;
      case ScannerEventType.cameraState:
      case ScannerEventType.documentDetected:
      case ScannerEventType.documentLost:
      case ScannerEventType.stabilityChanged:
      case ScannerEventType.autoCaptureProgress:
      case ScannerEventType.diagnostics:
        break;
    }
    _eventController.add(event);
    notifyListeners();
  }

  void _ensurePreviewing(String operation) {
    _ensureNotDisposed();
    if (_state != ScannerCameraState.previewing && _state != ScannerCameraState.error) {
      throw ScannerException(
        'INVALID_STATE',
        'Não é possível $operation enquanto a câmera estiver no estado: ${_translateState(_state)}.',
      );
    }
  }

  void _ensureNotDisposed() {
    if (isDisposed) {
      throw const ScannerException(
        'DISPOSED',
        'O controlador do digitalizador foi encerrado e não pode mais ser utilizado.',
      );
    }
  }

  void _setState(ScannerCameraState value) {
    _state = value;
    notifyListeners();
  }

  String _translateState(ScannerCameraState state) {
    switch (state) {
      case ScannerCameraState.uninitialized:
        return 'não inicializado';
      case ScannerCameraState.initializing:
        return 'inicializando';
      case ScannerCameraState.ready:
        return 'pronto';
      case ScannerCameraState.starting:
        return 'iniciando câmera';
      case ScannerCameraState.previewing:
        return 'em visualização';
      case ScannerCameraState.paused:
        return 'pausado';
      case ScannerCameraState.capturing:
        return 'capturando imagem';
      case ScannerCameraState.processing:
        return 'processando';
      case ScannerCameraState.error:
        return 'com falha na detecção';
      case ScannerCameraState.disposed:
        return 'desconectado';
    }
  }

  String _translateErrorMessage(String? code, String originalMessage) {
    switch (code) {
      case 'NO_DOCUMENT':
        return 'Nenhum documento válido foi identificado na imagem.';
      case 'TOO_DARK':
        return 'O ambiente está muito escuro para a leitura.';
      case 'WRONG_ANGLE':
        return 'Posicione a câmera de forma paralela ao documento.';
      case 'DOCUMENT_TOO_SMALL':
        return 'Aproxime a câmera do documento.';
      case 'LOW_STABILITY':
        return 'Mantenha o dispositivo firme durante a leitura.';
      default:
        return originalMessage;
    }
  }

  Future<void> close() async {
    if (isDisposed) return;
    _state = ScannerCameraState.disposed;
    notifyListeners();
    await _nativeEvents?.cancel();
    _nativeEvents = null;
    try {
      await _platform.dispose();
    } finally {
      await _eventController.close();
      super.dispose();
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _state = ScannerCameraState.disposed;
    unawaited(_nativeEvents?.cancel());
    _nativeEvents = null;
    unawaited(_platform.dispose());
    unawaited(_eventController.close());
    super.dispose();
  }
}