import Foundation

public enum Reconciliation {
    public static let unitemizedTitle = "没细记"
    public struct Gap: Equatable, Sendable { public var lastRecorded: Date; public var days: Int; public var from: Date; public var through: Date }
    public struct Row: Equatable, Sendable, Identifiable { public var id: UUID; public var name: String; public var book: Int64 }
    public struct Result: Equatable, Sendable { public var missing: Int64; public var from: Date; public var through: Date }
    public static func gap(in ledger: Ledger, now: Date, minimumDays: Int = 3) -> Gap? {
        guard let latest = ledger.entries.lazy.filter({ $0.deletedAt == nil && $0.date <= now }).map(\.date).max() else { return nil }
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
    public static func preview(_ ledger: Ledger, actual: [UUID: Int64], now: Date) -> Result {
        let gap = gap(in: ledger, now: now)
        let missing = rows(in: ledger, now: now).reduce(Int64(0)) { total, row in total + (actual[row.id].map { row.book - $0 } ?? 0) }
        return Result(missing: missing, from: gap?.from ?? Dates.day(now), through: Dates.day(now))
    }
    @discardableResult public static func apply(_ ledger: inout Ledger, actual: [UUID: Int64], now: Date) throws -> [UUID] {
        let rows = rows(in: ledger, now: now), ids = Set(rows.map(\.id))
        guard actual.keys.allSatisfy({ ids.contains($0) }), actual.values.allSatisfy({ (-Money.limit...Money.limit).contains($0) }) else {
            throw YubaiError.invalid("账户信息无效。")
        }
        let result = preview(ledger, actual: actual, now: now)
        let noon = Dates.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: result.through)!
        let date = min(noon, now.addingTimeInterval(-1))
        var next = ledger, added: [UUID] = []
        for row in rows {
            guard let value = actual[row.id] else { continue }
            if row.book != value {
                var entry = Entry(date: date, amount: abs(row.book - value), nature: row.book > value ? .expense : .adjustmentIn,
                                  accountID: row.id, title: unitemizedTitle)
                entry.spreadFrom = min(result.from, Dates.day(date)); entry.source = "对余额"
                next.entries.append(entry); added.append(entry.id)
            }
            let index = next.accounts.firstIndex { $0.id == row.id }!
            next.accounts[index].anchorBalance = value; next.accounts[index].anchorDate = now; next.accounts[index].reconciled = true
        }
        try next.validate(); ledger = next; return added
    }
}
