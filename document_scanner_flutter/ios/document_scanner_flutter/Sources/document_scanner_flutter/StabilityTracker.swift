import Foundation

struct StabilityUpdate {
  let state: String
  let progress: Double
  let stableFrames: Int64
  let shouldCapture: Bool
}

final class StabilityTracker {
  private var distanceThreshold = 50.0
  private var delayNanoseconds: UInt64 = 1_000_000_000
  private var durationNanoseconds: UInt64 = 1_000_000_000
  private var cooldownNanoseconds: UInt64 = 1_500_000_000

  private var previous: [Double]?
  private var stableSince: UInt64 = 0
  private var stableFrames: Int64 = 0
  private var cooldownUntil: UInt64 = 0
  private var capturedCurrentDocument = false

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
      let hadDocument = previous != nil
      resetCandidate()
      capturedCurrentDocument = false
      return StabilityUpdate(
        state: hadDocument ? "lost" : "searching",
        progress: 0,
        stableFrames: 0,
        shouldCapture: false)
    }

    guard let prior = previous else {
      previous = values
      stableSince = timestamp
      stableFrames = 1
      return StabilityUpdate(
        state: "detected", progress: 0, stableFrames: 1, shouldCapture: false)
    }

    previous = values
    if maximumMovement(prior, values, imageWidth, imageHeight) >= distanceThreshold {
      stableSince = timestamp
      stableFrames = 1
      capturedCurrentDocument = false
      return StabilityUpdate(
        state: "detected", progress: 0, stableFrames: 1, shouldCapture: false)
    }

    stableFrames += 1
    let total = delayNanoseconds + durationNanoseconds
    let elapsed = timestamp >= stableSince ? timestamp - stableSince : 0
    let progress = min(1, Double(elapsed) / Double(max(1, total)))
    if elapsed < total {
      return StabilityUpdate(
        state: "stabilizing",
        progress: progress,
        stableFrames: stableFrames,
        shouldCapture: false)
    }

    let shouldCapture = autoCaptureEnabled
      && !capturedCurrentDocument
      && timestamp >= cooldownUntil
    if shouldCapture { capturedCurrentDocument = true }
    return StabilityUpdate(
      state: "stable",
      progress: 1,
      stableFrames: stableFrames,
      shouldCapture: shouldCapture)
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
    stableSince = 0
    stableFrames = 0
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

  private func maximumMovement(
    _ first: [Double],
    _ second: [Double],
    _ width: Int,
    _ height: Int
  ) -> Double {
    var maximum = 0.0
    for index in 0..<4 {
      let dx = (first[index * 2] - second[index * 2]) * Double(width)
      let dy = (first[index * 2 + 1] - second[index * 2 + 1]) * Double(height)
      maximum = max(maximum, hypot(dx, dy))
    }
    return maximum
  }

  private func number(_ options: [String: Any]?, _ key: String, _ fallback: Double) -> Double {
    (options?[key] as? NSNumber)?.doubleValue ?? fallback
  }

  private func milliseconds(_ value: Double, minimum: Double) -> UInt64 {
    UInt64(max(minimum, value) * 1_000_000)
  }
}
