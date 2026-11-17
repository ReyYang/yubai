import Foundation

public struct CycleComparison: Equatable, Sendable {
    public var spent: Int64; public var previousSameDay: Int64; public var changes: [(category: String, delta: Int64)]
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spent == rhs.spent && lhs.previousSameDay == rhs.previousSameDay && lhs.changes.count == rhs.changes.count &&
        zip(lhs.changes, rhs.changes).allSatisfy { $0.category == $1.category && $0.delta == $1.delta }
    }
}
public struct WhereSpent: Equatable, Sendable {
    public var flexible: [Breakdown]; public var fixed: [Entry]; public var fixedTotal: Int64; public var unitemized: Int64
}
extension Finance {
    /// Completed periods with at least some recorded history. A missing earlier
    /// history never supplies synthetic zero months to averages.
    static func completedCycles(_ ledger: Ledger, now: Date, limit: Int) -> [DateInterval] {
        guard let earliest = ledger.entries.lazy.filter({ $0.deletedAt == nil && $0.date <= now }).map(\.date).min() else { return [] }
        var cursor = cycle(in: ledger, now: now).start, result: [DateInterval] = []
        for _ in 0..<max(0, limit) {
            guard earliest < cursor else { break }
            let previous = cycle(in: ledger, now: cursor.addingTimeInterval(-0.001))
            guard previous.start < cursor else { break }
            result.append(DateInterval(start: previous.start, end: cursor)); cursor = previous.start
        }
        return result
    }
    public static func cycleComparison(_ ledger: Ledger, now: Date) -> CycleComparison? {
        guard let previous = completedCycles(ledger, now: now, limit: 1).first else { return nil }
        let current = cycle(in: ledger, now: now)
        let days = (Dates.calendar.dateComponents([.day], from: current.start, to: Dates.day(now)).day ?? 0) + 1
        let previousEnd = min(previous.end, Dates.addDays(days, to: previous.start))
        let a = cashFlow(ledger, during: DateInterval(start: current.start, end: now.addingTimeInterval(0.001)))
        let b = cashFlow(ledger, during: DateInterval(start: previous.start, end: previousEnd))
        var deltas: [String: Int64] = [:]
        for row in a.spendingByCategory { deltas[row.category, default: 0] += row.amount }
        for row in b.spendingByCategory { deltas[row.category, default: 0] -= row.amount }
        let changes = deltas.filter { $0.value != 0 }.sorted { abs($0.value) == abs($1.value) ? $0.key < $1.key : abs($0.value) > abs($1.value) }
        return CycleComparison(spent: a.spending, previousSameDay: b.spending, changes: changes.prefix(2).map { ($0.key, $0.value) })
    }
    public static func whereSpent(_ ledger: Ledger, during interval: DateInterval) -> WhereSpent {
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        var fixed: [Entry] = [], fixedTotal: Int64 = 0, unitemized: Int64 = 0, totals: [String: (amount: Int64, count: Int)] = [:]
        for entry in ledger.entries where entry.deletedAt == nil && entry.date >= interval.start && entry.date < interval.end && (entry.nature == .expense || entry.nature == .refund) {
            let source = entry.nature == .refund ? entry.relatedEntryID.flatMap { lookup[$0] } ?? entry : entry
            let amount = spendingAmount(entry, ledger: ledger)
            if source.planID != nil || source.rentID != nil {
                fixedTotal += amount
                if entry.nature == .expense { fixed.append(entry) }
            } else if source.isUnitemized && Classification.isPending(source) { unitemized += amount }
            else {
                let category = ledger.normalizedCategory(for: entry, entriesByID: lookup).category
                totals[category, default: (0, 0)].amount += amount; totals[category, default: (0, 0)].count += 1
            }
        }
        return WhereSpent(flexible: totals.map { Breakdown(category: $0.key, amount: $0.value.amount, count: $0.value.count) }
            .sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount },
                          fixed: fixed.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }, fixedTotal: fixedTotal, unitemized: unitemized)
    }
}
public enum Setup {
    public enum Item: String, CaseIterable, Equatable, Sendable { case hand, payday, saving, bills }
    public static func done(_ ledger: Ledger, now: Date) -> Set<Item> {
        var items: Set<Item> = []
        if !ledger.accounts.isEmpty { items.insert(.hand) }
        if Finance.cycleInfo(in: ledger, now: now).known { items.insert(.payday) }
        if ledger.savingRule != nil { items.insert(.saving) }
        if ledger.plans.contains(where: { $0.active && !$0.inflow && $0.nature == .expense }) || ledger.rents.contains(where: { $0.active }) { items.insert(.bills) }
        return items
    }
}
