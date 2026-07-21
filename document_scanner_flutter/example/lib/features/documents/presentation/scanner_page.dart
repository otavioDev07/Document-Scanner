import 'dart:async';
import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';

import '../../settings/application/scanner_settings_controller.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, required this.settings});

  final ScannerSettingsController settings;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  late final DocumentScannerController _controller = DocumentScannerController(
    options: ScannerOptions(
      autoCapture: widget.settings.autoCapture,
      diagnosticsEnabled: widget.settings.diagnosticsEnabled,
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
  late bool _autoCapture = widget.settings.autoCapture;
  ScannerFlashMode _flashMode = ScannerFlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = _controller.events.listen((ScannerEvent event) {
      if (event.type == ScannerEventType.captureCompleted &&
          event.automatic &&
          event.capture != null) {
        unawaited(_useCameraCapture(event.capture!));
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
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _startCamera() async {
    setState(() {
      _busy = true;
      _error = null;
      _crop = null;
      _selected = null;
      _detection = null;
      _editedCorners = null;
    });
    try {
      await _controller.startPreview();
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
      await _useCameraCapture(await _controller.capture());
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCameraCapture(CaptureResult capture) async {
    if (!_cameraActive || _handlingCapture) return;
    _handlingCapture = true;
    if (mounted) setState(() => _busy = true);
    try {
      await _controller.stopPreview();
      final DetectionResult detection = await _controller.detectDocument(
        capture.path,
      );
      if (!mounted) return;
      setState(() {
        _cameraActive = false;
        _selected = capture;
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
      _handlingCapture = false;
      if (mounted) setState(() => _busy = false);
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
        title: const Text('Digitalizar página'),
        actions: <Widget>[
          if (_cameraActive)
            IconButton(
              tooltip: _autoCapture
                  ? 'Desativar captura automática'
                  : 'Ativar captura automática',
              onPressed: _busy ? null : _toggleAutoCapture,
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
                        ? DocumentScannerPreview(controller: _controller)
                        : _crop != null
                        ? Image.file(File(_crop!.path), fit: BoxFit.contain)
                        : _editedCorners != null && _selected != null
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
                        : const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'Abra a câmera ou escolha uma imagem para localizar as bordas do documento.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
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
            tooltip: 'Capturar',
            onPressed: _busy ? null : _captureCamera,
            iconSize: 36,
            padding: const EdgeInsets.all(18),
            icon: const Icon(Icons.camera_alt),
          ),
          IconButton.filledTonal(
            tooltip: 'Alternar câmera',
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
              onPressed: _busy ? null : () => Navigator.pop(context, _crop),
              icon: const Icon(Icons.check),
              label: const Text('Usar página'),
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
            label: const Text('Câmera'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Escolher imagem',
          onPressed: _busy ? null : _chooseAndDetect,
          icon: const Icon(Icons.photo_library_outlined),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Recortar',
          onPressed: _busy || _editedCorners == null ? null : _cropDocument,
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
}
