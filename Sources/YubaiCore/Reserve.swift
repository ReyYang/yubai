import Foundation

public struct CycleCover: Codable, Equatable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable { case saveLess, fromReserve }
    public var id: UUID; public var cycleStart: Date; public var date: Date; public var source: Source; public var amount: Int64
    public init(id: UUID = UUID(), cycleStart: Date, date: Date, source: Source, amount: Int64) {
        self.id = id; self.cycleStart = cycleStart; self.date = date; self.source = source; self.amount = amount
    }
}
public struct ReserveAdjustment: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID; public var date: Date; public var delta: Int64
    public init(id: UUID = UUID(), date: Date, delta: Int64) { self.id = id; self.date = date; self.delta = delta }
}
extension Ledger {
    func reserveSpent(now: Date) -> Int64 {
        var spent: [UUID: Int64] = [:], refunded: [UUID: Int64] = [:]
        for entry in entries where entry.deletedAt == nil && entry.date <= now {
            if entry.nature == .expense && entry.fromReserve { spent[entry.id] = entry.amount }
            if entry.nature == .refund, let id = entry.relatedEntryID { refunded[id, default: 0] += entry.amount }
        }
        return spent.reduce(0) { $0 + $1.value - min($1.value, refunded[$1.key, default: 0]) }
    }
    func reserveCovered(now: Date) -> Int64 {
        cycleCovers.filter { $0.source == .fromReserve && $0.date <= now }.reduce(0) { $0 + $1.amount }
    }
    func effectiveSavingTarget(_ rule: Int64, cycleStart: Date, now: Date) -> Int64 {
        max(0, rule - cycleCovers.filter { $0.source == .saveLess && $0.date <= now && abs($0.cycleStart.timeIntervalSince(cycleStart)) <= 36 * 3600 }
            .reduce(0) { $0 + $1.amount })
    }
}
public enum Overspend {
    public struct Options: Equatable, Sendable {
        public var overBy: Int64; public var daysLeft: Int; public var level: Int64; public var cushion: Int64
        public var maxSaveLess: Int64; public var maxFromReserve: Int64
    }
    public struct Preview: Equatable, Sendable {
        public var before: Int64; public var after: Int64; public var availableAfter: Int64; public var dailyAfter: Int64?
    }
    public static func options(_ ledger: Ledger, now: Date) -> Options? {
        let funds = Finance.funds(ledger, now: now)
        guard funds.available < 0 else { return nil }
        let pace = Finance.pace(ledger, now: now)
        let days = max(1, funds.horizonDays + 1), over = -funds.available
        return Options(overBy: over, daysLeft: days, level: over, cushion: over + Int64(days) * (pace?.baseDaily ?? 0),
                       maxSaveLess: funds.savingTarget, maxFromReserve: max(0, ledger.fixedSavingsTotal(now: now)))
    }
    public static func preview(_ ledger: Ledger, source: CycleCover.Source, amount: Int64, now: Date) -> Preview {
        let funds = Finance.funds(ledger, now: now)
        let before = source == .saveLess ? funds.savingTarget : ledger.fixedSavingsTotal(now: now)
        var projected = ledger
        projected.cycleCovers.append(CycleCover(cycleStart: funds.cycleStart, date: now, source: source, amount: amount))
        return Preview(before: before, after: before - amount, availableAfter: Finance.funds(projected, now: now).available,
                       dailyAfter: Finance.pace(projected, now: now)?.daily)
    }
    public static func cover(_ ledger: inout Ledger, source: CycleCover.Source, amount: Int64, now: Date) throws {
        let funds = Finance.funds(ledger, now: now)
        let maximum = source == .saveLess ? funds.savingTarget : ledger.fixedSavingsTotal(now: now)
        guard amount > 0, amount <= Money.limit, amount <= maximum else {
            throw YubaiError.invalid(source == .fromReserve ? "存着的钱不够。" : "攒钱的金额或周期无效。")
        }
        var next = ledger
        next.cycleCovers.append(CycleCover(cycleStart: funds.cycleStart, date: now, source: source, amount: amount))
        try next.validate(); ledger = next
    }
}
public struct BigPurchase: Equatable, Sendable {
    public var days: Int; public var availableAfter: Int64; public var dailyAfter: Int64?; public var tight: Bool
    public var reserveBefore: Int64; public var reserveAfter: Int64; public var canUseReserve: Bool
}
extension Finance {
    public static func bigPurchase(_ ledger: Ledger, amount: Int64, now: Date) -> BigPurchase? {
        let pace = pace(ledger, now: now)
        let ref = (pace?.baseDaily ?? 0) > 0 ? pace!.baseDaily : estimatedDailyLiving(ledger, now: now)
        guard ref > 0, amount > 7 * ref else { return nil }
        let after = funds(ledger, now: now).available - amount, daily = pace?.dailyAfterSpending(amount)
        let reserve = ledger.fixedSavingsTotal(now: now)
        return BigPurchase(days: Int((Double(amount) / Double(ref)).rounded()), availableAfter: after, dailyAfter: daily,
                           tight: after < 0 || (daily ?? 0) < ref / 2, reserveBefore: reserve,
                           reserveAfter: reserve - amount, canUseReserve: amount <= reserve)
    }
}
public struct ReserveLine: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case monthly(cycleStart: Date, pending: Bool), leftover, income(UUID), purchase(UUID), cover(UUID), adjust }
    // Structural rows use kind for the App's labels; title carries an original
    // entry's displayTitle. Core does not duplicate those presentation strings.
    public var id: String; public var date: Date; public var title: String; public var amount: Int64; public var kind: Kind
}
public struct ReserveOverview: Equatable, Sendable {
    public var total: Int64; public var setAside: Int64; public var lines: [ReserveLine]
}
public enum Reserve {
    public static func overview(_ ledger: Ledger, now: Date) -> ReserveOverview {
        let funds = Finance.funds(ledger, now: now)
        let setAside = funds.savingTarget
        var lines: [ReserveLine] = []
        for cycle in ledger.savingHistory {
            let key = String(cycle.cycleStart.timeIntervalSince1970)
            if cycle.saved != 0 {
                lines.append(ReserveLine(id: "monthly:" + key, date: cycle.cycleStart, title: "", amount: cycle.saved,
                                         kind: .monthly(cycleStart: cycle.cycleStart, pending: false)))
            }
            if cycle.leftover != 0 {
                lines.append(ReserveLine(id: "leftover:" + key, date: Dates.addDays(1, to: cycle.cycleEnd), title: "", amount: cycle.leftover, kind: .leftover))
            }
        }
        if setAside > 0 {
            lines.append(ReserveLine(id: "pending", date: funds.cycleStart, title: "", amount: setAside,
                                     kind: .monthly(cycleStart: funds.cycleStart, pending: true)))
        }
        let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
        let reserveIDs = Set(ledger.entries.filter { $0.deletedAt == nil && $0.fromReserve }.map(\.id))
        for entry in ledger.entries where entry.deletedAt == nil && entry.date <= now {
            if entry.nature == .income, entry.intoFixedSavings, let account = accounts[entry.accountID],
               account.kind == .cash || account.kind == .bank, account.includes(entry, posting: entry.postingDate(for: account.id)) {
                lines.append(ReserveLine(id: "income:" + entry.id.uuidString, date: entry.date, title: entry.displayTitle, amount: entry.amount, kind: .income(entry.id)))
            }
            if entry.fromReserve {
                lines.append(ReserveLine(id: "purchase:" + entry.id.uuidString, date: entry.date, title: entry.displayTitle, amount: -entry.amount, kind: .purchase(entry.id)))
            } else if entry.nature == .refund, let original = entry.relatedEntryID, reserveIDs.contains(original) {
                lines.append(ReserveLine(id: "refund:" + entry.id.uuidString, date: entry.date, title: entry.displayTitle, amount: entry.amount, kind: .purchase(original)))
            }
        }
        for cover in ledger.cycleCovers where cover.source == .fromReserve && cover.date <= now {
            lines.append(ReserveLine(id: "cover:" + cover.id.uuidString, date: cover.date, title: "", amount: -cover.amount, kind: .cover(cover.id)))
        }
        for adjustment in ledger.reserveAdjustments where adjustment.date <= now {
            lines.append(ReserveLine(id: "adjust:" + adjustment.id.uuidString, date: adjustment.date, title: "", amount: adjustment.delta, kind: .adjust))
        }
        return ReserveOverview(total: ledger.fixedSavingsTotal(now: now) + setAside, setAside: setAside,
                               lines: lines.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date })
    }
    public static func setTotal(_ total: Int64, in ledger: inout Ledger, now: Date) {
        let before = ledger.fixedSavingsTotal(now: now)
        ledger.setFixedSavingsTotal(total, now: now)
        let delta = ledger.fixedSavingsTotal(now: now) - before
        if delta != 0 { ledger.reserveAdjustments.append(ReserveAdjustment(date: now, delta: delta)) }
    }
    public static func suggestedMonthly(_ ledger: Ledger, now: Date) -> (average: Int64, suggestion: Int64)? {
        let cycles = Finance.completedCycles(ledger, now: now, limit: 3)
        guard !cycles.isEmpty else { return nil }
        let total = cycles.reduce(Int64(0)) { total, interval in
            let flow = Finance.cashFlow(ledger, during: interval)
            return total + flow.income - flow.spending
        }
        let average = total / Int64(cycles.count)
        return (average, max(0, average) / 10_000 * 10_000)
    }
}
