import Foundation

public struct RepeatPreference: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var pinned: EntryHistory.Repeat?
    public var hidden: Bool?
    public init(id: String, pinned: EntryHistory.Repeat? = nil, hidden: Bool? = nil) {
        self.id = id; self.pinned = pinned; self.hidden = hidden == true ? true : nil
    }
    private enum CodingKeys: String, CodingKey { case id, pinned, hidden }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pinned = try c.decodeIfPresent(EntryHistory.Repeat.self, forKey: .pinned)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) == true ? true : nil
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encodeIfPresent(pinned, forKey: .pinned)
        if hidden == true { try c.encode(true, forKey: .hidden) }
    }
}
extension EntryHistory {
    public static func setPinned(_ repeatEntry: Repeat, pinned: Bool, in ledger: inout Ledger) throws {
        var preferences = ledger.repeatPreferences ?? []
        let index = preferences.firstIndex { $0.id == repeatEntry.id }
        var row = index.map { preferences[$0] } ?? RepeatPreference(id: repeatEntry.id)
        row.pinned = pinned ? repeatEntry : nil
        if pinned { row.hidden = nil }
        if let index { preferences[index] = row } else { preferences.insert(row, at: 0) }
        try save(preferences, in: &ledger)
    }
    public static func setHidden(_ repeatEntry: Repeat, hidden: Bool, in ledger: inout Ledger) throws {
        var preferences = ledger.repeatPreferences ?? []
        let index = preferences.firstIndex { $0.id == repeatEntry.id }
        var row = index.map { preferences[$0] } ?? RepeatPreference(id: repeatEntry.id)
        row.hidden = hidden ? true : nil
        if hidden { row.pinned = nil }
        if let index { preferences[index] = row } else { preferences.append(row) }
        try save(preferences, in: &ledger)
    }
    /// Ordered rows are pinned too, so maintenance survives the rolling 30-day window.
    public static func reorder(_ repeats: [Repeat], in ledger: inout Ledger) throws {
        guard Set(repeats.map(\.id)).count == repeats.count else { throw YubaiError.invalid("记录信息无效。") }
        let ids = Set(repeats.map(\.id))
        let preferences = repeats.map { RepeatPreference(id: $0.id, pinned: $0) } + (ledger.repeatPreferences ?? []).filter { !ids.contains($0.id) }
        try save(preferences, in: &ledger)
    }
    private static func save(_ preferences: [RepeatPreference], in ledger: inout Ledger) throws {
        var next = ledger
        let rows = preferences.filter { $0.pinned != nil || $0.hidden == true }
        next.repeatPreferences = rows.isEmpty ? nil : rows
        try next.validate(); ledger = next
    }
    static func validateRepeatPreferences(in ledger: Ledger) throws {
        let rows = ledger.repeatPreferences ?? []
        guard rows.count <= 1000, Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ row in
                  guard !row.id.isEmpty, row.id.count <= 5000 else { return false }
                  guard let entry = row.pinned else { return true }
                  return row.id == entry.id && !entry.purpose.isEmpty && entry.purpose.count <= 4000 &&
                      (1...Money.limit).contains(entry.amount) && ledger.accounts.contains { $0.id == entry.accountID }
              }) else { throw YubaiError.invalid("记录信息无效。") }
    }
}
