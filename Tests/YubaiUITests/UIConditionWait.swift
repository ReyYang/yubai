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

/// Missing telemetry is unknown, not an active transition. Keep the actual
/// observation used by the gate so failure reporting never performs another
/// potentially slow query after a stop has expired.
enum UITransitionWait {
    struct Result: CustomStringConvertible {
        let settled: Bool
        let reads: Int
        let unreadableReads: Int
        let elapsed: TimeInterval
        let observed: UIWindowMetrics?
        let lastReadable: UIWindowMetrics?
        var description: String {
            func describe(_ value: UIWindowMetrics?) -> String {
                guard let value else { return "unreadable" }
                return "transitioning=\(value.transitioning) active=\(String(describing: value.activeTransitions)) focused=\(value.focused)"
            }
            return "settled=\(settled) reads=\(reads) unreadableReads=\(unreadableReads) elapsed=\(elapsed) " +
                "observed={\(describe(observed))} lastReadable={\(describe(lastReadable))}"
        }
    }
    static func run(timeout: TimeInterval = 15, deadline: TimeInterval? = nil, read: () -> UIWindowMetrics?,
                    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    poll: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) }) -> Result {
        let start = clock()
        var observed: UIWindowMetrics?, lastReadable: UIWindowMetrics?
        var reads = 0, unreadable = 0
        let settled = UIConditionWait.run(timeout: timeout, deadline: deadline, read: {
            reads += 1; observed = read()
            guard let observed else { unreadable += 1; return false }
            lastReadable = observed
            return !observed.transitioning
        }, clock: clock, poll: poll)
        return Result(settled: settled, reads: reads, unreadableReads: unreadable, elapsed: clock() - start,
                      observed: observed, lastReadable: lastReadable)
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
        let surface: UIWindowMetrics.BambooSurface?
        var description: String {
            "bamboo {\(observed?.description ?? "diagnostics unreadable")} " +
                "surface={\(surface?.description ?? "unknown")} " +
                "unreadableReads=\(unreadableReads) elapsed=\(elapsed) " +
                (observed == nil ? "lastReadable={\(lastReadable?.description ?? "none")}" : "")
        }
    }

    static func run(timeout: TimeInterval = UIBambooWait.timeout, deadline: TimeInterval? = nil,
                    read: () -> UIWindowMetrics.Bamboo?,
                    clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    poll: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) }) -> Result {
        observe(timeout: timeout, deadline: deadline, read: {
            read().map { (UIWindowMetrics.BambooSurface(required: true, key: nil), $0) }
        }, clock: clock, poll: poll)
    }

    /// Captures only require rasters when the foreground paper actually draws
    /// one. Unknown/unreadable surface metadata is retried, never a bypass.
    static func forCapture(timeout: TimeInterval = UIBambooWait.timeout, deadline: TimeInterval? = nil,
                           read: () -> UIWindowMetrics?,
                           clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                           poll: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) }) -> Result {
        observe(timeout: timeout, deadline: deadline, read: {
            guard let metrics = read() else { return nil }
            return (metrics.bambooSurface, metrics.bamboo)
        }, clock: clock, poll: poll)
    }

    private static func observe(timeout: TimeInterval, deadline: TimeInterval?,
                                read: () -> (UIWindowMetrics.BambooSurface?, UIWindowMetrics.Bamboo?)?,
                                clock: () -> TimeInterval, poll: (TimeInterval) -> Void) -> Result {
        let start = clock(), end = min(start + timeout, deadline ?? .infinity)
        var observed: UIWindowMetrics.Bamboo?, lastReadable: UIWindowMetrics.Bamboo?
        var surface: UIWindowMetrics.BambooSurface?
        var accepted = false
        var unreadableReads = 0
        let finished = UIConditionWait.run(timeout: timeout, deadline: end, read: {
            let sample = read()
            surface = sample?.0; observed = sample?.1
            if let observed { lastReadable = observed }
            guard let surface else { unreadableReads += 1; return false }
            if !surface.required { accepted = true; return true }
            guard let value = observed else { unreadableReads += 1; return false }
            // A failed render (even if a retry recovers), or any main-thread
            // render, fails immediately instead of spending the timeout.
            accepted = value.isReady && (surface.key.map { value.ready.contains($0) } ?? true)
            return value.hasFailure || accepted
        }, clock: clock, poll: poll)
        return Result(ready: finished && accepted, observed: observed, lastReadable: lastReadable,
                      unreadableReads: unreadableReads, elapsed: clock() - start, surface: surface)
    }
}
