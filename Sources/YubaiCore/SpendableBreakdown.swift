import Foundation

public struct SpendableRow: Equatable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case income, carry, saving, bills, spent, withdrawal, balanceGap }
    public var kind: Kind
    public var id: String { kind.rawValue }
    /// Signed contribution to the worked exercise; saving uses its effective amount.
    public var amount: Int64
    public var originalAmount: Int64
    public var entryIDs: [UUID] = []
    public var occurrences: [Occurrence] = []
    public var transferIDs: [UUID] = []
    public var coverIDs: [UUID] = []
    public var accountIDs: [UUID] = []
    public var paybackIDs: [UUID] = []
    public var historyIDs: [Date] = []
    public var setting: SavingRule? = nil
    public var date: Date? = nil
    public var title: String {
        switch kind { case .income: "本期收入"; case .carry: "上期留下"; case .saving: "要攒"; case .bills: "还要付"; case .spent: "已经花了"; case .withdrawal: "拿出来用"; case .balanceGap: "余额差额" }
    }
}

public struct SpendableBreakdown: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case normal
        case savingLess(Int64)
        case deficit(amount: Int64, bill: Occurrence?)
        case spentFallback
    }
    public struct WaterBar: Equatable, Sendable {
        public var fill: Double
        public var tick: Double
        public var fast: Bool
    }
    public var cycleStart: Date
    public var cycleEnd: Date
    public var asOf: Date = .distantPast
    public var rows: [SpendableRow]
    public var state: State
    /// R before the automatic saving buffer. Use available/headlineAmount for display.
    public var rawR: Int64
    public var income: Int64
    public var carry: Int64
    public var plannedSaving: Int64
    public var effectiveSaving: Int64
    public var billsRest: Int64
    public var spent: Int64
    public var withdrawal: Int64
    public var balanceGap: Int64
    public var headlineAmount: Int64
    public var waterBar: WaterBar?
    public var bills: [FixedFlowOccurrence] = []
    public var incoming: [Occurrence] = []
    public var available: Int64 { max(0, rawR) }
    public var savingLess: Int64 { min(plannedSaving, max(0, -rawR)) }
    public var deficit: Int64 { max(0, -rawR - plannedSaving) }
    public var offersFormula: Bool { state != .spentFallback }
    public var headlineTitle: String {
        switch state { case .deficit: "缺口"; case .spentFallback: "这个月花了"; default: "还能花" }
    }
    public var daysTotal: Int { max(1, (Dates.calendar.dateComponents([.day], from: cycleStart, to: cycleEnd).day ?? 0) + 1) }
    public var daysLeft: Int { max(1, (Dates.calendar.dateComponents([.day], from: Dates.day(asOf), to: cycleEnd).day ?? 0) + 1) }
    public var interval: DateInterval { DateInterval(start: cycleStart, end: Dates.addDays(1, to: cycleEnd)) }
    public var billCount: Int { rows.first { $0.kind == .bills }?.occurrences.count ?? 0 }
    public var billsPaid: Int { bills.filter { $0.state == .paid }.count }
    public var saving: Int64 { effectiveSaving }
    public var savingRuleTarget: Int64 { plannedSaving }
    static let empty = Self(cycleStart: .distantPast, cycleEnd: .distantPast, rows: [], state: .spentFallback,
                            rawR: 0, income: 0, carry: 0, plannedSaving: 0, effectiveSaving: 0, billsRest: 0,
                            spent: 0, withdrawal: 0, balanceGap: 0, headlineAmount: 0)
}

extension Finance {
    public static func spendableBreakdown(_ ledger: Ledger, now: Date = Dates.now) -> SpendableBreakdown { funds(ledger, now: now).spendable }

