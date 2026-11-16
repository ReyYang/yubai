import Foundation

/// XCTest can deliver an app's crash issue after another fixture has launched.
/// Keep the last stop that owned each process, even after intentional relaunch.
struct GalleryProcessHistory {
    private struct Death {
        let run: Int
        let stop: String
        var reported = false
    }
    private(set) var run = 0
    private var owner: String?
    private var deaths: [Death] = []
    var hasUnreportedDeath: Bool { deaths.contains { !$0.reported } }

    mutating func launched(in stop: String?) { run += 1; owner = stop }
    mutating func enterStop(_ stop: String) { if run > 0 { owner = stop } }
    mutating func observeStopped() -> String? {
        guard run > 0, let owner, !deaths.contains(where: { $0.run == run }) else { return nil }
        deaths.append(Death(run: run, stop: owner))
        return owner
    }
    mutating func crashOwner(fallback: String?) -> String? {
        if let index = deaths.firstIndex(where: { !$0.reported }) {
            deaths[index].reported = true
            return deaths[index].stop
        }
        return owner ?? fallback
    }
}
