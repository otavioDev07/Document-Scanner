import Foundation

struct StabilityUpdate {
  let state: String
  let progress: Double
  let stableFrames: Int64
  let shouldCapture: Bool
  let corners: [[String: NSNumber]]?

  init(
    state: String,
    progress: Double,
    stableFrames: Int64,
    shouldCapture: Bool,
    corners: [[String: NSNumber]]? = nil
  ) {
    self.state = state
    self.progress = progress
    self.stableFrames = stableFrames
    self.shouldCapture = shouldCapture
    self.corners = corners
  }
}

final class StabilityTracker {
  private var distanceThreshold = 50.0
  private var delayNanoseconds: UInt64 = 1_000_000_000
  private var durationNanoseconds: UInt64 = 1_000_000_000
  private var cooldownNanoseconds: UInt64 = 1_500_000_000

  private var previous: [Double]?
  private var displayed: [Double]?
  private var pendingMovement: [Double]?
  private var stableSince: UInt64 = 0
  private var stableFrames: Int64 = 0
  private var cooldownUntil: UInt64 = 0
  private var capturedCurrentDocument = false
  private var lastDetectedAt: UInt64 = 0

  // A single failed frame is common with a live camera. Keep the current
  // overlay briefly so the document border does not flash on and off.
  private let lostDetectionGraceNanoseconds: UInt64 = 250_000_000

  init(options: [String: Any]?) {
    updateOptions(options)
  }

  func updateOptions(_ options: [String: Any]?) {
    distanceThreshold = number(options, "autoCaptureDistanceThreshold", distanceThreshold)
    delayNanoseconds = milliseconds(
      number(options, "autoCaptureDelayMs", Double(delayNanoseconds) / 1_000_000),
      minimum: 0)
    durationNanoseconds = milliseconds(
      number(options, "autoCaptureDurationMs", Double(durationNanoseconds) / 1_000_000),
      minimum: 1)
    cooldownNanoseconds = milliseconds(
      number(options, "autoCaptureCooldownMs", Double(cooldownNanoseconds) / 1_000_000),
      minimum: 0)
  }

  func update(
    corners: [[String: NSNumber]]?,
    imageWidth: Int,
    imageHeight: Int,
    timestamp: UInt64,
    autoCaptureEnabled: Bool
  ) -> StabilityUpdate {
    guard let values = flattened(corners) else {
      if previous != nil,
        timestamp >= lastDetectedAt,
        timestamp - lastDetectedAt <= lostDetectionGraceNanoseconds
      {
        return progressUpdate(
          timestamp: timestamp,
          autoCaptureEnabled: autoCaptureEnabled,
          allowCapture: false)
      }
      let hadDocument = previous != nil
      resetCandidate()
      capturedCurrentDocument = false
      return StabilityUpdate(
        state: hadDocument ? "lost" : "searching",
        progress: 0,
        stableFrames: 0,
        shouldCapture: false)
    }

    lastDetectedAt = timestamp

    guard let prior = previous else {
      previous = values
      displayed = values
      stableSince = timestamp
      stableFrames = 1
      return StabilityUpdate(
        state: "detected",
        progress: 0,
        stableFrames: 1,
        shouldCapture: false,
        corners: mapped(displayed))
    }

    if maximumMovement(prior, values, imageWidth, imageHeight) >= distanceThreshold {
      if let pendingMovement,
        maximumMovement(pendingMovement, values, imageWidth, imageHeight) < distanceThreshold
      {
        // Two consecutive, mutually close frames represent real movement.
        // A single distant contour is detector noise and must not reset the
        // progress.
        previous = values
        displayed = smoothed(displayed, toward: values)
        self.pendingMovement = nil
        stableSince = timestamp
        stableFrames = 1
        capturedCurrentDocument = false
        return StabilityUpdate(
          state: "detected",
          progress: 0,
          stableFrames: 1,
          shouldCapture: false,
          corners: mapped(displayed))
      }
      pendingMovement = values
      return progressUpdate(
        timestamp: timestamp,
        autoCaptureEnabled: autoCaptureEnabled,
        allowCapture: false)
    }

    pendingMovement = nil
    previous = values
    displayed = smoothed(displayed, toward: values)
    stableFrames += 1
    return progressUpdate(
      timestamp: timestamp,
      autoCaptureEnabled: autoCaptureEnabled,
      allowCapture: true)
  }