    static func plannedSaving(in ledger: Ledger, income: Int64, cycleStart: Date, now: Date) -> Int64 {
        let rule = (ledger.savingRule?.target(income: income) ?? 0) +
            Reserve.paybackAmounts(ledger, cycleStart: cycleStart, now: now).reduce(0) { $0 + $1.amount }
        return ledger.effectiveSavingTarget(rule, cycleStart: cycleStart, now: now)
    }

    static func makeSpendableBreakdown(_ ledger: Ledger, now: Date, cycle: CycleInfo, commitments: [Occurrence]) -> SpendableBreakdown {
        let entries = ledger.entries.filter { $0.deletedAt == nil && $0.date >= cycle.start && $0.date <= now }
        let incomeEntries = entries.filter { $0.kind != .adjustment && $0.nature == .income && !$0.intoFixedSavings }
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let expenseEntries = entries.filter { entry in
            guard entry.kind != .adjustment, entry.nature == .expense || entry.nature == .refund else { return false }
            let source = entry.nature == .refund ? entry.relatedEntryID.flatMap { lookup[$0] } ?? entry : entry
            return !source.fromReserve
        }
        let income = incomeEntries.reduce(Int64(0)) { $0 + $1.amount }
        let spent = expenseEntries.reduce(Int64(0)) { $0 + spendingAmount($1, ledger: ledger) }
        let transfers = ledger.savingsTransfers.filter { $0.date >= cycle.start && $0.date <= now }
        let covers = ledger.cycleCovers.filter { $0.date >= cycle.start && $0.date <= now && $0.source == .fromReserve }
        let withdrawal = transfers.reduce(Int64(0)) { $0 + ($1.direction == .take ? $1.amount : -$1.amount) } + covers.reduce(0) { $0 + $1.amount }
        let carries = ledger.carryReleases.filter { $0.date >= cycle.start && $0.date <= now }
        let carry = carries.reduce(Int64(0)) { $0 + $1.amount }
        // Existing explicit save-less decisions and releases retain their meaning.
        let planned = plannedSaving(in: ledger, income: income, cycleStart: cycle.start, now: now)
        // The portion released from a pending target is already represented by the
        // smaller saving row; count only the settled-money portion as an inflow.
        let released = transfers.filter { $0.direction == .take }.reduce(Int64(0)) { $0 + $1.fromSetAside }
        let netWithdrawal = withdrawal - released
        let bills = commitments.reduce(Int64(0)) { $0 + $1.amount }
        let reconciliation = ledger.periodReconciliations.last { abs($0.cycleStart.timeIntervalSince(cycle.start)) <= 36 * 3600 && $0.date <= now }
        let gap = reconciliation?.floor ?? 0
        let raw = income + carry - planned - bills - spent + netWithdrawal - gap
        let effective = max(0, planned - max(0, -raw))
        let deficit = max(0, -raw - planned)
        let known = anchorPlan(in: ledger, now: now) != nil && income > 0
        let state: SpendableBreakdown.State = !known ? .spentFallback : deficit > 0 ? .deficit(amount: deficit, bill: commitments.first) : raw < 0 ? .savingLess(-raw) : .normal
        let totalDays = max(1, (Dates.calendar.dateComponents([.day], from: cycle.start, to: cycle.end).day ?? 0) + 1)
        let elapsed = (Dates.calendar.dateComponents([.day], from: cycle.start, to: Dates.day(now)).day ?? 0) + 1
        let elapsedDays = min(totalDays, max(0, elapsed))
        let tick = Double(elapsedDays) / Double(totalDays)
        let freeTotal = raw + spent
        let fill = freeTotal > 0 ? min(1, max(0, Double(spent) / Double(freeTotal))) : spent > 0 || raw < 0 ? 1.0 : 0.0
        let fast = fill >= 1 || (freeTotal > 0 && spent > 0 && Decimal(spent) * Decimal(totalDays) * 20 > Decimal(freeTotal) * (Decimal(elapsedDays) * 20 + Decimal(totalDays) * 3))
        var rows = [SpendableRow(kind: .income, amount: income, originalAmount: income, entryIDs: incomeEntries.map(\.id))]
        if carry != 0 { rows.append(SpendableRow(kind: .carry, amount: carry, originalAmount: carry, historyIDs: carries.map(\.sourceCycleStart), date: carries.last?.date)) }
        if planned != 0 { rows.append(SpendableRow(kind: .saving, amount: -effective, originalAmount: planned, transferIDs: transfers.filter { $0.fromSetAside > 0 }.map(\.id), coverIDs: ledger.cycleCovers.filter { $0.source == .saveLess && $0.cycleStart == cycle.start && $0.date <= now }.map(\.id), paybackIDs: Reserve.paybackAmounts(ledger, cycleStart: cycle.start, now: now).map(\.id), setting: ledger.savingRule)) }
        if bills != 0 { rows.append(SpendableRow(kind: .bills, amount: -bills, originalAmount: bills, occurrences: commitments)) }
        rows.append(SpendableRow(kind: .spent, amount: -spent, originalAmount: spent, entryIDs: expenseEntries.map(\.id)))
        if netWithdrawal != 0 { rows.append(SpendableRow(kind: .withdrawal, amount: netWithdrawal, originalAmount: withdrawal, transferIDs: transfers.map(\.id), coverIDs: covers.map(\.id), date: transfers.last?.date ?? covers.last?.date)) }
        if gap != 0 { rows.append(SpendableRow(kind: .balanceGap, amount: -gap, originalAmount: gap, entryIDs: reconciliation?.entryIDs ?? [], accountIDs: ledger.accounts.filter { $0.kind == .bank || $0.kind == .cash }.map(\.id), date: reconciliation?.date)) }
        return SpendableBreakdown(cycleStart: cycle.start, cycleEnd: cycle.end, asOf: now, rows: rows, state: state, rawR: raw,
            income: income, carry: carry, plannedSaving: planned, effectiveSaving: effective, billsRest: bills, spent: spent,
            withdrawal: netWithdrawal, balanceGap: gap, headlineAmount: !known ? max(0, spent) : deficit > 0 ? deficit : max(0, raw),
            waterBar: known ? .init(fill: fill, tick: tick, fast: fast) : nil)
    }
}

