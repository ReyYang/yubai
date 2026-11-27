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
        public var changesSpendable: Bool { missing != 0 && floor > 0 }
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
    private static func cashAccounts(in ledger: Ledger) -> [Account] {
        ledger.accounts.filter { !$0.archived && ($0.kind == .cash || $0.kind == .bank) }
    }
    public static func rows(in ledger: Ledger, now: Date) -> [Row] {
        cashAccounts(in: ledger).map { Row(id: $0.id, name: $0.name, book: Finance.balance($0, in: ledger, at: now)) }
    }
    public static func mismatch(in ledger: Ledger, now: Date) -> Mismatch? {
        let accounts = cashAccounts(in: ledger)
        guard !accounts.isEmpty, !ledger.entries.isEmpty else { return nil }
        // FirstUse's earliest supported anchor is a placeholder, even in
        // ledgers that marked the generated account as reconciled.
        let hasOpeningBalance = accounts.filter {
            $0.anchorBalance != 0 || ($0.reconciled && $0.anchorDate.timeIntervalSince1970 != -2_208_988_800)
        }
        if ledger.lastReconciledAt == nil && hasOpeningBalance.isEmpty { return nil }
        let funds = Finance.funds(ledger, now: now)
        // Money that must really be there: an overspend already shrank what can be saved.
        let need = max(0, funds.fixedSavingsTotal + funds.spendable.savingCovered) + funds.dueRest + funds.available
        let amount = max(0, need - funds.cash)
        let last = ledger.lastReconciledAt ?? hasOpeningBalance.filter(\.reconciled).map(\.anchorDate).max()
        let stale = last.map { (Dates.calendar.dateComponents([.day], from: Dates.day($0), to: Dates.day(now)).day ?? 0) >= staleDays } ?? false
        if last.map({ Dates.day($0) == Dates.day(now) }) == true { return nil }
        guard amount > mismatchTolerance || stale else { return nil }
        return Mismatch(amount: amount, lastReconciledAt: last, stale: stale)
    }
    public static func preview(_ ledger: Ledger, actual: [UUID: Int64], now: Date) -> Result {
        let gap = gap(in: ledger, now: now)
        let missing = rows(in: ledger, now: now).reduce(Int64(0)) { total, row in total + (actual[row.id].map { row.book - $0 } ?? 0) }
        let from = gap?.from ?? Dates.day(now)
        let before = Finance.spendableBreakdown(ledger, now: now)
        if missing == 0 {
            return Result(missing: missing, from: from, through: Dates.day(now), floor: before.balanceGap, spendableAfter: before)
        }
        var projected = ledger
        projected.periodReconciliations.removeAll { abs($0.cycleStart.timeIntervalSince(before.cycleStart)) <= 36 * 3600 }
        let base = Finance.funds(projected, now: now)
        let real = base.cash - missing
        let need = max(0, base.fixedSavingsTotal + base.spendable.savingCovered) + base.dueRest + base.available
        let floor = max(0, need - real)
        projected.periodReconciliations.append(PeriodReconciliation(cycleStart: base.cycleStart, date: now, floor: floor, entryIDs: []))
        return Result(missing: missing, from: from, through: Dates.day(now), floor: floor,
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

    @discardableResult
    public static func reconcileAccount(_ ledger: inout Ledger, accountID: UUID, actualBalance: Int64, now: Date) throws -> Entry? {
        guard let index = ledger.accounts.firstIndex(where: { $0.id == accountID && !$0.archived && $0.kind != .investment }),
              (-Money.limit...Money.limit).contains(actualBalance) else { throw YubaiError.invalid("账户信息无效。") }
        let account = ledger.accounts[index]
        var next = ledger
        var adjustment: Entry?
        switch account.kind {
        case .cash, .bank:
            let id = try apply(&next, actual: [accountID: actualBalance], now: now).first
            adjustment = id.flatMap { id in next.entries.first { $0.id == id } }
        case .credit, .receivable:
            let book = Finance.balance(account, in: ledger, at: now)
            if book != actualBalance {
                var entry = Entry(date: now, amount: abs(book - actualBalance),
                                  nature: book > actualBalance ? .adjustmentOut : .adjustmentIn,
                                  accountID: accountID, title: "调整")
                entry.source = "账户校准"
                entry.recordedAt = now
                next.entries.append(entry)
                adjustment = entry
            }
            next.accounts[index].anchorBalance = actualBalance
            next.accounts[index].anchorDate = now
            next.accounts[index].reconciled = true
            next.updatedAt = max(next.updatedAt, now)
        case .investment:
            throw YubaiError.invalid("账户信息无效。")
        }
        for index in next.cards.indices where next.cards[index].action == .reconcileAccount(accountID) {
            if next.cards[index].dismissedAt == nil { next.cards[index].dismissedAt = now }
        }
        try next.validate()
        ledger = next
        return adjustment
    }

    @discardableResult
    public static func revalueInvestment(_ ledger: inout Ledger, accountID: UUID, newValue: Int64, now: Date) throws -> Int64 {
        guard let index = ledger.accounts.firstIndex(where: { $0.id == accountID && !$0.archived && $0.kind == .investment }),
              (0...Money.limit).contains(newValue) else { throw YubaiError.invalid("投资金额无效。") }
        let previous = Finance.balance(ledger.accounts[index], in: ledger, at: now)
        var next = ledger
        next.accounts[index].anchorBalance = newValue
        next.accounts[index].anchorDate = now
        next.accounts[index].reconciled = true
        next.updatedAt = max(next.updatedAt, now)
        try next.validate()
        ledger = next
        return newValue - previous
    }

}
