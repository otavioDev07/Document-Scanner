final class CameraPreviewInfo {
  const CameraPreviewInfo({
    required this.textureId,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.mirrored,
  })  : assert(textureId >= 0),
        assert(width > 0),
        assert(height > 0),
        assert(
          rotationDegrees == 0 ||
              rotationDegrees == 90 ||
              rotationDegrees == 180 ||
              rotationDegrees == 270,
        );

  final int textureId;

  /// Raw camera buffer width before [rotationDegrees] is applied.
  final int width;

  /// Raw camera buffer height before [rotationDegrees] is applied.
  final int height;
  final int rotationDegrees;
  final bool mirrored;

  int get orientedWidth =>
      rotationDegrees == 90 || rotationDegrees == 270 ? height : width;
  int get orientedHeight =>
      rotationDegrees == 90 || rotationDegrees == 270 ? width : height;

  factory CameraPreviewInfo.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Camera preview info must be a map');
    }
    final Object? textureId = value['textureId'];
    final Object? width = value['width'];
    final Object? height = value['height'];
    final Object? rotation = value['rotationDegrees'];
    if (textureId is! num ||
        width is! num ||
        height is! num ||
        rotation is! num) {
      throw const FormatException('Camera preview metadata is incomplete');
    }
    if (textureId.toInt() < 0 || width.toInt() <= 0 || height.toInt() <= 0) {
      throw const FormatException('Camera preview metadata is invalid');
    }
    if (!<int>{0, 90, 180, 270}.contains(rotation.toInt())) {
      throw const FormatException(
        'Preview rotation must be 0, 90, 180, or 270',
      );
    }
    return CameraPreviewInfo(
      textureId: textureId.toInt(),
      width: width.toInt(),
      height: height.toInt(),
      rotationDegrees: rotation.toInt(),
      mirrored: value['mirrored'] == true,
    );
  }
}
