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

/// Reviewed findings stay visible in every affected capture, only when the
/// native audit actually reports them. fixC16: the largest-size PNG shows the
/// complete fixed-amount text; the reviewed payday title is complete as well.
/// Keep the stop, element kind, identifier and full label exact. These are
/// warnings for PNG review, never an exemption for another text or audit.
enum GalleryTextReview {
    enum Kind { case button, text, other }

    static func warning(stop: String, identifier: String, label: String, kind: Kind,
                        elementDescription: String, auditText: String) -> String? {
        let reason: String
        let savingStops = ["light", "dark", "hidden", "a11y"].flatMap { mode in
            ["V47-\(mode)-Spend-Edit-Saving", "V47-\(mode)-Spend-Edit-Deficit"]
        }
        let paydayStops = ["light", "dark", "hidden"].map { "V47-\($0)-First-After-Setup" }
        if savingStops.contains(stop), kind == .button, identifier == "savingMode_fixed", label == "固定金额" {
            reason = "PNG-reviewed complete fixed-amount label at largest size"
        } else if paydayStops.contains(stop), kind == .text, identifier.isEmpty, label == "哪天发工资" {
            reason = "PNG-reviewed complete payday sheet title"
        } else { return nil }
        return stop + ": Text clipped: " + reason + "; " + elementDescription + " " + auditText
    }
}
