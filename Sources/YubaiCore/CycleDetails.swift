import Foundation

public struct ClosedFormula: Equatable, Sendable {
    public var cycleStart: Date; public var cycleEnd: Date
    /// Residual opening cash, absorbing non-spending changes and missing history.
    public var hand: Int64
    public var income: Int64
    public var fixedSavings: Int64
    public var saving: Int64
    public var bills: Int64
    public var spent: Int64
    public var remaining: Int64
}
public struct CategoryCycleSpending: Equatable, Sendable, Identifiable {
    public var id: Date { cycleStart }
    public var cycleStart: Date; public var cycleEnd: Date; public var through: Date
    public var amount: Int64; public var count: Int
}
public struct CategoryPlace: Equatable, Sendable, Identifiable {
    public var id: String; public var title: String; public var count: Int; public var amount: Int64
}
public struct CategoryDetail: Equatable, Sendable {
    public var category: String
    /// Current cycle first, then earlier cycles at the same day offset.
    public var cycles: [CategoryCycleSpending]
    public var frequentPlaces: [CategoryPlace]
    public var entries: [Entry]
}
extension Finance {
    /// Half-open periods, newest first. Includes saved history with no surviving entries.
    public static func pastCycles(_ ledger: Ledger, now: Date, limit: Int = 120) -> [DateInterval] {
        let count = min(2400, max(0, limit))
        let current = cycle(in: ledger, now: now).start
        var result = ledger.savingHistory.filter { $0.cycleEnd < current }.map {
            DateInterval(start: $0.cycleStart, end: Dates.addDays(1, to: $0.cycleEnd))
        }
        for interval in completedCycles(ledger, now: now, limit: count) {
            if !result.contains(where: { $0.start < interval.end && interval.start < $0.end }) { result.append(interval) }
        }
        return Array(result.sorted { $0.start > $1.start }.prefix(count))
    }
    /// Pass a start from pastCycles. Stored settlement amounts take precedence;
    /// other rows are retrospective estimates from the surviving ledger.
    public static func closedFormula(_ ledger: Ledger, cycleStart: Date) -> ClosedFormula {
        let record = ledger.savingHistory.first { abs($0.cycleStart.timeIntervalSince(cycleStart)) <= 36 * 3600 }
        let cycle = self.cycle(in: ledger, now: cycleStart)
        let start = record?.cycleStart ?? cycle.start, end = record?.cycleEnd ?? cycle.end
        let close = Dates.addDays(1, to: end).addingTimeInterval(-0.001)
        var snapshot = WeeklyLetter.snapshot(ledger, at: close)
        // Later actual confirmations define boundaries, while Funds excludes
        // future postings from all amounts.
        snapshot.entries = ledger.entries
        let funds = self.funds(snapshot, now: close)
        snapshot.entries = ledger.entries.filter { $0.date <= close }
        let interval = DateInterval(start: start, end: Dates.addDays(1, to: end))
        let flow = whereSpent(snapshot, during: interval)
        let lookup = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.id, $0) })
        let spent = snapshot.entries.filter { $0.deletedAt == nil && $0.date >= start && $0.date <= close }
            .reduce(Int64(0)) { $0 + SpendingParts.flexibleAmount($1, in: snapshot, entriesByID: lookup) }
        let saving = record?.saved ?? max(0, min(funds.savingTarget, funds.savingTarget + funds.available))
        let derivedRemaining = funds.available + funds.savingTarget - saving
        // unspent is clamped to zero for the first-batch leftover prompt. A
        // deficit beyond all saving still belongs in the closed formula.
        let remaining = record?.unspent.map { $0 > 0 ? $0 : min(0, derivedRemaining) } ?? derivedRemaining
        let bills = flow.fixedTotal + funds.committed
        let fixed = funds.emergency
        return ClosedFormula(cycleStart: start, cycleEnd: end, hand: fixed + saving + bills + spent + remaining,
                             income: record?.income ?? funds.cycleIncome, fixedSavings: fixed, saving: saving,
                             bills: bills, spent: spent, remaining: remaining)
    }
    public static func categoryDetail(_ ledger: Ledger, category: String, now: Date, previousCycles: Int = 3) -> CategoryDetail {
        let current = cycle(in: ledger, now: now)
        let offset = max(0, Dates.calendar.dateComponents([.day], from: current.start, to: Dates.day(now)).day ?? 0)
        let category = ledger.resolveCategory(category, income: false)
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let rows = ledger.entries.filter { entry in
            guard entry.deletedAt == nil, entry.date <= now, entry.nature == .expense || entry.nature == .refund else { return false }
            let source = entry.relatedEntryID.flatMap { lookup[$0] } ?? entry
            if category == Reconciliation.unitemizedTitle { return source.isUnitemized && Classification.isPending(source) }
            return ledger.normalizedCategory(for: entry, entriesByID: lookup).category == category
        }
        let currentRows = rows.filter { $0.date >= current.start }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
        func summary(start: Date, end: Date, through: Date, entries: [Entry]) -> CategoryCycleSpending {
            CategoryCycleSpending(cycleStart: start, cycleEnd: end, through: through,
                amount: entries.reduce(0) { $0 + spendingAmount($1, ledger: ledger) }, count: entries.filter { $0.nature == .expense }.count)
        }
        var cycles = [summary(start: current.start, end: current.end, through: Dates.day(now), entries: currentRows)]
        for interval in pastCycles(ledger, now: now, limit: max(0, previousCycles)) {
            let through = min(Dates.addDays(offset + 1, to: interval.start), interval.end)
            cycles.append(summary(start: interval.start, end: Dates.addDays(-1, to: interval.end), through: Dates.addDays(-1, to: through),
                                  entries: rows.filter { $0.date >= interval.start && $0.date < through }))
        }
        var places: [String: CategoryPlace] = [:]
        for entry in currentRows {
            let original = entry.nature == .refund ? entry.relatedEntryID.flatMap { lookup[$0] } ?? entry : entry
            let title = original.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = CategoryMemory.key(title)
            var place = places[key] ?? CategoryPlace(id: key, title: title, count: 0, amount: 0)
            if entry.nature == .expense { place.count += 1 }
            place.amount += spendingAmount(entry, ledger: ledger); places[key] = place
        }
        return CategoryDetail(category: category, cycles: cycles,
            frequentPlaces: places.values.sorted { $0.count == $1.count ? ($0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount) : $0.count > $1.count },
            entries: currentRows)
    }
}
