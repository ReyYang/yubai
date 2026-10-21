import Foundation

/// View lifetimes do not reset first-appearance motion during this process.
struct MotionSessionState {
    private var seen: Set<String> = []
    func contains(_ key: String) -> Bool { seen.contains(key) }
    @discardableResult mutating func claim(_ key: String) -> Bool { seen.insert(key).inserted }
    static func direction(from: Int, to: Int) -> Double { to == from ? 0 : (to > from ? 1 : -1) }
}

struct MotionEntryChange {
    let saved: Set<UUID>
    let deleted: Set<UUID>
    init(previous: [UUID], previousActive: [UUID], currentActive: [UUID]) {
        saved = Set(currentActive).subtracting(previous)
        deleted = Set(previousActive).subtracting(currentActive)
    }
}
