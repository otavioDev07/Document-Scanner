import Flutter
import UIKit

public class DocumentScannerFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "document_scanner_flutter", binaryMessenger: registrar.messenger())
    let instance = DocumentScannerFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getNativeStatus", "initialize":
      result([
        "platform": "ios",
        "pluginVersion": "0.1.0",
        "opencvVersion": "not-linked",
        "detectorAvailable": false,
        "staticImageSupported": false,
        "cameraPreviewSupported": false,
      ])
    case "dispose":
      result(nil)
    case "pickImage", "detectDocument", "cropDocument":
      result(FlutterError(
        code: "IOS_PHASE_NOT_IMPLEMENTED",
        message: "The audited iOS native pipeline is preserved for a later migration phase",
        details: nil
      ))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
