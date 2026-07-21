final class NativeStatus {
  const NativeStatus({
    required this.platform,
    required this.pluginVersion,
    required this.opencvVersion,
    required this.detectorAvailable,
    required this.staticImageSupported,
    required this.cameraPreviewSupported,
  });

  final String platform;
  final String pluginVersion;
  final String opencvVersion;
  final bool detectorAvailable;
  final bool staticImageSupported;
  final bool cameraPreviewSupported;

  factory NativeStatus.fromMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Native status must be a map');
    }
    return NativeStatus(
      platform: value['platform'] as String? ?? 'unknown',
      pluginVersion: value['pluginVersion'] as String? ?? 'unknown',
      opencvVersion: value['opencvVersion'] as String? ?? 'unavailable',
      detectorAvailable: value['detectorAvailable'] == true,
      staticImageSupported: value['staticImageSupported'] == true,
      cameraPreviewSupported: value['cameraPreviewSupported'] == true,
    );
  }
}
