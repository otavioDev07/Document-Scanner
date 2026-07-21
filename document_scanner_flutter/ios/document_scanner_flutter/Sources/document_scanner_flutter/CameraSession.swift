import AVFoundation
import DocumentScannerNative
import Flutter
import Foundation

struct CameraOperationError: Error {
  let code: String
  let message: String
}

final class CameraTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var latest: CVPixelBuffer?

  func update(_ pixelBuffer: CVPixelBuffer) {
    lock.lock()
    latest = pixelBuffer
    lock.unlock()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let latest else { return nil }
    return Unmanaged.passRetained(latest)
  }

  func clear() {
    lock.lock()
    latest = nil
    lock.unlock()
  }
}

final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
  AVCapturePhotoCaptureDelegate
{
  typealias EventEmitter = ([String: Any]) -> Void
  typealias CameraResult = (Result<[String: Any], CameraOperationError>) -> Void

  private let textureRegistry: FlutterTextureRegistry
  private let cacheDirectory: URL
  private let emit: EventEmitter
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "document-scanner.camera.session")
  private let videoQueue = DispatchQueue(label: "document-scanner.camera.analysis")
  private let texture = CameraTexture()
  private let photoOutput = AVCapturePhotoOutput()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let metrics = CameraMetrics()

  private var textureID: Int64?
  private var currentInput: AVCaptureDeviceInput?
  private var position: AVCaptureDevice.Position = .back
  private var options: [String: Any] = [:]
  private var stability = StabilityTracker(options: nil)
  private var autoCaptureEnabled = false
  private var diagnosticsEnabled = false
  private var active = false
  private var paused = false
  private var disposed = false
  private var lastHadDocument = false
  private var captureInFlight = false
  private var automaticCapture = false
  private var pendingCapture: CameraResult?
  private var flashMode = "off"
  private var previewWidth = 1080
  private var previewHeight = 1920

  init(
    textureRegistry: FlutterTextureRegistry,
    cacheDirectory: URL,
    emit: @escaping EventEmitter
  ) {
    self.textureRegistry = textureRegistry
    self.cacheDirectory = cacheDirectory
    self.emit = emit
    super.init()
  }

  func start(options: [String: Any]?, completion: @escaping CameraResult) {
    if disposed {
      completion(.failure(CameraOperationError(code: "DISPOSED", message: "Camera is disposed")))
      return
    }
    self.options = options ?? [:]
    autoCaptureEnabled = self.options["autoCapture"] as? Bool ?? false
    diagnosticsEnabled = self.options["diagnosticsEnabled"] as? Bool ?? false
    stability = StabilityTracker(options: self.options)
    ensureTexture()

    sessionQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.configureSession()
        if !self.session.isRunning { self.session.startRunning() }
        self.active = true
        self.paused = false
        self.metrics.reset()
        let info = self.previewInfo()
        self.emitEvent("cameraState", state: "searching", extra: [
          "cameraState": "previewing",
          "preview": info,
        ])
        DispatchQueue.main.async { completion(.success(info)) }
      } catch let error as CameraOperationError {
        DispatchQueue.main.async { completion(.failure(error)) }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(CameraOperationError(
            code: "CAMERA_START_FAILED", message: error.localizedDescription)))
        }
      }
    }
  }

  func pause() throws {
    try checkActive()
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.session.isRunning { self.session.stopRunning() }
      self.active = false
      self.paused = true
      self.stability.reset()
      self.emitEvent("cameraState", state: "lost", extra: ["cameraState": "paused"])
    }
  }

  func resume(completion: @escaping CameraResult) {
    guard paused, !disposed else {
      completion(.failure(CameraOperationError(
        code: "INVALID_STATE", message: "Camera preview is not paused")))
      return
    }
    start(options: options, completion: completion)
  }

  func switchCamera(completion: @escaping CameraResult) {
    do {
      try checkActive()
      position = position == .back ? .front : .back
      stability.reset()
      lastHadDocument = false
      start(options: options, completion: completion)
    } catch let error as CameraOperationError {
      completion(.failure(error))
    } catch {
      completion(.failure(CameraOperationError(
        code: "CAMERA_SWITCH_FAILED", message: error.localizedDescription)))
    }
  }

  func setAutoCapture(_ enabled: Bool) throws {
    try checkUsable()
    autoCaptureEnabled = enabled
    if !enabled { stability.reset() }
  }

  func setFlash(_ mode: String) throws {
    try checkActive()
    guard ["off", "auto", "on", "torch"].contains(mode) else {
      throw CameraOperationError(code: "INVALID_ARGUMENT", message: "Unknown flash mode: \(mode)")
    }
    guard let device = currentInput?.device else {
      throw CameraOperationError(code: "INVALID_STATE", message: "Camera device is unavailable")
    }
    if mode == "torch" {
      guard device.hasTorch else {
        throw CameraOperationError(code: "FLASH_UNAVAILABLE", message: "This camera has no torch")
      }
      try device.lockForConfiguration()
      device.torchMode = .on
      device.unlockForConfiguration()
    } else if device.hasTorch && device.torchMode != .off {
      try device.lockForConfiguration()
      device.torchMode = .off
      device.unlockForConfiguration()
    }
    flashMode = mode
  }

  func capture(automatic: Bool, completion: CameraResult?) {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.checkActive()
        guard !self.captureInFlight else {
          throw CameraOperationError(code: "BUSY", message: "A capture is already in progress")
        }
        self.captureInFlight = true
        self.automaticCapture = automatic
        self.pendingCapture = completion
        self.stability.onCaptured(timestamp: DispatchTime.now().uptimeNanoseconds)
        self.emitEvent("captureStarted", state: "capturing", extra: [
          "automatic": automatic
        ])
        let settings = AVCapturePhotoSettings()
        if self.photoOutput.supportedFlashModes.contains(.auto), self.position == .back {
          switch self.flashMode {
          case "auto": settings.flashMode = .auto
          case "on": settings.flashMode = .on
          default: settings.flashMode = .off
          }
        }
        self.photoOutput.capturePhoto(with: settings, delegate: self)
      } catch let error as CameraOperationError {
        DispatchQueue.main.async { completion?(.failure(error)) }
      } catch {
        DispatchQueue.main.async {
          completion?(.failure(CameraOperationError(
            code: "CAPTURE_FAILED", message: error.localizedDescription)))
        }
      }
    }
  }

  func diagnostics() -> [String: Any] { metrics.snapshot() }

  func stop() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.session.isRunning { self.session.stopRunning() }
      self.active = false
      self.paused = false
      self.removeInputsAndOutputs()
      self.stability.reset()
      self.lastHadDocument = false
      self.texture.clear()
      self.emitEvent("cameraState", state: "lost", extra: ["cameraState": "ready"])
      DispatchQueue.main.async { self.releaseTexture() }
    }
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    stop()
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard active, !disposed, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    let timestamp = DispatchTime.now().uptimeNanoseconds
    metrics.recordReceived(timestamp: timestamp)
    texture.update(pixelBuffer)
    if let textureID {
      DispatchQueue.main.async { [weak self] in
        self?.textureRegistry.textureFrameAvailable(textureID)
      }
    }

    let started = DispatchTime.now().uptimeNanoseconds
    let resizeThreshold = (options["previewResizeThreshold"] as? NSNumber)?.intValue ?? 200
    let areaFactor = (options["previewAreaScaleMinFactor"] as? NSNumber)?.doubleValue ?? 0.1
    let corners = DSNativeDocumentProcessor.detect(
      pixelBuffer,
      resizeThreshold: resizeThreshold,
      areaScaleMinFactor: areaFactor)
    let processingTime = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    metrics.recordProcessed(milliseconds: processingTime, candidate: corners != nil)
    let update = stability.update(
      corners: corners,
      imageWidth: previewWidth,
      imageHeight: previewHeight,
      timestamp: timestamp,
      autoCaptureEnabled: autoCaptureEnabled)

    if let corners {
      lastHadDocument = true
      var extra: [String: Any] = frameMetadata(update: update, processingTime: processingTime)
      extra["corners"] = corners
      emitEvent("documentDetected", state: update.state, extra: extra)
      if update.shouldCapture {
        DispatchQueue.main.async { [weak self] in self?.capture(automatic: true, completion: nil) }
      }
    } else if lastHadDocument || update.state == "lost" {
      lastHadDocument = false
      emitEvent(
        "documentLost",
        state: update.state,
        extra: frameMetadata(update: update, processingTime: processingTime))
    } else if diagnosticsEnabled && metrics.processedCount.isMultiple(of: 15) {
      emitEvent("diagnostics", state: "searching", extra: ["diagnostics": metrics.snapshot()])
    }
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let completion = pendingCapture
    let automatic = automaticCapture
    pendingCapture = nil
    captureInFlight = false
    if let error {
      let typed = CameraOperationError(code: "CAPTURE_FAILED", message: error.localizedDescription)
      emitError(typed)
      DispatchQueue.main.async { completion?(.failure(typed)) }
      return
    }
    guard let data = photo.fileDataRepresentation() else {
      let typed = CameraOperationError(code: "CAPTURE_FAILED", message: "Camera returned no image data")
      emitError(typed)
      DispatchQueue.main.async { completion?(.failure(typed)) }
      return
    }
    do {
      let directory = cacheDirectory.appendingPathComponent("camera", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("capture_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
      try data.write(to: file, options: .atomic)
      let value: [String: Any] = [
        "path": file.path,
        "mimeType": "image/jpeg",
        "displayName": file.lastPathComponent,
      ]
      emitEvent("captureCompleted", state: "detected", extra: [
        "automatic": automatic,
        "capture": value,
      ])
      DispatchQueue.main.async { completion?(.success(value)) }
    } catch {
      let typed = CameraOperationError(code: "WRITE_FAILED", message: error.localizedDescription)
      emitError(typed)
      DispatchQueue.main.async { completion?(.failure(typed)) }
    }
  }

  private func configureSession() throws {
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .photo
    removeInputsAndOutputs(configuring: true)

    guard let device = camera(position: position) else {
      throw CameraOperationError(code: "CAMERA_UNAVAILABLE", message: "Requested camera is unavailable")
    }
    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      throw CameraOperationError(code: "CAMERA_START_FAILED", message: "Cannot attach camera input")
    }
    session.addInput(input)
    currentInput = input

    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
    guard session.canAddOutput(videoOutput), session.canAddOutput(photoOutput) else {
      throw CameraOperationError(code: "CAMERA_START_FAILED", message: "Cannot attach camera outputs")
    }
    session.addOutput(videoOutput)
    session.addOutput(photoOutput)

    if let connection = videoOutput.connection(with: .video) {
      if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
      if connection.isVideoMirroringSupported {
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = false
      }
    }
    if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }
    let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    previewWidth = Int(min(dimensions.width, dimensions.height))
    previewHeight = Int(max(dimensions.width, dimensions.height))
  }

  private func camera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInDualWideCamera],
      mediaType: .video,
      position: position)
    return discovery.devices.first
  }

  private func removeInputsAndOutputs(configuring: Bool = false) {
    if !configuring { session.beginConfiguration() }
    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    for input in session.inputs { session.removeInput(input) }
    for output in session.outputs { session.removeOutput(output) }
    currentInput = nil
    if !configuring { session.commitConfiguration() }
  }

  private func ensureTexture() {
    if textureID == nil { textureID = textureRegistry.register(texture) }
  }

  private func releaseTexture() {
    if let textureID { textureRegistry.unregisterTexture(textureID) }
    textureID = nil
  }

  private func previewInfo() -> [String: Any] {
    [
      "textureId": textureID ?? -1,
      "width": previewWidth,
      "height": previewHeight,
      "rotationDegrees": 0,
      "mirrored": false,
    ]
  }

  private func frameMetadata(update: StabilityUpdate, processingTime: Double) -> [String: Any] {
    var value: [String: Any] = [
      "imageWidth": previewWidth,
      "imageHeight": previewHeight,
      "rotationDegrees": 0,
      "mirrored": false,
      "source": "camera_contour_detector",
      "stability": update.progress,
      "stableFrames": update.stableFrames,
      "processingTimeMs": processingTime,
    ]
    if diagnosticsEnabled { value["diagnostics"] = metrics.snapshot() }
    return value
  }

  private func emitEvent(_ name: String, state: String, extra: [String: Any] = [:]) {
    var value: [String: Any] = [
      "event": name,
      "state": state,
      "timestampMicros": Int64(Date().timeIntervalSince1970 * 1_000_000),
    ]
    value.merge(extra) { _, new in new }
    emit(value)
  }

  private func emitError(_ error: CameraOperationError) {
    emitEvent("error", state: "error", extra: [
      "code": error.code,
      "message": error.message,
    ])
  }

  private func checkUsable() throws {
    if disposed { throw CameraOperationError(code: "DISPOSED", message: "Camera is disposed") }
  }

  private func checkActive() throws {
    try checkUsable()
    if !active {
      throw CameraOperationError(code: "INVALID_STATE", message: "Camera preview is not active")
    }
  }
}

