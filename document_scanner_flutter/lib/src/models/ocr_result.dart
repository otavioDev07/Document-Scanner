import 'package:flutter/foundation.dart';

@immutable
final class OcrTextBlock {
  const OcrTextBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  factory OcrTextBlock.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('OCR block must be an object');
    }
    final String? text = value['text'] as String?;
    final num? left = value['left'] as num?;
    final num? top = value['top'] as num?;
    final num? width = value['width'] as num?;
    final num? height = value['height'] as num?;
    if (text == null ||
        left == null ||
        top == null ||
        width == null ||
        height == null) {
      throw const FormatException('OCR block is incomplete');
    }
    return OcrTextBlock(
      text: text,
      left: left.toDouble().clamp(0, 1),
      top: top.toDouble().clamp(0, 1),
      width: width.toDouble().clamp(0, 1),
      height: height.toDouble().clamp(0, 1),
    );
  }
}

@immutable
final class OcrResult {
  OcrResult({
    required this.text,
    required List<OcrTextBlock> blocks,
    required List<String> languages,
    required this.durationMilliseconds,
  })  : blocks = List<OcrTextBlock>.unmodifiable(blocks),
        languages = List<String>.unmodifiable(languages);

  final String text;
  final List<OcrTextBlock> blocks;
  final List<String> languages;
  final int durationMilliseconds;

  factory OcrResult.fromMap(Object? value) {
    if (value is! Map || value['text'] is! String) {
      throw const FormatException('OCR result must contain text');
    }
    final Object? rawBlocks = value['blocks'];
    final Object? rawLanguages = value['languages'];
    return OcrResult(
      text: value['text'] as String,
      blocks: rawBlocks is List
          ? rawBlocks.map(OcrTextBlock.fromMap).toList(growable: false)
          : const <OcrTextBlock>[],
      languages: rawLanguages is List
          ? rawLanguages.whereType<String>().toSet().toList(growable: false)
          : const <String>[],
      durationMilliseconds:
          (value['durationMilliseconds'] as num?)?.toInt() ?? 0,
    );
  }
}
