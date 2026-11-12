import Foundation

/// Suggestions use recorded choices only. Text is an equality key, never a keyword classifier.
public enum EntryHistory {
    public struct Recall: Identifiable, Equatable, Sendable {
        public var id: String { purpose }
        public let purpose: String
        public let entry: Entry
        public let count: Int
    }
    public static func recentPurposes(in ledger: Ledger, nature: Nature, now: Date = Date(), limit: Int = 6) -> [Recall] {
        let rows = ledger.entries.filter { $0.deletedAt == nil && $0.nature == nature && $0.date <= now }
        let names = Set(ledger.categories.flatMap { [$0.name] + $0.subcategories } + [Classification.pendingCategory, "没分类"])
        let groups = Dictionary(grouping: rows.filter { !purpose($0).isEmpty && !names.contains(purpose($0)) }, by: purpose)
        return groups.map { key, rows in
            Recall(purpose: key, entry: rows.max(by: older)!, count: rows.count)
        }.sorted {
            // A recent single use can outrank a much older repeated use.
            let a = score($0, now: now); let b = score($1, now: now)
            if a != b { return a > b }
            if $0.entry.date != $1.entry.date { return $0.entry.date > $1.entry.date }
            return $0.purpose < $1.purpose
        }.prefix(max(0, limit)).map { $0 }
    }
    public static func suggestion(purpose text: String, nature: Nature, in ledger: Ledger, at now: Date = Date(),
                                  calendar: Calendar = Dates.calendar) -> CategoryAssignment? {
        guard nature != .transfer else { return nil }
        let rows = ledger.entries.filter { $0.deletedAt == nil && $0.nature == nature && $0.date <= now }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        func assignment(_ entry: Entry) -> CategoryAssignment? {
            let value = ledger.normalizedCategory(for: entry)
            guard ledger.selectableCategories.contains(where: { $0.name == value.category && $0.income == (nature != .refund && nature.inflow) }) else { return nil }
            return value
        }
        // The last matching entry is authoritative, including an unsorted choice.
        if !clean.isEmpty, let last = rows.filter({ purpose($0) == clean }).max(by: older) { return assignment(last) }
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let window = rows.filter {
            let value = calendar.component(.hour, from: $0.date) * 60 + calendar.component(.minute, from: $0.date)
            let distance = abs(value - minute)
            return min(distance, 1440 - distance) <= 120
        }.filter { assignment($0) != nil }
        let groups = Dictionary(grouping: window, by: { assignment($0)!.category })
        let winner = groups.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            let a = $0.value.max(by: older)!; let b = $1.value.max(by: older)!
            if a.date != b.date { return a.date > b.date }
            return $0.key < $1.key
        }.first
        return winner.map { CategoryAssignment(category: $0.key) }
    }
    private static func purpose(_ entry: Entry) -> String { (entry.purpose ?? entry.title).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func older(_ a: Entry, _ b: Entry) -> Bool {
        if a.date != b.date { return a.date < b.date }
        if a.recordedAt != b.recordedAt { return (a.recordedAt ?? a.date) < (b.recordedAt ?? b.date) }
        return a.id.uuidString < b.id.uuidString
    }
    private static func score(_ recall: Recall, now: Date) -> Double {
        Double(recall.count) / (1 + max(0, now.timeIntervalSince(recall.entry.date)) / (30 * 86_400))
    }
}