extension Finance {
    /// Bill drill-down and the formula use the same period result.
    public static func formula(_ ledger: Ledger, now: Date) -> SpendableBreakdown {
        var value = spendableBreakdown(ledger, now: now)
        var cursor = Dates.calendar.dateInterval(of: .month, for: value.cycleStart)!.start
        while cursor < value.interval.end {
            value.bills += FixedFlows.month(containing: cursor, in: ledger, asOf: now).occurrences.filter {
                !$0.inflow && $0.date >= value.cycleStart && $0.date < value.interval.end
            }
            cursor = Dates.addMonths(1, to: cursor)
        }
        let shown = Set(value.bills.map(\.id))
        for bill in value.rows.first(where: { $0.kind == .bills })?.occurrences ?? [] where !shown.contains(bill.id) {
            value.bills.append(FixedFlowOccurrence(id: bill.id, title: bill.title, date: bill.date,
                state: Dates.day(bill.date) <= Dates.day(now) ? .due : .upcoming, amount: bill.amount,
                planID: bill.planID, rentID: bill.rentID, inflow: false, autoPay: false, installment: nil, estimated: false))
        }
        value.bills.sort { ($0.state == .paid) != ($1.state == .paid) ? $0.state != .paid : $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        value.incoming = occurrences(in: ledger, now: now, days: max(1, (Dates.calendar.dateComponents([.day], from: Dates.day(now), to: value.cycleEnd).day ?? 0) + 1)).filter { $0.inflow && Dates.day($0.date) <= value.cycleEnd }
        return value
    }
}

extension SpendableBreakdown {
    public var start: Date { cycleStart }
    public var end: Date { cycleEnd }
    public var budget: Int64 { rawR + spent }
}
