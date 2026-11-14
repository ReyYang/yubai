import Foundation

/// Financial dates in isolated simulator scripts stay on one day, including
/// across app relaunches. Real users and non-scripted builds use the live clock.
extension Dates {
    public static var now: Date {
        #if DEBUG && targetEnvironment(simulator)
        scriptedInstant ?? Date()
        #else
        Date()
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static let scriptedInstant = ScriptedDateClock.capture(
        arguments: ProcessInfo.processInfo.arguments,
        environment: ProcessInfo.processInfo.environment, launchedAt: Date())
    #endif
}

enum ScriptedDateClock {
    static func capture(arguments: [String], environment: [String: String], launchedAt: Date) -> Date? {
        guard let index = arguments.firstIndex(of: "--test-ledger"), arguments.indices.contains(index + 1),
              UUID(uuidString: arguments[index + 1]) != nil,
              let script = environment["YUBAI_UI_TEST_SCRIPT"], !script.isEmpty else { return nil }
        guard let raw = environment["YUBAI_UI_TEST_NOW"], let seconds = TimeInterval(raw), seconds.isFinite else { return launchedAt }
        return Date(timeIntervalSince1970: seconds)
    }
}
