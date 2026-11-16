import Foundation

enum UIConditionWait {
    /// A slow first AX query must be allowed to deliver its observation. Later
    /// false observations never restart the budget; a caller deadline is hard.
    static func run(timeout: TimeInterval = 12, deadline: TimeInterval? = nil,
                    read: () -> Bool, clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    poll: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) }) -> Bool {
        let start = clock()
        var end = min(start + timeout, deadline ?? .infinity)
        var first = true
        while clock() < end {
            let satisfied = read(), now = clock()
            if let deadline, now >= deadline { return false }
            if first { first = false; end = min(now + timeout, deadline ?? .infinity) }
            else if now >= end { return false }
            if satisfied { return true }
            poll(min(0.15, max(0, end - clock())))
        }
        return false
    }
}

/// The same real completion state gates the raster proof and pixel captures.
enum UIBambooWait {
    // Run 7's first launch took ~39s and recorded a 7.7s system/dyld stall;
    // 30s did not establish completion of the two cold CoreImage renders.
    // Allow up to 90s of observation, never extending a gallery stop's budget.
    // This is a cold-runner bound, not an acceptable app rendering latency.
    static let timeout: TimeInterval = 90

    struct Result: CustomStringConvertible {
        let ready: Bool
        let observed: UIWindowMetrics.Bamboo?
        let lastReadable: UIWindowMetrics.Bamboo?
        let unreadableReads: Int
        let elapsed: TimeInterval
        var description: String {
            "bamboo {\(observed?.description ?? "diagnostics unreadable")} " +
                "unreadableReads=\(unreadableReads) elapsed=\(elapsed) " +
                (observed == nil ? "lastReadable={\(lastReadable?.description ?? "none")}" : "")
        }
    }

    static func run(timeout: TimeInterval = UIBambooWait.timeout, deadline: TimeInterval? = nil,
                    read: () -> UIWindowMetrics.Bamboo?,
                    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    poll: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) }) -> Result {
        let start = clock(), end = min(start + timeout, deadline ?? .infinity)
        var observed: UIWindowMetrics.Bamboo?, lastReadable: UIWindowMetrics.Bamboo?
        var unreadableReads = 0
        let finished = UIConditionWait.run(timeout: timeout, deadline: end, read: {
            observed = read()
            guard let value = observed else { unreadableReads += 1; return false }
            lastReadable = value
            // A failed render (even if a retry recovers), or any main-thread
            // render, fails immediately instead of spending the timeout.
            return value.hasFailure || value.isReady
        }, clock: clock, poll: poll)
        return Result(ready: finished && observed?.isReady == true, observed: observed, lastReadable: lastReadable,
                      unreadableReads: unreadableReads, elapsed: clock() - start)
    }
}