final class CameraMetrics {
  private let lock = NSLock()
  private var received: Int64 = 0
  private var processed: Int64 = 0
  private var candidates: Int64 = 0
  private var totalProcessingMilliseconds = 0.0
  private var started = DispatchTime.now().uptimeNanoseconds
  private var firstFrame: UInt64 = 0
  private var lastFrame: UInt64 = 0
  private var minimumDelta = UInt64.max
  private var dropped: Int64 = 0

  var processedCount: Int64 {
    lock.lock()
    defer { lock.unlock() }
    return processed
  }

  func reset() {
    lock.lock()
    received = 0
    processed = 0
    candidates = 0
    totalProcessingMilliseconds = 0
    started = DispatchTime.now().uptimeNanoseconds
    firstFrame = 0
    lastFrame = 0
    minimumDelta = UInt64.max
    dropped = 0
    lock.unlock()
  }

  func recordReceived(timestamp: UInt64) {
    lock.lock()
    received += 1
    if firstFrame == 0 { firstFrame = timestamp }
    if lastFrame > 0, timestamp > lastFrame {
      let delta = timestamp - lastFrame
      minimumDelta = min(minimumDelta, delta)
      if minimumDelta != UInt64.max, delta > minimumDelta * 3 / 2 {
        dropped += Int64(delta / minimumDelta) - 1
      }
    }
    lastFrame = timestamp
    lock.unlock()
  }

  func recordProcessed(milliseconds: Double, candidate: Bool) {
    lock.lock()
    processed += 1
    totalProcessingMilliseconds += milliseconds
    if candidate { candidates += 1 }
    lock.unlock()
  }

  func snapshot() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    let now = DispatchTime.now().uptimeNanoseconds
    let cameraSeconds = lastFrame > firstFrame ? Double(lastFrame - firstFrame) / 1_000_000_000 : 0
    let analysisSeconds = max(0.000_001, Double(now - started) / 1_000_000_000)
    return [
      "framesReceived": received,
      "framesProcessed": processed,
      "framesDropped": dropped,
      "candidatesFound": candidates,
      "cameraFps": cameraSeconds > 0 ? Double(received) / cameraSeconds : 0,
      "analysisFps": Double(processed) / analysisSeconds,
      "averageProcessingTimeMs": processed > 0 ? totalProcessingMilliseconds / Double(processed) : 0,
      "backpressureStrategy": "ALWAYS_DISCARDS_LATE_FRAMES",
    ]
  }
}
