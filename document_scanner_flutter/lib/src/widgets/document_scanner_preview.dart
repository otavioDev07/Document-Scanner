import 'package:flutter/material.dart';

import '../document_scanner_controller.dart';
import '../models/detection_result.dart';
import 'document_overlay.dart';

/// A preview composition surface. Live native camera textures are a later phase.
class DocumentScannerPreview extends StatelessWidget {
  const DocumentScannerPreview({
    required this.controller,
    required this.child,
    super.key,
    this.detection,
    this.fit = BoxFit.cover,
  });

  final DocumentScannerController controller;
  final Widget child;
  final DetectionResult? detection;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final DetectionResult? current = detection ?? controller.lastDetection;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        if (current?.corners != null)
          DocumentOverlay(
            corners: current!.corners!,
            sourceSize: Size(
              current.imageWidth.toDouble(),
              current.imageHeight.toDouble(),
            ),
            rotationDegrees: current.rotationDegrees,
            mirrored: current.mirrored,
            fit: fit,
          ),
      ],
    );
  }
}