public enum RecentlyDeleted {
    public static func cutoff(now: Date = Date(), calendar: Calendar = Dates.calendar) -> Date {
        calendar.date(byAdding: .day, value: -30, to: now)!
    }
    public static func entries(in ledger: Ledger, now: Date = Date(), calendar: Calendar = Dates.calendar) -> [Entry] {
        let cutoff = cutoff(now: now, calendar: calendar)
        return ledger.entries.filter { $0.deletedAt.map { $0 > cutoff } ?? false }.sorted {
            if $0.deletedAt != $1.deletedAt { return $0.deletedAt! > $1.deletedAt! }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    public static func daysRemaining(_ entry: Entry, now: Date = Date(), calendar: Calendar = Dates.calendar) -> Int {
        guard let deleted = entry.deletedAt, let end = calendar.date(byAdding: .day, value: 30, to: deleted) else { return 0 }
        return max(0, Int(ceil(end.timeIntervalSince(now) / 86_400)))
    }
    public static func restore(_ id: UUID, in ledger: inout Ledger, now: Date = Date(), calendar: Calendar = Dates.calendar) throws {
        guard let index = ledger.entries.firstIndex(where: { $0.id == id }),
              let deleted = ledger.entries[index].deletedAt, deleted > cutoff(now: now, calendar: calendar) else {
            throw YubaiError.invalid("这笔已清掉")
        }
        ledger.entries[index].deletedAt = nil
    }
    @discardableResult public static func purge(in ledger: inout Ledger, now: Date = Date(), calendar: Calendar = Dates.calendar) -> Int {
        let cutoff = cutoff(now: now, calendar: calendar); let count = ledger.entries.count
        ledger.entries.removeAll { $0.deletedAt.map { $0 <= cutoff } ?? false }
        return count - ledger.entries.count
    }
    public static func clear(in ledger: inout Ledger) { ledger.entries.removeAll { $0.deletedAt != nil } }
}

extension EntryHistory {
    public static func categoryHint(purpose text: String, nature: Nature, in ledger: Ledger, now: Date) -> CategoryAssignment? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, nature != .transfer else { return nil }
        let rows = Array(ledger.entries.filter { $0.deletedAt == nil && $0.nature == nature && $0.date <= now && purpose($0) == clean }
            .sorted { older($1, $0) }.prefix(3))
        guard !rows.isEmpty else { return CategoryGuesser.guess(clean, nature: nature, in: ledger) }
        let assignments = rows.map { ledger.normalizedCategory(for: $0) }
        let winner = assignments.first { choice in assignments.filter { $0 == choice }.count >= (rows.count == 1 ? 1 : 2) }
        guard let winner, ledger.selectableCategories.contains(where: { $0.name == winner.category && $0.income == nature.categoryIncome }) else { return nil }
        return winner
    }
    public static func recalls(matching text: String, nature: Nature, in ledger: Ledger, now: Date, limit: Int = 4) -> [Recall] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(recentPurposes(in: ledger, nature: nature, now: now, limit: ledger.entries.count)
            .filter { clean.isEmpty || $0.purpose.range(of: clean, options: .caseInsensitive) != nil }.prefix(max(0, limit)))
    }
    public struct Repeat: Codable, Equatable, Sendable, Identifiable {
        public var id: String; public var purpose: String; public var amount: Int64
        public var category: String; public var subcategory: String?; public var accountID: UUID
    }
    public struct HiddenRepeat: Equatable, Sendable, Identifiable {
        public let id: String
        public let entry: Repeat?
        public let purpose: String?
        public let amount: Int64?
        init(id: String, entry: Repeat?) {
            self.id = id; self.entry = entry
            let legacy = entry == nil ? Self.legacyDisplayData(id) : nil
            purpose = entry?.purpose ?? legacy?.purpose; amount = entry?.amount ?? legacy?.amount
        }
        private static func legacyDisplayData(_ id: String) -> (purpose: String, amount: Int64)? {
            // The name length counts UTF-8 bytes, and the name itself may contain colons.
            let bytes = Array(id.utf8)
            guard let separator = bytes.firstIndex(of: 58),
                  let count = Int(String(decoding: bytes[..<separator], as: UTF8.self)),
                  count > 0, count < bytes.count - separator - 1 else { return nil }
            let start = separator + 1, end = start + count
            guard bytes[end] == 58, let purpose = String(bytes: bytes[start..<end], encoding: .utf8) else { return nil }
            let tail = String(decoding: bytes[(end + 1)...], as: UTF8.self).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard tail.count == 2, !tail[1].isEmpty, let amount = Int64(tail[0]), (1...Money.limit).contains(amount) else { return nil }
            return (purpose, amount)
        }
    }
    public static func hiddenRepeats(in ledger: Ledger, now: Date) -> [HiddenRepeat] {
        let automatic = Dictionary(uniqueKeysWithValues: automaticRepeats(in: ledger, now: now).map { ($0.id, $0) })
        return (ledger.repeatPreferences ?? []).filter { $0.hidden == true }.map {
            HiddenRepeat(id: $0.id, entry: $0.snapshot ?? automatic[$0.id])
        }
    }
    public static func repeats(in ledger: Ledger, now: Date, limit: Int = 3) -> [Repeat] {
        let preferences = ledger.repeatPreferences ?? []
        let hidden = Set(preferences.filter { $0.hidden == true }.map(\.id))
        let automatic = automaticRepeats(in: ledger, now: now)
        let lookup = Dictionary(uniqueKeysWithValues: automatic.map { ($0.id, $0) })
        let maintained = preferences.filter { !hidden.contains($0.id) }.compactMap { lookup[$0.id] ?? $0.pinned }
        let seen = Set(maintained.map(\.id)).union(hidden)
        return Array((maintained + automatic.filter { !seen.contains($0.id) }).prefix(max(0, limit)))
    }
    private static func automaticRepeats(in ledger: Ledger, now: Date) -> [Repeat] {
        let from = Dates.addDays(-30, to: now)
        let rows = ledger.entries.filter { $0.deletedAt == nil && $0.nature == .expense && $0.recordedAt != nil && $0.batchID == nil && $0.date >= from && $0.date <= now && $0.planID == nil && $0.rentID == nil && !purpose($0).isEmpty }
        func key(_ entry: Entry) -> String {
            let name = purpose(entry), category = ledger.normalizedCategory(for: entry).category
            return "\(name.utf8.count):\(name):\(entry.amount):\(category)"
        }
        return Dictionary(grouping: rows, by: key).filter { $0.value.count >= 2 }.sorted {
            let a = $0.value.max(by: older)!, b = $1.value.max(by: older)!
            let aScore = Double($0.value.count) / max(1, now.timeIntervalSince(a.date) / 86_400)
            let bScore = Double($1.value.count) / max(1, now.timeIntervalSince(b.date) / 86_400)
            return aScore == bScore ? $0.key < $1.key : aScore > bScore
        }.map { id, rows in
            let entry = rows.max(by: older)!, assignment = ledger.normalizedCategory(for: entry)
            return Repeat(id: id, purpose: purpose(entry), amount: entry.amount, category: assignment.category,
                          subcategory: assignment.subcategory, accountID: entry.accountID)
        }
    }
}
