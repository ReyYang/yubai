import Foundation

public struct SpendingDerivation: Equatable, Sendable {
    public var salary: Entry?
    public var income: Int64
    public var otherFunds: Int64
    public var fixedSavings: Int64
    public var creditDebt: Int64
    public var goals: Int64
    public var uncertainInflow: Int64
    public var saving: Int64
    public var yearlySetAside: Int64 = 0
    public var bills: Int64
    public var billNames: [String]
    public var budget: Int64
    public var spent: Int64
    public var entryIDs: [UUID]
    public var available: Int64
    public var daily: Int64?
    public var cycleEnd: Date = .distantPast
    public var daysLeft: Int = 0
    public var billCount: Int = 0
    /// Opening spendable funds plus posted income, after the existing protected
    /// balances. Absorbs balance anchors and savings transfers exactly once.
    public var exerciseIncome: Int64 = 0
    public var exerciseResult: Int64 { exerciseIncome - saving - bills - yearlySetAside - spent }
    public var interval: DateInterval
}

extension Finance {
    /// The residual opening row absorbs transfers, balance anchors and other
    /// movements. The displayed derivation remains an identity for every ledger.
    public static func spendingDerivation(_ ledger: Ledger, now: Date) -> SpendingDerivation {
        let funds = funds(ledger, now: now), formula = formula(ledger, now: now)
        let entries = ledger.activeEntries.filter { $0.date >= funds.cycleStart && $0.date <= now }
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let flexible = entries.filter { SpendingParts.flexibleAmount($0, in: ledger, entriesByID: lookup) != 0 }
        let spent = flexible.reduce(Int64(0)) { $0 + SpendingParts.flexibleAmount($1, in: ledger, entriesByID: lookup) }
        let income = funds.cycleIncome
        let paid = entries.filter { $0.nature == .expense && ($0.planID != nil || $0.rentID != nil) }.reduce(Int64(0)) { $0 + $1.amount }
        let bills = funds.committed + paid
        let budget = funds.available + spent
        let residual = budget + funds.savingTarget + funds.yearlySetAside + bills + funds.debt + funds.goals + funds.uncertainInflow + funds.fixedSavingsTotal - income
        let salary = entries.filter { entry in
            guard entry.nature == .income, !entry.intoFixedSavings else { return false }
            return entry.category == "工资" || entry.title.contains("工资") || entry.planID == Finance.anchorPlan(in: ledger, now: now)?.id
        }.max { $0.date < $1.date }
        return SpendingDerivation(salary: salary, income: income, otherFunds: residual, fixedSavings: funds.fixedSavingsTotal,
                                  creditDebt: funds.debt, goals: funds.goals, uncertainInflow: funds.uncertainInflow,
                                  saving: funds.savingTarget, yearlySetAside: funds.yearlySetAside, bills: bills, billNames: formula.bills.map(\.title), budget: budget,
                                  spent: spent, entryIDs: flexible.map(\.id), available: funds.available, daily: pace(ledger, now: now)?.daily,
                                  cycleEnd: funds.cycleEnd, daysLeft: pace(ledger, now: now)?.daysLeft ?? max(1, funds.horizonDays + 1),
                                  billCount: Set(formula.bills.map(\.title)).count,
                                  exerciseIncome: funds.cash - funds.debt - funds.fixedSavingsTotal - funds.goals - funds.uncertainInflow + paid + spent,
                                  interval: DateInterval(start: funds.cycleStart, end: min(now.addingTimeInterval(0.001), Dates.addDays(1, to: funds.cycleEnd))))
    }
}
