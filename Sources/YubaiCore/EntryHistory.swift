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
