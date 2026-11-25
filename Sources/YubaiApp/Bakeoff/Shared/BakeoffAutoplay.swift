#if DEBUG && os(iOS)
  import QuartzCore
  import UIKit

  /// The display link only supplies finger translations. The screens own all spring motion.
  @MainActor final class BakeoffAutoplay {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-YubaiBakeoffAutoplay")

    enum Input {
      case tap(String), grab, drag(CGFloat), release(CGFloat), reopen, reset
    }

    // Grab returns the current presentation offset. Other inputs return zero.
    typealias Send = (Input) -> CGFloat
    private let send: Send
    private var link: CADisplayLink?
    private var sample: ((CFTimeInterval) -> Void)?
    private var completion: CheckedContinuation<Void, Never>?

    init(send: @escaping Send) { self.send = send }

    private struct Cycle: Codable {
      let amountInputEnd, firstRelease, secondGrab, secondRelease, reopen, reset: TimeInterval
      let regrabOffset: CGFloat
    }

    private struct Receipt: Codable {
      let pid: Int32
      let start, end: TimeInterval
      let cycles: [Cycle]
      let batteryStates: [Int]
      let lowPower: [Bool]
    }

    func run() async {
      guard Self.enabled else { return }
      let device = UIDevice.current
      let monitored = device.isBatteryMonitoringEnabled
      let idleDisabled = UIApplication.shared.isIdleTimerDisabled
      device.isBatteryMonitoringEnabled = true
      UIApplication.shared.isIdleTimerDisabled = true
      defer {
        device.isBatteryMonitoringEnabled = monitored
        UIApplication.shared.isIdleTimerDisabled = idleDisabled
      }
      do {
        try await Task.sleep(for: .seconds(1.5))
        let start = Date.now.timeIntervalSince1970
        var cycles: [Cycle] = []
        var battery = [device.batteryState.rawValue]
        var power = [ProcessInfo.processInfo.isLowPowerModeEnabled]
        for _ in 0..<4 {
          for key in ["1", "2", "8", ".", "5"] {
            _ = send(.tap("bakeoff.key." + key))
            try await Task.sleep(for: .milliseconds(120))
          }
          let amountInputEnd = Date.now.timeIntervalSince1970
          for type in ["1", "2", "0"] {
            _ = send(.tap("bakeoff.type." + type))
            try await Task.sleep(for: .milliseconds(300))
          }
          _ = send(.grab)
          try await drag(distance: BakeoffSpec.mainHeight / 2, duration: 0.65, slowsToRest: true)
          let firstRelease = Date.now.timeIntervalSince1970
          _ = send(.release(0))
          try await Task.sleep(for: .milliseconds(140))
          let secondGrab = Date.now.timeIntervalSince1970
          let regrabOffset = send(.grab)
          let distance = BakeoffSpec.mainHeight * 0.62
          try await drag(distance: distance, duration: 0.52, slowsToRest: false)
          let secondRelease = Date.now.timeIntervalSince1970
          _ = send(.release(distance / 0.52))
          try await Task.sleep(for: .milliseconds(600))
          let reopen = Date.now.timeIntervalSince1970
          _ = send(.reopen)
          try await Task.sleep(for: .seconds(1))
          _ = send(.reset)
          cycles.append(Cycle(amountInputEnd: amountInputEnd, firstRelease: firstRelease,
                              secondGrab: secondGrab, secondRelease: secondRelease, reopen: reopen,
                              reset: Date.now.timeIntervalSince1970, regrabOffset: regrabOffset))
          battery.append(device.batteryState.rawValue)
          power.append(ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        let receipt = Receipt(pid: ProcessInfo.processInfo.processIdentifier, start: start,
                              end: Date.now.timeIntervalSince1970, cycles: cycles,
                              batteryStates: battery, lowPower: power)
        try JSONEncoder().encode(receipt).write(
          to: FileManager.default.temporaryDirectory.appendingPathComponent("bakeoff-autoplay.json"),
          options: .atomic)
      } catch is CancellationError {
        return
      } catch {
        NSLog("Bakeoff autoplay: %@", error.localizedDescription)
      }
    }

    private func drag(distance: CGFloat, duration: Double, slowsToRest: Bool) async throws {
      try Task.checkCancellation()
      let start = CACurrentMediaTime()
      await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
          completion = continuation
          sample = { [weak self] timestamp in
            guard let self else { return }
            let t = min(1, max(0, (timestamp - start) / duration))
            let fraction = slowsToRest ? t * (2 - t) : t
            _ = send(.drag(distance * fraction))
            if t >= 1 { finishDrag() }
          }
          let displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
          link = displayLink
          displayLink.add(to: .main, forMode: .common)
        }
      } onCancel: {
        Task { @MainActor in self.finishDrag() }
      }
      try Task.checkCancellation()
    }

    @objc private func tick(_ displayLink: CADisplayLink) { sample?(displayLink.timestamp) }

    private func finishDrag() {
      link?.invalidate()
      link = nil
      sample = nil
      completion?.resume()
      completion = nil
    }
  }
#endif
