import 'package:flutter/material.dart';

import '../document_scanner_controller.dart';
import '../models/camera_preview_info.dart';
import '../models/detection_result.dart';
import '../models/scanner_event.dart';
import '../models/scanner_point.dart';
import 'document_overlay.dart';

/// Composes the native camera Texture and the Flutter document overlay.
class DocumentScannerPreview extends StatelessWidget {
  const DocumentScannerPreview({
    required this.controller,
    super.key,
    this.child,
    this.detection,
    this.fit = BoxFit.cover,
    this.showOverlay = false,
  });

  final DocumentScannerController controller;

  /// Fallback content used before a native Texture is available. It also keeps
  /// static-image preview support for consumers that provide their own image.
  final Widget? child;
  final DetectionResult? detection;
  final BoxFit fit;

  /// Live contours are optional because preview candidates are intentionally
  /// lightweight and may differ from the high-resolution capture result.
  final bool showOverlay;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? _) {
          final CameraPreviewInfo? preview = controller.previewInfo;
          final DetectionResult? current =
              detection ?? controller.lastDetection;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (preview != null)
                _NativeTexturePreview(info: preview, fit: fit)
              else
                child ?? const ColoredBox(color: Colors.black),
              if (showOverlay && current?.corners != null)
                TweenAnimationBuilder<List<ScannerPoint>>(
                  tween: _ScannerCornersTween(end: current!.corners!),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  builder: (
                    BuildContext context,
                    List<ScannerPoint> corners,
                    Widget? child,
                  ) =>
                      DocumentOverlay(
                    corners: corners,
                    sourceSize: Size(
                      current.imageWidth.toDouble(),
                      current.imageHeight.toDouble(),
                    ),
                    rotationDegrees: current.rotationDegrees,
                    mirrored: current.mirrored,
                    fit: fit,
                    borderColor: _stateColor(controller.detectionState),
                    fillColor: _stateColor(
                      controller.detectionState,
                    ).withAlpha(28),
                    handleRadius: 0,
                  ),
                ),
              Positioned(
                top: 24,
                left: 24,
                right: 24,
                child: _ScannerStatusBanner(
                  message: _statusMessage(controller),
                  color: _statusColor(controller),
                ),
              ),
              if (controller.detectionState ==
                      ScannerDetectionState.stabilizing ||
                  controller.detectionState == ScannerDetectionState.stable)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: LinearProgressIndicator(
                    value: controller.stability,
                    color: _stateColor(controller.detectionState),
                    backgroundColor: Colors.white24,
                  ),
                ),
            ],
          );
        },
      );

  static String _statusMessage(DocumentScannerController controller) {
    if (controller.documentBlurred) {
      return 'Imagem instável. Mantenha a câmera firme.';
    }
    return switch (controller.detectionState) {
      ScannerDetectionState.detected ||
      ScannerDetectionState.stabilizing =>
        'Cupom localizado. Mantenha a mão estável.',
      ScannerDetectionState.stable => 'Cupom estável. Pronto para capturar.',
      ScannerDetectionState.capturing ||
      ScannerDetectionState.processing => 'Processando cupom…',
      ScannerDetectionState.error => 'Não foi possível analisar a imagem.',
      ScannerDetectionState.searching || ScannerDetectionState.lost =>
        'Buscando cupom, aguarde com a mão estável…',
    };
  }

  static Color _statusColor(DocumentScannerController controller) {
    if (controller.documentBlurred) return const Color(0xE5B3261E);
    return switch (controller.detectionState) {
      ScannerDetectionState.stable => const Color(0xE5007D62),
      ScannerDetectionState.error => const Color(0xE5B3261E),
      _ => const Color(0xCC1D252B),
    };
  }

  static Color _stateColor(ScannerDetectionState state) => switch (state) {
        ScannerDetectionState.detected => const Color(0xFFFFC107),
        ScannerDetectionState.stabilizing => const Color(0xFFFF9800),
        ScannerDetectionState.stable => const Color(0xFF00D4A6),
        ScannerDetectionState.capturing ||
        ScannerDetectionState.processing =>
          const Color(0xFF42A5F5),
        ScannerDetectionState.error => const Color(0xFFEF5350),
        ScannerDetectionState.searching ||
        ScannerDetectionState.lost =>
          Colors.white54,
      };
}

class _ScannerStatusBanner extends StatelessWidget {
  const _ScannerStatusBanner({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.document_scanner_outlined, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
}

final class _ScannerCornersTween extends Tween<List<ScannerPoint>> {
  _ScannerCornersTween({required super.end});

  @override
  List<ScannerPoint> lerp(double t) {
    final List<ScannerPoint> target = end!;
    final List<ScannerPoint> source = begin ?? target;
    return List<ScannerPoint>.generate(
      target.length,
      (int index) => ScannerPoint(
        source[index].x + (target[index].x - source[index].x) * t,
        source[index].y + (target[index].y - source[index].y) * t,
      ),
      growable: false,
    );
  }
}

class _NativeTexturePreview extends StatelessWidget {
  const _NativeTexturePreview({required this.info, required this.fit});

  final CameraPreviewInfo info;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    Widget texture = SizedBox(
      width: info.width.toDouble(),
      height: info.height.toDouble(),
      child: Texture(textureId: info.textureId, freeze: false),
    );
    texture = RotatedBox(
      quarterTurns: info.rotationDegrees ~/ 90,
      child: texture,
    );
    if (info.mirrored) {
      texture = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: texture,
      );
    }
    return ClipRect(
      child: FittedBox(
        fit: fit,
        alignment: Alignment.center,
        child: texture,
      ),
    );
  }
}
