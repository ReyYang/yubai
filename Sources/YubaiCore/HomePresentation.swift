import Foundation

/// Presentation facts for the home page. Unknown income is never a negative budget.
public struct HomeHero: Equatable, Sendable {
    public var isFirstOpen: Bool
    public var hasSalaryPlan: Bool
    public var title: String
    public var amount: Int64
    public static func make(_ ledger: Ledger, now: Date) -> Self {
        let known = Finance.anchorPlan(in: ledger, now: now) != nil
        let funds = Finance.funds(ledger, now: now)
        let month = Dates.calendar.dateInterval(of: .month, for: now)!.start
        let spent = Finance.cashFlow(ledger, during: DateInterval(start: month, end: now.addingTimeInterval(0.001))).spending
        return Self(isFirstOpen: ledger.entries.isEmpty, hasSalaryPlan: known,
                    title: known ? (funds.available < 0 ? "多花了" : "还能花") : "这个月花了",
                    amount: known ? abs(funds.available) : max(0, spent))
    }
}

public struct SalarySetupDeferral: Codable, Equatable, Sendable {
    public var deferredAt: Date
    public var postedIncomeIDs: Set<UUID>
    public init(deferredAt: Date, postedIncomeIDs: Set<UUID>) {
        self.deferredAt = deferredAt; self.postedIncomeIDs = postedIncomeIDs
    }
    private enum CodingKeys: String, CodingKey { case deferredAt, postedIncomeIDs }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(deferredAt, forKey: .deferredAt)
        try c.encode(postedIncomeIDs.sorted { $0.uuidString < $1.uuidString }, forKey: .postedIncomeIDs)
    }
    public var askAgainOn: Date {
        let month = Dates.calendar.dateInterval(of: .month, for: deferredAt)!.start
        return Dates.addDays(9, to: Dates.addMonths(1, to: month))
    }
}

extension FirstUse {
    public static func salaryPromptDue(_ ledger: Ledger, now: Date) -> Bool {
        guard !ledger.entries.isEmpty, Finance.anchorPlan(in: ledger, now: now) == nil else { return false }
        guard let deferred = ledger.salarySetupDeferral else { return true }
        return now >= deferred.askAgainOn || ledger.activeEntries.contains {
            $0.nature == .income && $0.date <= now && !deferred.postedIncomeIDs.contains($0.id)
        }
    }
    public static func deferSalarySetup(_ ledger: inout Ledger, now: Date) {
        ledger.salarySetupDeferral = SalarySetupDeferral(deferredAt: now, postedIncomeIDs: Set(
            ledger.activeEntries.filter { $0.nature == .income && $0.date <= now }.map(\.id)))
    }
}

public struct HomeSavingCard: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case notStarted
        case monthly(Int64)
        case wish(id: UUID, title: String, shortfall: Int64, progress: Double)
    }
    public var total: Int64
    public var state: State
    public var started: Bool { state != .notStarted }
    public static func make(_ ledger: Ledger, now: Date) -> Self {
        let total = max(0, Reserve.overview(ledger, now: now).total)
        guard ledger.savingRule != nil || total > 0 || !ledger.savingHistory.isEmpty else {
            return Self(total: total, state: .notStarted)
        }
        // Closest to being funded first; stable ties do not shuffle on redraw.
        let wishes = ledger.wishlist.filter { $0.status == .thinking && $0.amount > 0 }.sorted {
            if $0.amount != $1.amount { return $0.amount < $1.amount }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        if let wish = wishes.first {
            return Self(total: total, state: .wish(id: wish.id, title: wish.title,
                shortfall: max(0, wish.amount - total), progress: min(1, Double(total) / Double(wish.amount))))
        }
        return Self(total: total, state: .monthly(Finance.funds(ledger, now: now).savingRuleTarget))
    }
}

/// One receipt per local day, with a total over every row, including hidden rows.
public struct DailyReceipt: Equatable, Sendable {
    public var day: Date
    public var entries: [Entry]
    public var count: Int
    public var total: Int64
    public var omittedCount: Int { max(0, count - entries.count) }
    public static func make(_ ledger: Ledger, now: Date) -> Self {
        let today = Dates.day(now)
        let rows = ledger.activeEntries.filter { $0.date <= now && Dates.day($0.date) == today }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            let a = $0.recordedAt ?? $0.date, b = $1.recordedAt ?? $1.date
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
        return Self(day: today, entries: Array(rows.suffix(6)), count: rows.count,
                    total: rows.reduce(0) { $0 + Finance.spendingAmount($1, ledger: ledger) })
    }
}

public struct HomeEntryFeedback: Equatable, Sendable {
    public var highlightedIDs: Set<UUID>
    public var needsToast: Bool
    public static func make(savedIDs: Set<UUID>, fromHome: Bool, ledger: Ledger, now: Date) -> Self {
        let saved = ledger.activeEntries.filter { savedIDs.contains($0.id) }
        let today = fromHome ? Set(saved.filter { $0.date <= now && Dates.day($0.date) == Dates.day(now) }.map(\.id)) : []
        return Self(highlightedIDs: today, needsToast: saved.contains { !today.contains($0.id) })
    }
}
