import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scanner_point.dart';
import 'document_overlay.dart';

class CropEditor extends StatefulWidget {
  const CropEditor({
    required this.imagePath,
    required this.imageSize,
    required this.initialCorners,
    super.key,
    this.onCornersChanged,
    this.fit = BoxFit.contain,
  });

  final String imagePath;
  final Size imageSize;
  final List<ScannerPoint> initialCorners;
  final ValueChanged<List<ScannerPoint>>? onCornersChanged;
  final BoxFit fit;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  late List<ScannerPoint> _corners = List<ScannerPoint>.of(
    widget.initialCorners,
  );

  List<ScannerPoint> get corners => List<ScannerPoint>.unmodifiable(_corners);

  @override
  void didUpdateWidget(CropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCorners != widget.initialCorners) {
      _corners = List<ScannerPoint>.of(widget.initialCorners);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.file(File(widget.imagePath), fit: widget.fit),
          DocumentOverlay(
            corners: _corners,
            sourceSize: widget.imageSize,
            fit: widget.fit,
            onCornersChanged: (List<ScannerPoint> corners) {
              setState(() => _corners = corners);
              widget.onCornersChanged?.call(corners);
            },
          ),
        ],
      );
}
