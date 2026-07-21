final class CaptureResult {
  const CaptureResult({required this.path, this.mimeType, this.displayName});

  final String path;
  final String? mimeType;
  final String? displayName;

  factory CaptureResult.fromMap(Object? value) {
    if (value is! Map ||
        value['path'] is! String ||
        (value['path'] as String).isEmpty) {
      throw const FormatException('Capture result has no valid path');
    }
    return CaptureResult(
      path: value['path'] as String,
      mimeType: value['mimeType'] as String?,
      displayName: value['displayName'] as String?,
    );
  }
}
