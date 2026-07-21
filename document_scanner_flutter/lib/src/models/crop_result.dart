final class CropResult {
  const CropResult({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;

  factory CropResult.fromMap(Object? value) {
    if (value is! Map ||
        value['path'] is! String ||
        value['width'] is! num ||
        value['height'] is! num) {
      throw const FormatException('Crop result payload is invalid');
    }
    final CropResult result = CropResult(
      path: value['path'] as String,
      width: (value['width'] as num).toInt(),
      height: (value['height'] as num).toInt(),
    );
    if (result.path.isEmpty || result.width <= 0 || result.height <= 0) {
      throw const FormatException('Crop result values are invalid');
    }
    return result;
  }
}
