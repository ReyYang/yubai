import Foundation

public enum Reconciliation {
    public static let unitemizedTitle = "没细记" // Historical records retain their original meaning.
    public static let mismatchTolerance: Int64 = 100
    public static let staleDays = 30
    public struct Gap: Equatable, Sendable { public var lastRecorded: Date; public var days: Int; public var from: Date; public var through: Date }
    public struct Row: Equatable, Sendable, Identifiable { public var id: UUID; public var name: String; public var book: Int64 }
    public struct Result: Equatable, Sendable {
        public var missing: Int64; public var from: Date; public var through: Date
        public var floor: Int64
        public var spendableAfter: SpendableBreakdown
        public var changesSpendable: Bool { floor > 0 }
    }
    public struct Mismatch: Equatable, Sendable {
        public var amount: Int64
        public var lastReconciledAt: Date?
        public var stale: Bool
        public var id: String { "balanceMismatch:" + (lastReconciledAt.map { Dates.text($0) } ?? "never") }
    }
    public static func gap(in ledger: Ledger, now: Date, minimumDays: Int = 3) -> Gap? {
        guard let latest = ledger.entries.lazy.filter({ $0.deletedAt == nil && $0.kind != .adjustment && $0.date <= now }).map(\.date).max() else { return nil }
        let last = Dates.day(latest), today = Dates.day(now)
        let days = Dates.calendar.dateComponents([.day], from: last, to: today).day ?? 0
        let accounts = ledger.accounts.filter { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }
        guard days >= minimumDays, !accounts.allSatisfy({ $0.anchorDate > latest }) else { return nil }
        return Gap(lastRecorded: last, days: days, from: Dates.addDays(1, to: last), through: today)
    }
    public static func rows(in ledger: Ledger, now: Date) -> [Row] {
        ledger.accounts.filter { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }
            .map { Row(id: $0.id, name: $0.name, book: Finance.balance($0, in: ledger, at: now)) }
    }
    public static func mismatch(in ledger: Ledger, now: Date) -> Mismatch? {
        guard !rows(in: ledger, now: now).isEmpty, !ledger.entries.isEmpty else { return nil }
        let funds = Finance.funds(ledger, now: now)
        let need = max(0, funds.fixedSavingsTotal + funds.savingTarget) + funds.dueRest + funds.available
        let amount = max(0, need - (funds.cash - funds.debt))
        let last = ledger.lastReconciledAt ?? ledger.accounts.filter(\.reconciled).map(\.anchorDate).max()
        let stale = last.map { (Dates.calendar.dateComponents([.day], from: Dates.day($0), to: Dates.day(now)).day ?? 0) >= staleDays } ?? true
        if last.map({ Dates.day($0) == Dates.day(now) }) == true { return nil }
        guard amount > mismatchTolerance || stale else { return nil }
        return Mismatch(amount: amount, lastReconciledAt: last, stale: stale)
    }
    public static func preview(_ ledger: Ledger, actual: [UUID: Int64], now: Date) -> Result {
        let gap = gap(in: ledger, now: now)
        let missing = rows(in: ledger, now: now).reduce(Int64(0)) { total, row in total + (actual[row.id].map { row.book - $0 } ?? 0) }
        var projected = ledger
        projected.periodReconciliations.removeAll { abs($0.cycleStart.timeIntervalSince(Finance.cycle(in: ledger, now: now).start)) <= 36 * 3600 }
        let base = Finance.funds(projected, now: now)
        let real = base.cash - base.debt - missing
        let need = max(0, base.fixedSavingsTotal + base.savingTarget) + base.dueRest + base.available
        let floor = max(0, need - real)
        projected.periodReconciliations.append(PeriodReconciliation(cycleStart: base.cycleStart, date: now, floor: floor, entryIDs: []))
        return Result(missing: missing, from: gap?.from ?? Dates.day(now), through: Dates.day(now), floor: floor,
                      spendableAfter: Finance.spendableBreakdown(projected, now: now))
    }
    @discardableResult public static func apply(_ ledger: inout Ledger, actual: [UUID: Int64], now: Date) throws -> [UUID] {
        let rows = rows(in: ledger, now: now), ids = Set(rows.map(\.id))
        guard !actual.isEmpty, actual.keys.allSatisfy({ ids.contains($0) }), actual.values.allSatisfy({ (-Money.limit...Money.limit).contains($0) }) else { throw YubaiError.invalid("账户信息无效。") }
        let result = preview(ledger, actual: actual, now: now)
        let savedBefore = ledger.fixedSavingsTotal(now: now)
        var next = ledger, added: [UUID] = []
        for row in rows {
            guard let value = actual[row.id] else { continue }
            if row.book != value {
                var entry = Entry(date: now, amount: abs(row.book - value), nature: row.book > value ? .adjustmentOut : .adjustmentIn,
                                  accountID: row.id, title: "调整")
                entry.source = "对余额"; entry.recordedAt = now
                next.entries.append(entry); added.append(entry.id)
            }
            let index = next.accounts.firstIndex { $0.id == row.id }!
            next.accounts[index].anchorBalance = value; next.accounts[index].anchorDate = now; next.accounts[index].reconciled = true
        }
        next.setFixedSavingsTotal(savedBefore, now: now)
        let start = Finance.cycle(in: ledger, now: now).start
        next.periodReconciliations.removeAll { abs($0.cycleStart.timeIntervalSince(start)) <= 36 * 3600 }
        next.periodReconciliations.append(PeriodReconciliation(cycleStart: start, date: now, floor: result.floor, entryIDs: next.entries.filter { $0.kind == .adjustment && $0.source == "对余额" && $0.deletedAt == nil && $0.date >= start && $0.date <= now }.map(\.id)))
        next.lastReconciledAt = now; next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next; return added
    }
}
