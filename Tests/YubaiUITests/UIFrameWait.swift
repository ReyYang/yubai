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
                // Never extend the deadline for a missing/moving control, and
                // never accept a read returned after the observation deadline.
                if now >= end { break }
                if let frame, let previous,
                   abs(frame.minX - previous.minX) < 0.1, abs(frame.minY - previous.minY) < 0.1,
                   abs(frame.width - previous.width) < 0.1, abs(frame.height - previous.height) < 0.1 {
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
