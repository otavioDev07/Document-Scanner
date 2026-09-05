import 'dart:async';
import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/legacy_localizations.dart';
import '../../settings/application/scanner_settings_controller.dart';

/// Dedicated route for the automatic receipt-capture experience.
class AutomaticScannerPage extends StatefulWidget {
  const AutomaticScannerPage({super.key, required this.settings});

  final ScannerSettingsController settings;

  @override
  State<AutomaticScannerPage> createState() => _ScannerPageState();
}

/// Kept for callers that still need the previous route name. New scan flows
/// use [AutomaticScannerPage] directly.
@Deprecated('Use AutomaticScannerPage for receipt capture.')
class ScannerPage extends AutomaticScannerPage {
  const ScannerPage({super.key, required super.settings});
}

class _ScannerPageState extends State<AutomaticScannerPage>
    with WidgetsBindingObserver {
  late final DocumentScannerController _controller = DocumentScannerController(
    options: ScannerOptions(
      // This screen is intentionally dedicated to the automatic flow. The
      // manual/import controls remain implemented, but are disabled in the UI.
      autoCapture: true,
      diagnosticsEnabled: widget.settings.diagnosticsEnabled,
      autoCaptureDistanceThreshold: 150,
      jpegQuality: widget.settings.jpegQuality,
    ),
  );
  StreamSubscription<ScannerEvent>? _events;
  CaptureResult? _selected;
  DetectionResult? _detection;
  CropResult? _crop;
  List<ScannerPoint>? _editedCorners;
  NativeStatus? _status;
  String? _error;
  bool _busy = false;
  bool _cameraActive = false;
  bool _handlingCapture = false;
  String? _cameraNotice;
  bool _autoCapture = true;
  // Keep the manual flows in place so they can be restored without rebuilding
  // them, but leave this automatic-capture experience intentionally locked.
  final bool _manualControlsEnabled = false;
  ScannerFlashMode _flashMode = ScannerFlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = _controller.events.listen((ScannerEvent event) {
      if (event.type == ScannerEventType.documentDetected &&
          _cameraNotice != null &&
          mounted) {
        setState(() => _cameraNotice = null);
      }
      if (event.type == ScannerEventType.captureCompleted &&
          event.automatic &&
          event.capture != null) {
        final List<ScannerPoint>? previewCorners =
            event.capture!.previewCorners ?? _controller.lastDetection?.corners;
        unawaited(
          _useCameraCapture(
            event.capture!,
            automatic: true,
            previewCorners: previewCorners,
          ),
        );
      }
      if (event.type == ScannerEventType.error && mounted) {
        setState(() => _error = event.errorMessage ?? event.errorCode);
      }
    });
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final NativeStatus status = await _controller.initialize();
      if (!mounted) return;
      setState(() => _status = status);
      await _startCamera();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _startCamera() async {
    setState(() {
      _busy = true;
      _error = null;
      _cameraNotice = null;
      _crop = null;
      _selected = null;
      _detection = null;
      _editedCorners = null;
    });
    try {
      await _controller.startPreview();
      await _controller.setAutoCapture(true);
      if (mounted) setState(() => _cameraActive = true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _captureCamera() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<ScannerPoint>? previewCorners =
          _controller.lastDetection?.corners;
      final CaptureResult capture = await _controller.capture();
      await _useCameraCapture(
        capture,
        automatic: false,
        previewCorners: capture.previewCorners ?? previewCorners,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCameraCapture(
    CaptureResult capture, {
    required bool automatic,
    List<ScannerPoint>? previewCorners,
  }) async {
    if (!_cameraActive || _handlingCapture) return;
    _handlingCapture = true;
    if (mounted) setState(() => _busy = true);
    try {
      await _controller.stopPreview();
      if (mounted) setState(() => _cameraActive = false);
      final DetectionResult detection = await _controller.detectDocument(
        capture.path,
        previewCorners: previewCorners,
      );
      if (!mounted) return;
      if (automatic) {
        final List<ScannerPoint>? corners = detection.corners;
        if (corners == null) {
          await _resumeAfterAutomaticCaptureFailure(
            _detectionFailureMessage(detection),
          );
          return;
        }
        final CropResult result = await _controller.cropDocument(
          capture.path,
          corners: corners,
        );
        if (mounted) await _completeProcessedImage(result);
        return;
      }
      setState(() {
        _selected = capture;
        _detection = detection;
        _editedCorners = detection.corners ?? _fallbackCorners;
        if (!detection.documentFound) {
          _error = _detectionFailureMessage(detection);
        }
      });
    } catch (error) {
      if (automatic) {
        await _resumeAfterAutomaticCaptureFailure('$error');
      } else if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      _handlingCapture = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumeAfterAutomaticCaptureFailure(String message) async {
    if (!mounted) return;
    try {
      await _controller.startPreview();
      if (mounted) {
        setState(() {
          _cameraActive = true;
          _error = null;
          _cameraNotice = message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _cameraActive = false;
          _error = '$message\nNão foi possível reiniciar a câmera: $error';
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _chooseAndDetect() async {
    setState(() {
      _busy = true;
      _error = null;
      _crop = null;
    });
    try {
      if (_cameraActive) await _controller.stopPreview();
      final CaptureResult? selected = await _controller.pickImage();
      if (selected == null) return;
      final DetectionResult detection = await _controller.detectDocument(
        selected.path,
      );
      if (!mounted) return;
      setState(() {
        _cameraActive = false;
        _selected = selected;
        _detection = detection;
        _editedCorners = detection.corners ?? _fallbackCorners;
        if (!detection.documentFound) {
          _error =
              'Bordas não detectadas. Ajuste os quatro cantos manualmente.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cropDocument() async {
    final CaptureResult? selected = _selected;
    final List<ScannerPoint>? corners = _editedCorners;
    if (selected == null || corners == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final CropResult result = await _controller.cropDocument(
        selected.path,
        corners: corners,
      );
      if (mounted) setState(() => _crop = result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeProcessedImage(CropResult result) async {
    if (widget.settings.imageDestination == ImageDestination.internal) {
      if (mounted) Navigator.pop(context, result);
      return;
    }
    final String destination = widget.settings.cloudDestination.trim();
    if (destination.isEmpty) {
      throw const FormatException(
        'Configure um endpoint de nuvem antes de enviar a imagem.',
      );
    }
    await _controller.enqueueImageUpload(result.path, destination);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleAutoCapture() async {
    final bool enabled = !_autoCapture;
    try {
      await _controller.setAutoCapture(enabled);
      if (mounted) setState(() => _autoCapture = enabled);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _cycleFlash() async {
    final ScannerFlashMode next = switch (_flashMode) {
      ScannerFlashMode.off => ScannerFlashMode.auto,
      ScannerFlashMode.auto => ScannerFlashMode.on,
      ScannerFlashMode.on => ScannerFlashMode.torch,
      ScannerFlashMode.torch => ScannerFlashMode.off,
    };
    try {
      await _controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _controller.state == ScannerCameraState.previewing) {
      unawaited(_pauseForLifecycle());
    } else if (state == AppLifecycleState.resumed &&
        _cameraActive &&
        _controller.state == ScannerCameraState.paused) {
      unawaited(_resumeForLifecycle());
    }
  }

  Future<void> _pauseForLifecycle() async {
    try {
      await _controller.pausePreview();
    } catch (_) {
      // The native activity may have already paused the camera session.
    }
  }

  Future<void> _resumeForLifecycle() async {
    try {
      await _controller.resumePreview();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DetectionResult? detection = _detection;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(context.l10n.text('scan', fallback: 'Digitalizar página')),
        actions: <Widget>[
          if (_cameraActive)
            IconButton(
              tooltip: _autoCapture
                  ? context.l10n.text(
                      'autoscan',
                      fallback: 'Desativar captura automática',
                    )
                  : context.l10n.text(
                      'autoscan',
                      fallback: 'Ativar captura automática',
                    ),
              // Automatic capture is the only supported capture mode here.
              onPressed: _manualControlsEnabled && !_busy
                  ? _toggleAutoCapture
                  : null,
              icon: Icon(
                _autoCapture ? Icons.auto_awesome : Icons.auto_awesome_outlined,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _status == null
                          ? 'Inicializando processamento nativo…'
                          : 'OpenCV ${_status!.opencvVersion} • '
                                '${_cameraActive ? 'câmera ao vivo' : 'ajuste do recorte'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  if (_busy)
                    const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ColoredBox(
                    color: Colors.black,
                    child: _cameraActive
                        ? DocumentScannerPreview(
                            controller: _controller,
                            notice: _cameraNotice,
                          )
                        : _handlingCapture
                        ? const _ProcessingCoupon()
                        : _manualControlsEnabled && _crop != null
                        ? Image.file(File(_crop!.path), fit: BoxFit.contain)
                        : _manualControlsEnabled &&
                              _editedCorners != null &&
                              _selected != null
                        ? CropEditor(
                            imagePath: _selected!.path,
                            imageSize: Size(
                              detection!.imageWidth.toDouble(),
                              detection.imageHeight.toDouble(),
                            ),
                            initialCorners: _editedCorners!,
                            onCornersChanged: (List<ScannerPoint> value) =>
                                _editedCorners = value,
                          )
                        : _OpeningAutomaticCamera(
                            failed: _error != null,
                            onRetry: _busy ? null : _startCamera,
                          ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _bottomControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomControls() {
    if (!_cameraActive && !_manualControlsEnabled) {
      return const SizedBox.shrink();
    }
    if (_cameraActive) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          IconButton.filledTonal(
            tooltip: 'Flash: ${_flashMode.name}',
            onPressed: _busy ? null : _cycleFlash,
            icon: const Icon(Icons.flash_on),
          ),
          IconButton.filled(
            tooltip: 'Captura manual desativada',
            onPressed: _manualControlsEnabled && !_busy
                ? _captureCamera
                : null,
            iconSize: 36,
            padding: const EdgeInsets.all(18),
            icon: const Icon(Icons.camera_alt),
          ),
          IconButton.filledTonal(
            tooltip: context.l10n.text(
              'toggle_camera',
              fallback: 'Alternar câmera',
            ),
            onPressed: _busy ? null : _switchCamera,
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      );
    }
    if (_crop != null) {
      return Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _crop = null;
                    }),
              icon: const Icon(Icons.tune),
              label: const Text('Reajustar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await _completeProcessedImage(_crop!);
                      } catch (error) {
                        if (mounted) setState(() => _error = '$error');
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              icon: Icon(
                widget.settings.imageDestination == ImageDestination.cloud
                    ? Icons.cloud_upload_outlined
                    : Icons.check,
              ),
              label: Text(
                widget.settings.imageDestination == ImageDestination.cloud
                    ? 'Enviar'
                    : context.l10n.text('save', fallback: 'Usar página'),
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : _startCamera,
            icon: const Icon(Icons.document_scanner),
            label: Text(context.l10n.text('camera', fallback: 'Câmera')),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Galeria desativada',
          onPressed: _manualControlsEnabled && !_busy
              ? _chooseAndDetect
              : null,
          icon: const Icon(Icons.photo_library_outlined),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Recorte manual desativado',
          onPressed: _manualControlsEnabled &&
                  !_busy &&
                  _editedCorners != null
              ? _cropDocument
              : null,
          icon: const Icon(Icons.crop),
        ),
      ],
    );
  }

  static const List<ScannerPoint> _fallbackCorners = <ScannerPoint>[
    ScannerPoint(0.05, 0.05),
    ScannerPoint(0.95, 0.05),
    ScannerPoint(0.95, 0.95),
    ScannerPoint(0.05, 0.95),
  ];

  static String _detectionFailureMessage(DetectionResult detection) =>
      detection.source == 'fft_rejected'
          ? 'A imagem está borrada ou desfocada. Mantenha a câmera firme e tente novamente.'
          : 'O documento se moveu durante a captura. Tente mantê-lo estável.';
}

class _ProcessingCoupon extends StatelessWidget {
  const _ProcessingCoupon();

  @override
  Widget build(BuildContext context) => const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Text(
              'Processando cupom…',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
}

class _OpeningAutomaticCamera extends StatelessWidget {
  const _OpeningAutomaticCamera({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!failed)
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            const SizedBox(height: 16),
            Text(
              failed
                  ? 'Não foi possível abrir a câmera automática.'
                  : 'Abrindo câmera automática…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            if (failed) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      );
}
