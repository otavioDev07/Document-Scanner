import 'dart:io';

import 'package:document_scanner_flutter/document_scanner_flutter.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ScannerExampleApp());

class ScannerExampleApp extends StatelessWidget {
  const ScannerExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF006C51),
      useMaterial3: true,
    ),
    home: const ScannerExamplePage(),
  );
}

class ScannerExamplePage extends StatefulWidget {
  const ScannerExamplePage({super.key});

  @override
  State<ScannerExamplePage> createState() => _ScannerExamplePageState();
}

class _ScannerExamplePageState extends State<ScannerExamplePage> {
  final DocumentScannerController _controller = DocumentScannerController();
  CaptureResult? _selected;
  DetectionResult? _detection;
  CropResult? _crop;
  List<ScannerPoint>? _editedCorners;
  NativeStatus? _status;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _chooseAndDetect() async {
    setState(() {
      _busy = true;
      _error = null;
      _crop = null;
    });
    try {
      final CaptureResult? selected = await _controller.pickImage();
      if (selected == null) return;
      final DetectionResult detection = await _controller.detectDocument(
        selected.path,
      );
      if (!mounted) return;
      setState(() {
        _selected = selected;
        _detection = detection;
        _editedCorners = detection.corners;
        if (!detection.documentFound) {
          _error = 'Nenhum documento foi detectado nesta imagem.';
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DetectionResult? detection = _detection;
    return Scaffold(
      appBar: AppBar(title: const Text('Document Scanner Flutter')),
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
                          ? 'Inicializando ponte nativa…'
                          : 'Android • OpenCV ${_status!.opencvVersion} • imagem estática',
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _crop != null
                        ? Image.file(File(_crop!.path), fit: BoxFit.contain)
                        : detection?.corners != null && _selected != null
                        ? CropEditor(
                            imagePath: _selected!.path,
                            imageSize: Size(
                              detection!.imageWidth.toDouble(),
                              detection.imageHeight.toDouble(),
                            ),
                            initialCorners: detection.corners!,
                            onCornersChanged: (List<ScannerPoint> value) =>
                                _editedCorners = value,
                          )
                        : const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'Escolha uma foto de documento para detectar e ajustar os quatro cantos.',
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
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _chooseAndDetect,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Escolher imagem'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _busy || _editedCorners == null
                          ? null
                          : _cropDocument,
                      icon: const Icon(Icons.crop),
                      label: const Text('Recortar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
