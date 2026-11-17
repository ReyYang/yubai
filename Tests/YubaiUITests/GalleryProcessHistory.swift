import Foundation

/// Navigation and capture share one budget per stop. Xcode launch/root discovery
/// and the native audit have their own bounds; charging them here can leave the
/// first capture read with an already-expired deadline. Never renew a spent
/// budget when returning from either operation, including a failed recovery.
final class GalleryStopBudget {
    private let clock: () -> Date
    private(set) var deadline = Date.distantFuture

    init(clock: @escaping () -> Date = { Date() }) { self.clock = clock }
    func begin(_ duration: TimeInterval) { deadline = clock().addingTimeInterval(duration) }
    func end() { deadline = .distantFuture }

    func excluding<T>(_ operation: () throws -> T) rethrows -> T {
        let saved = deadline, start = clock()
        // The excluded operation still uses its existing local wait bounds,
        // including the first AX observation, without this stop's hard cap.
        deadline = .distantFuture
        defer {
            deadline = saved == .distantFuture ? saved : saved.addingTimeInterval(clock().timeIntervalSince(start))
        }
        return try operation()
    }
}

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

/// Reviewed findings stay visible in every affected capture, only when the
/// native audit actually reports them. fixC16/fixC20: the largest-size PNGs
/// show both complete texts, including the a11y payday title. Run 13's saving
/// recording also shows the selected fixed-amount label growing and stacking
/// DURING the native audit (19.0s -> 21.6s), then returning to its original size.
/// Its composite selected AX node's Dynamic Type finding is a false positive.
/// fixC34: ordinary light/dark and largest-size frequent-sheet PNGs also show
/// the complete title. ManualSheetHeader measures it at its placed width with
/// unlimited lines/height; the audit mistakes that custom title for a clip.
/// Keep the stop, category, element kind, identifier and full label exact.
enum GalleryTextReview {
    enum Kind { case button, text, other }
    enum Category { case textClipped, dynamicType, other }

    static func warning(stop: String, identifier: String, label: String, kind: Kind,
                        category: Category, selected: Bool,
                        elementDescription: String, auditText: String) -> String? {
        let reason: String
        let savingStops = ["light", "dark", "a11y"].flatMap { mode in
            ["V47-\(mode)-Spend-Edit-Saving", "V47-\(mode)-Spend-Edit-Deficit"]
        }
        let paydayStops = ["light", "dark", "a11y"].map { "V47-\($0)-First-After-Setup" }
        let frequentStops = ["light", "dark", "a11y"].map { "V47-\($0)-Empty-Frequent" }
        if savingStops.contains(stop), kind == .button, identifier == "savingMode_fixed", label == "固定金额" {
            switch category {
            case .textClipped: reason = "PNG-reviewed complete fixed-amount label at largest size"
            case .dynamicType:
                guard selected else { return nil }
                reason = "recording-reviewed selected fixed-amount label grows and stacks during live size change"
            case .other: return nil
            }
        } else if paydayStops.contains(stop), kind == .text, identifier.isEmpty, label == "哪天发工资", category == .textClipped {
            reason = "PNG-reviewed complete payday sheet title"
        } else if frequentStops.contains(stop), kind == .text, identifier.isEmpty, label == "整理常用", category == .textClipped {
            reason = "PNG-reviewed complete frequent sheet title"
        } else { return nil }
        let categoryName = category == .dynamicType ? "Dynamic Type" : "Text clipped"
        return stop + ": " + categoryName + ": " + reason + "; " + elementDescription + " " + auditText
    }
}
