import Foundation

/// One read per sample. Snapshot latency is not part of the initial settling
/// budget: it starts when the first valid frame has actually been delivered.
enum UIFrameWait {
    struct Sample {
        let elapsed: TimeInterval
        let frame: CGRect?
    }
    struct Result {
        let stable: Bool
        let samples: [Sample]
        var frame: CGRect? { samples.last?.frame }
        var description: String {
            let reads = samples.map { String(format: "%.3fs", $0.elapsed) + " " + ($0.frame.map(String.init(describing:)) ?? "<no valid frame>") }
            return "Stable frame: \(stable); \(samples.count) reads\n" + reads.joined(separator: "\n")
        }
    }

    static func run(timeout: TimeInterval = 12, deadline: TimeInterval? = nil,
                    read: () -> CGRect?, clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    poll: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) }) -> Result {
        let start = clock()
        var end = min(start + timeout, deadline ?? .infinity)
        var firstRead = true
        var previous: CGRect?
        var samples: [Sample] = []
        func equal(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 0.1 && abs(a.minY - b.minY) < 0.1 &&
            abs(a.width - b.width) < 0.1 && abs(a.height - b.height) < 0.1
        }
        func allReadsAgree() -> Bool {
            guard samples.count >= 2, let first = samples.first?.frame else { return false }
            return samples.allSatisfy { $0.frame.map { equal(first, $0) } ?? false }
        }
        while clock() < end {
            let raw = read(), now = clock()
            let frame = raw.flatMap { rect -> CGRect? in
                guard !rect.isEmpty, !rect.isNull, !rect.isInfinite,
                      rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
                return rect
            }
            samples.append(Sample(elapsed: now - start, frame: frame))
            if let frame, firstRead {
                firstRead = false
                end = min(now + timeout, deadline ?? .infinity)
                previous = frame
            } else {
                // A slow snapshot can finish after sampling has ended. All
                // observations must agree in that case; two matching tail
                // reads cannot erase an earlier missing or moving frame.
                if now >= end {
                    let withinCallerDeadline = deadline.map { now < $0 } ?? true
                    return Result(stable: withinCallerDeadline && allReadsAgree(), samples: samples)
                }
                if let frame, let previous, equal(frame, previous) {
                    return Result(stable: true, samples: samples)
                }
                previous = frame
            }
            let remaining = end - clock()
            if remaining > 0 { poll(min(0.15, remaining)) }
        }
        return Result(stable: false, samples: samples)
    }
}
