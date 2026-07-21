import AVFoundation
import DocumentScannerNative
import Flutter
import UIKit

public final class DocumentScannerFlutterPlugin: NSObject, FlutterPlugin,
  FlutterStreamHandler, UIImagePickerControllerDelegate, UINavigationControllerDelegate
{
  private let registrar: FlutterPluginRegistrar
  private let processingQueue = DispatchQueue(label: "document-scanner.processing")
  private var eventSink: FlutterEventSink?
  private var cameraSession: CameraSession?
  private var pendingPickerResult: FlutterResult?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DocumentScannerFlutterPlugin(registrar: registrar)
    let methodChannel = FlutterMethodChannel(
      name: "document_scanner_flutter",
      binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(
      name: "document_scanner_flutter/events",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getNativeStatus", "initialize":
      result(nativeStatus())
    case "pickImage":
      pickImage(result: result)
    case "detectDocument":
      detectDocument(call: call, result: result)
    case "cropDocument":
      cropDocument(call: call, result: result)
    case "applyFilter":
      applyFilter(call: call, result: result)
    case "startPreview":
      startPreview(call: call, result: result)
    case "stopPreview":
      cameraSession?.stop()
      result(nil)
    case "pausePreview":
      cameraCommand(result: result) { session in
        try session.pause()
        return nil
      }
    case "resumePreview":
      guard let session = cameraSession else {
        result(cameraError("INVALID_STATE", "Camera preview has not been started"))
        return
      }
      session.resume { [weak self] outcome in self?.complete(outcome, result: result) }
    case "switchCamera":
      guard let session = cameraSession else {
        result(cameraError("INVALID_STATE", "Camera preview has not been started"))
        return
      }
      session.switchCamera { [weak self] outcome in self?.complete(outcome, result: result) }
    case "setFlash":
      let arguments = dictionary(call.arguments)
      guard let mode = arguments?["mode"] as? String else {
        result(cameraError("INVALID_ARGUMENT", "mode is required"))
        return
      }
      cameraCommand(result: result) { session in
        try session.setFlash(mode)
        return nil
      }
    case "setAutoCapture":
      let arguments = dictionary(call.arguments)
      guard let enabled = arguments?["enabled"] as? Bool else {
        result(cameraError("INVALID_ARGUMENT", "enabled is required"))
        return
      }
      cameraCommand(result: result) { session in
        try session.setAutoCapture(enabled)
        return nil
      }
    case "capture":
      guard let session = cameraSession else {
        result(cameraError("INVALID_STATE", "Camera preview has not been started"))
        return
      }
      session.capture(automatic: false) { [weak self] outcome in
        self?.complete(outcome, result: result)
      }
    case "getDiagnostics":
      cameraCommand(result: result) { session in session.diagnostics() }
    case "dispose":
      cameraSession?.dispose()
      cameraSession = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func nativeStatus() -> [String: Any] {
    [
      "platform": "ios",
      "pluginVersion": "0.2.0",
      "opencvVersion": DSNativeDocumentProcessor.openCVVersion(),
      "detectorAvailable": true,
      "staticImageSupported": true,
      "cameraPreviewSupported": true,
    ]
  }

  private func detectDocument(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = dictionary(call.arguments),
      let imagePath = arguments["imagePath"] as? String,
      !imagePath.isEmpty
    else {
      result(cameraError("INVALID_ARGUMENT", "imagePath is required"))
      return
    }
    let options = dictionary(arguments["options"]) ?? [:]
    let resize = (options["detectionResizeThreshold"] as? NSNumber)?.intValue ?? 1200
    let area = (options["areaScaleMinFactor"] as? NSNumber)?.doubleValue ?? 0.04
    processingQueue.async {
      let value = DSNativeDocumentProcessor.detectImage(
        atPath: imagePath,
        resizeThreshold: resize,
        areaScaleMinFactor: area)
      DispatchQueue.main.async { self.returnNative(value, result: result) }
    }
  }

  private func cropDocument(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = dictionary(call.arguments),
      let imagePath = arguments["imagePath"] as? String,
      let corners = arguments["corners"] as? [[String: NSNumber]],
      corners.count == 4
    else {
      result(cameraError("INVALID_ARGUMENT", "imagePath and four corners are required"))
      return
    }
    let options = dictionary(arguments["options"]) ?? [:]
    let maximum = (options["maxOutputDimension"] as? NSNumber)?.intValue ?? 4096
    let quality = (options["jpegQuality"] as? NSNumber)?.intValue ?? 92
    let directory = cacheDirectory().appendingPathComponent("crop", isDirectory: true)
    let output = directory.appendingPathComponent(
      "crop_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
    processingQueue.async {
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let value = DSNativeDocumentProcessor.cropImage(
          atPath: imagePath,
          corners: corners,
          outputPath: output.path,
          maxOutputDimension: maximum,
          jpegQuality: quality)
        DispatchQueue.main.async { self.returnNative(value, result: result) }
      } catch {
        DispatchQueue.main.async {
          result(self.cameraError("WRITE_FAILED", error.localizedDescription))
        }
      }
    }
  }

  private func applyFilter(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = dictionary(call.arguments),
      let imagePath = arguments["imagePath"] as? String,
      !imagePath.isEmpty,
      let outputPath = arguments["outputPath"] as? String,
      !outputPath.isEmpty,
      let filter = arguments["filter"] as? String
    else {
      result(cameraError(
        "INVALID_ARGUMENT",
        "imagePath, outputPath, and filter are required"))
      return
    }
    let outputFormat = arguments["outputFormat"] as? String ?? "jpeg"
    let quality = (arguments["jpegQuality"] as? NSNumber)?.intValue ?? 92
    processingQueue.async {
      let value = DSNativeDocumentProcessor.applyFilter(
        atPath: imagePath,
        filter: filter,
        outputPath: outputPath,
        outputFormat: outputFormat,
        jpegQuality: quality)
      DispatchQueue.main.async { self.returnNative(value, result: result) }
    }
  }

  private func startPreview(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = dictionary(call.arguments)
    let options = dictionary(arguments?["options"])
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      startAuthorizedCamera(options: options, result: result)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.startAuthorizedCamera(options: options, result: result)
          } else {
            result(self.cameraError("CAMERA_PERMISSION_DENIED", "Camera permission was denied"))
          }
        }
      }
    case .denied, .restricted:
      result(cameraError("CAMERA_PERMISSION_DENIED", "Camera permission was denied"))
    @unknown default:
      result(cameraError("CAMERA_PERMISSION_DENIED", "Camera permission is unavailable"))
    }
  }

  private func startAuthorizedCamera(
    options: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    let session = cameraSession ?? CameraSession(
      textureRegistry: registrar.textures(),
      cacheDirectory: cacheDirectory(),
      emit: { [weak self] event in
        DispatchQueue.main.async { self?.eventSink?(event) }
      })
    cameraSession = session
    session.start(options: options) { [weak self] outcome in
      self?.complete(outcome, result: result)
    }
  }

  private func cameraCommand(
    result: @escaping FlutterResult,
    operation: (CameraSession) throws -> Any?
  ) {
    guard let session = cameraSession else {
      result(cameraError("INVALID_STATE", "Camera preview has not been started"))
      return
    }
    do {
      result(try operation(session))
    } catch let error as CameraOperationError {
      result(cameraError(error.code, error.message))
    } catch {
      result(cameraError("NATIVE_PROCESSING_ERROR", error.localizedDescription))
    }
  }

  private func complete(
    _ outcome: Result<[String: Any], CameraOperationError>,
    result: @escaping FlutterResult
  ) {
    switch outcome {
    case .success(let value): result(value)
    case .failure(let error): result(cameraError(error.code, error.message))
    }
  }

  private func returnNative(_ value: [String: Any], result: @escaping FlutterResult) {
    if let code = value["errorCode"] as? String {
      result(cameraError(code, value["errorMessage"] as? String ?? "Native operation failed"))
    } else {
      result(value)
    }
  }

  private func pickImage(result: @escaping FlutterResult) {
    guard pendingPickerResult == nil else {
      result(cameraError("BUSY", "An image picker request is already active"))
      return
    }
    guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary),
      let presenter = topViewController()
    else {
      result(cameraError("NO_VIEW_CONTROLLER", "Image picker cannot be presented"))
      return
    }
    pendingPickerResult = result
    let picker = UIImagePickerController()
    picker.sourceType = .photoLibrary
    picker.mediaTypes = ["public.image"]
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    let result = pendingPickerResult
    pendingPickerResult = nil
    picker.dismiss(animated: true) { result?(nil) }
  }

  public func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    let result = pendingPickerResult
    pendingPickerResult = nil
    guard let image = info[.originalImage] as? UIImage,
      let data = image.jpegData(compressionQuality: 1)
    else {
      picker.dismiss(animated: true) {
        result?(self.cameraError("IMAGE_DECODE_FAILED", "Selected image could not be decoded"))
      }
      return
    }
    do {
      let directory = cacheDirectory().appendingPathComponent("input", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent(
        "picked_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
      try data.write(to: file, options: .atomic)
      let value: [String: Any] = [
        "path": file.path,
        "mimeType": "image/jpeg",
        "displayName": (info[.imageURL] as? URL)?.lastPathComponent ?? file.lastPathComponent,
      ]
      picker.dismiss(animated: true) { result?(value) }
    } catch {
      picker.dismiss(animated: true) {
        result?(self.cameraError("WRITE_FAILED", error.localizedDescription))
      }
    }
  }

  private func cacheDirectory() -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("document_scanner_flutter", isDirectory: true)
  }

  private func dictionary(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
  }

  private func cameraError(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  private func topViewController(_ root: UIViewController? = nil) -> UIViewController? {
    let candidate = root ?? UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
    if let presented = candidate?.presentedViewController {
      return topViewController(presented)
    }
    if let navigation = candidate as? UINavigationController {
      return topViewController(navigation.visibleViewController)
    }
    if let tabs = candidate as? UITabBarController {
      return topViewController(tabs.selectedViewController)
    }
    return candidate
  }
}
