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