  private func progressUpdate(
    timestamp: UInt64,
    autoCaptureEnabled: Bool,
    allowCapture: Bool
  ) -> StabilityUpdate {
    let elapsed = timestamp >= stableSince ? timestamp - stableSince : 0
    if elapsed < delayNanoseconds {
      return StabilityUpdate(
        state: "detected",
        progress: 0,
        stableFrames: stableFrames,
        shouldCapture: false,
        corners: mapped(displayed ?? previous))
    }

    let scanningElapsed = elapsed - delayNanoseconds
    let progress = min(1, Double(scanningElapsed) / Double(max(1, durationNanoseconds)))
    if scanningElapsed < durationNanoseconds {
      return StabilityUpdate(
        state: "stabilizing",
        progress: progress,
        stableFrames: stableFrames,
        shouldCapture: false,
        corners: mapped(displayed ?? previous))
    }

    let shouldCapture = allowCapture
      && autoCaptureEnabled
      && !capturedCurrentDocument
      && timestamp >= cooldownUntil
    if shouldCapture { capturedCurrentDocument = true }
    return StabilityUpdate(
      state: "stable",
      progress: 1,
      stableFrames: stableFrames,
      shouldCapture: shouldCapture,
      corners: mapped(displayed ?? previous))
  }

  func onCaptured(timestamp: UInt64) {
    cooldownUntil = timestamp + cooldownNanoseconds
    capturedCurrentDocument = true
  }

  func reset() {
    resetCandidate()
    cooldownUntil = 0
    capturedCurrentDocument = false
  }

  private func resetCandidate() {
    previous = nil
    displayed = nil
    pendingMovement = nil
    stableSince = 0
    stableFrames = 0
    lastDetectedAt = 0
  }

  private func flattened(_ corners: [[String: NSNumber]]?) -> [Double]? {
    guard let corners, corners.count == 4 else { return nil }
    var values: [Double] = []
    for point in corners {
      guard let x = point["x"]?.doubleValue, let y = point["y"]?.doubleValue else {
        return nil
      }
      values.append(x)
      values.append(y)
    }
    return values
  }

  private func mapped(_ values: [Double]?) -> [[String: NSNumber]]? {
    guard let values, values.count == 8 else { return nil }
    return stride(from: 0, to: values.count, by: 2).map { index in
      [
        "x": NSNumber(value: values[index]),
        "y": NSNumber(value: values[index + 1]),
      ]
    }
  }

  private func smoothed(_ current: [Double]?, toward target: [Double]) -> [Double] {
    guard let current, current.count == target.count else { return target }
    let factor = 0.20
    return zip(current, target).map { source, destination in
      source + (destination - source) * factor
    }
  }

  private func maximumMovement(
    _ first: [Double],
    _ second: [Double],
    _ width: Int,
    _ height: Int
  ) -> Double {
    // Preserve AutoScanHandler's iOS matching rule. It intentionally tracks
    // one inward-facing axis per ordered corner, which ignores contour jitter
    // along the document edges while still resetting for real movement.
    return max(
      abs(first[0] - second[0]) * Double(width),
      abs(first[3] - second[3]) * Double(height),
      abs(first[4] - second[4]) * Double(width),
      abs(first[7] - second[7]) * Double(height)
    )
  }

  private func number(_ options: [String: Any]?, _ key: String, _ fallback: Double) -> Double {
    (options?[key] as? NSNumber)?.doubleValue ?? fallback
  }

  private func milliseconds(_ value: Double, minimum: Double) -> UInt64 {
    UInt64(max(minimum, value) * 1_000_000)
  }
}
