import Foundation

/// A completed touch sequence can precede UICollectionView's layout and the
/// probe's next cached sample. Observe actual motion before judging progress.
enum UIRevealMotionWait {
    static func run(from before: UIRevealProgress.Sample, timeout: TimeInterval = 6, deadline: TimeInterval? = nil,
                    read: () -> UIRevealProgress.Sample?, clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    poll: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) }) -> Bool {
        UIConditionWait.run(timeout: timeout, deadline: deadline, read: {
            guard let after = read() else { return false }
            if let old = before.scrollOffset, let new = after.scrollOffset, abs(new - old) > 0.5 { return true }
            if before.target == nil, after.target != nil { return true }
            if let old = before.target, let new = after.target,
               abs(new.minY - old.minY) > 0.5 || abs(new.minX - old.minX) > 0.5 { return true }
            return before.landmarks.contains { key, value in
                after.landmarks[key].map { abs($0 - value) > 0.5 } ?? false
            }
        }, clock: clock, poll: poll)
    }
}
