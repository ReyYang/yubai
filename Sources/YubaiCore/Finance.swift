import Foundation

public struct Occurrence: Identifiable, Equatable, Sendable {
    public var id: String; public var title: String; public var date: Date; public var amount: Int64
    public var inflow: Bool; public var planID: UUID?; public var rentID: UUID?; public var overdue: Bool
    public var rentMonth: Date? = nil
}
public struct ForecastPoint: Equatable, Identifiable, Sendable {
    public var id: Date { date }; public var date: Date; public var conservative: Int64; public var expected: Int64
}
public struct Funds: Equatable, Sendable {
    public var cash: Int64; public var debt: Int64; public var investments: Int64; public var receivables: Int64; public var netWorth: Int64
    public var livingEstimated: Bool = false
    public var committed: Int64; public var goals: Int64; public var emergency: Int64; public var living: Int64
    public var uncertainInflow: Int64; public var available: Int64; public var expectedIncome: Int64
    public var occurrences: [Occurrence]; public var points: [ForecastPoint]; public var warnings: [String]
    public var cycleStart = Date.distantPast
    public var cycleEnd = Date.distantPast
    public var cycleIsPayday = false
    public var liquidStart: Int64 = 0
    public var cycleIncome: Int64 = 0
    public var yearlySetAside: Int64 = 0
    public var savingRuleTarget: Int64 = 0
    public var salaryLateDays: Int? = nil
    public var savingTarget: Int64 = 0
    public var fixedSavingsTotal: Int64 { emergency }
    public var cycleSpent: Int64 = 0
    public var dueRest: Int64 = 0
    public var dailyAllowance: Int64 = 0
    public var savingShortfall: Int64 = 0
    public var liquidNow: Int64 { liquidStart + cycleIncome - cycleSpent }
    /// Retained for source compatibility; fixed savings are deducted directly.
    public var floorRoom: Int64? = nil
    public var horizonEnd: Date = Dates.addDays(Finance.observationDays, to: Dates.day(Date()))
    public var horizonDays: Int = Finance.observationDays; public var payday: Date? = nil; public var paydayTitle: String? = nil
}
public struct Breakdown: Equatable, Identifiable, Sendable {
    public var id: String { category }; public var category: String; public var amount: Int64; public var count: Int
}
public struct Review: Sendable {
    public var spending: Int64; public var income: Int64; public var refunds: Int64
    public var byCategory: [Breakdown]; public var previousSpending: Int64; public var count: Int
}
/// Net expense/refund accounting is shared with Review and the weekly letter.
/// Refunds offset spending, never appear as income. Categories may be negative
/// for a refund of a purchase made before this half-open interval.
public struct CashFlowSlice: Equatable, Identifiable, Sendable {
    public var id: [String] { categories }
    public var title: String
    public var categories: [String]
    public var amount: Int64
    public var share: Double
}
public struct CashFlowSummary: Equatable, Sendable {
    public var income: Int64
    public var spending: Int64
    public var incomeByCategory: [Breakdown]
    public var spendingByCategory: [Breakdown]
    public var balance: Int64 { income - spending }
    /// At most six positive sectors. Nonpositive net categories remain readable
    /// as signed rows, outside the donut. Shares describe positive sectors only.
    public func slices(income: Bool) -> [CashFlowSlice] {
        let rows = income ? incomeByCategory : spendingByCategory
        let positive = rows.filter { $0.amount > 0 }
        let total = positive.reduce(Int64(0)) { $0 + $1.amount }
        func slice(_ rows: [Breakdown], title: String) -> CashFlowSlice {
            let amount = rows.reduce(Int64(0)) { $0 + $1.amount }
            return CashFlowSlice(title: title, categories: rows.map(\.category), amount: amount,
                                 share: amount > 0 && total > 0 ? Double(amount) / Double(total) : 0)
        }
        var result = positive.prefix(positive.count > 6 ? 5 : 6).map { slice([$0], title: $0.category) }
        if positive.count > 6 {
            let rest = Array(positive.dropFirst(5))
            result.append(slice(rest, title: "其他 \(rest.count) 类"))
        }
        result += rows.filter { $0.amount <= 0 }.map { slice([$0], title: $0.category) }
        return result
    }

}

public struct PurchaseAssessment: Sendable {
    public var verdict: PurchaseVerdict = .buy
    public var reason: String = ""
    public var title: String; public var explanation: String; public var afterPurchase: Int64
    public var severity: Int; public var facts: [String]; public var questions: [String]
}

public enum Finance {
    public static let observationDays = 90
    /// Median of nine 10-day spending totals / 10 over the 90 complete calendar days
    /// ending yesterday. Today's entries cannot change the estimate within the day.
    /// Includes zero-spend days; excludes single bills above ¥500 and plan/rent-linked
    /// expenses. Linked refunds offset their original; unlinked refunds offset their
    /// own 10-day window. The median resists a few unusually expensive windows.
    public static func estimatedDailyLiving(_ ledger: Ledger, now: Date) -> Int64 {
        let end = Dates.day(now); let start = Dates.addDays(-90, to: end)
        if let cached = ledger.calculations.dailyLiving(on: end) { return cached }
        let entries = ledger.entries.lazy.filter { $0.deletedAt == nil && $0.date < end }
        var refunds: [UUID: Int64] = [:]
        for e in entries where e.nature == .refund {
            if let id = e.relatedEntryID { refunds[id, default: 0] += e.amount }
        }
        var windows = Array(repeating: Int64(0), count: 9)
        let boundaries = (0...9).map { Dates.addDays($0 * 10, to: start) }
        for e in entries where e.date >= start {
            // Calendar boundaries preserve DST and local-midnight semantics
            // without allocating calendar components for every transaction.
            var window = 0
            while window < 8 && e.date >= boundaries[window + 1] { window += 1 }
            if e.nature == .expense, e.planID == nil, e.rentID == nil, e.amount <= 50_000 {
                windows[window] += max(0, e.amount - refunds[e.id, default: 0])
            } else if e.nature == .refund, e.relatedEntryID == nil {
                windows[window] -= e.amount
            }
        }
        let value = min(Money.limit / 366, max(0, windows.sorted()[4]) / 10)
        ledger.calculations.storeDailyLiving(value, day: end)
        return value
    }
    public static func balance(_ account: Account, in ledger: Ledger, at: Date = Date()) -> Int64 {
        account.anchorBalance + ledger.entries.lazy.filter { $0.deletedAt == nil && account.includes($0, posting: $0.postingDate(for: account.id)) && $0.postingDate(for: account.id) <= at }.reduce(Int64(0)) { $0 + $1.delta(for: account.id) }
    }
    public static func occurrences(in ledger: Ledger, now: Date = Date(), days: Int? = nil) -> [Occurrence] {
        let start = Dates.day(now); let end = Dates.addDays(days ?? observationDays, to: start)
        let calendar = Dates.calendar
        func month(_ date: Date) -> Date { calendar.date(from: calendar.dateComponents([.year, .month], from: date))! }
        let payments = FixedFlowPayments(in: ledger, now: now)
        var result: [Occurrence] = []
        for p in ledger.plans where p.active {
            // Always derive from the original day (Jan 31 → Feb 28 → Mar 31), never chained dates.
            for item in p.schedule(through: end) {
                let date = item.date; let day = Dates.day(date); let remaining = payments.remaining(for: p, on: date)
                if remaining > 0 {
                    result.append(Occurrence(id: "\(p.id)-\(date.timeIntervalSince1970)", title: p.title, date: date, amount: remaining, inflow: p.inflow, planID: p.id, overdue: day < start))
                }
            }
        }
        for r in ledger.rents where r.active {
            let endDay = r.endDate.map { calendar.startOfDay(for: $0) }
            for index in 0..<240 {
                let due = Dates.addMonths(index * r.monthsPerPayment, to: r.nextDueDate)
                let day = calendar.startOfDay(for: due)
                if due > end || (endDay != nil && day > endDay!) { break }
                let paid = payments.rentPaid[FixedFlowPaymentKey(id: r.id, day: day), default: 0]
                let dueAmount = r.monthlyTotal * Int64(r.monthsPerPayment)
                if paid < dueAmount { result.append(Occurrence(id: "rent-\(r.id)-\(due.timeIntervalSince1970)", title: r.title, date: due, amount: dueAmount - paid, inflow: false, rentID: r.id, overdue: day < start)) }
            }
            let firstMonth = month(r.startDate)
            for index in 0..<1200 {
                let month = Dates.addMonths(index, to: firstMonth)
                let receiveDate = max(Dates.addDays(r.receiveDay - 1, to: month), r.startDate)
                let day = calendar.startOfDay(for: receiveDate)
                if receiveDate > end || (endDay != nil && day > endDay!) { break }
                let paid = payments.rentReceived[FixedFlowPaymentKey(id: r.id, day: month), default: 0]
                let amount = r.monthlyTotal - r.personalShare - paid
                if amount > 0 { result.append(Occurrence(id: "share-\(r.id)-\(month.timeIntervalSince1970)", title: r.title + " · 应收分摊", date: receiveDate, amount: amount, inflow: true, rentID: r.id, overdue: day < start, rentMonth: month)) }
            }
        }
        return result.sorted { $0.date < $1.date }
    }
    public static func nextPayday(in ledger: Ledger, now: Date) -> (date: Date, title: String)? {
        let today = Dates.day(now)
        return ledger.plans.filter { $0.active && $0.inflow && $0.nature == .income && $0.frequency != .once }.compactMap { plan -> (date: Date, title: String)? in
            for offset in 1...observationDays {
                let day = Dates.addDays(offset, to: today)
                if let index = plan.occurrenceIndex(on: day), !plan.isSkipped(on: day),
                   !(plan.occurrenceDateOverrides?.isEmpty ?? true) ||
                    (plan.endDate.map({ (plan.previousOccurrences.isEmpty ? plan.scheduledDate(at: index) : day) <= $0 }) ?? true) {
                    return (day, plan.title)
                }
            }
            return nil
        }.min { $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date }
    }
    static func scheduledCycle(in ledger: Ledger, now: Date) -> (start: Date, end: Date, payday: Bool) {
        let month = Dates.calendar.dateInterval(of: .month, for: now)!
        let natural = (start: month.start, end: Dates.addDays(-1, to: month.end), payday: false)
        if ledger.cycleAnchor == .calendarMonth { return natural }
        if let plan = anchorPlan(in: ledger, now: now),
           let next = nextPayday(in: { var source = ledger; source.plans = [plan]; return source }(), now: now) {
            if !(plan.occurrenceDateOverrides?.isEmpty ?? true),
               let previous = plan.schedule(through: Dates.addDays(1, to: Dates.day(now)).addingTimeInterval(-0.001)).last(where: { !plan.isSkipped(on: $0.date) }) {
                return (Dates.day(previous.date), Dates.addDays(-1, to: next.date), true)
            }
            // Derive from the original schedule, preserving Jan 31 → Feb 28 → Mar 31.
            let calendar = Dates.calendar
            let months = calendar.dateComponents([.month], from: calendar.dateInterval(of: .month, for: plan.dueDate)!.start,
                                                  to: calendar.dateInterval(of: .month, for: next.date)!.start).month ?? 0
            let index: Int
            switch plan.frequency {
            case .weekly: index = (calendar.dateComponents([.day], from: Dates.day(plan.dueDate), to: next.date).day ?? 0) / 7
            case .monthly: index = months
            case .quarterly: index = months / 3
            case .halfYearly: index = months / 6
            case .fortnightly: index = (calendar.dateComponents([.day], from: Dates.day(plan.dueDate), to: next.date).day ?? 0) / 14
            case .yearly: index = months / 12
            case .once: index = 0
            }
            var previousIndex = index - 1
            var previous = Dates.day(plan.scheduledDate(at: previousIndex))
            while previous > Dates.day(now) {
                previousIndex -= 1
                previous = Dates.day(plan.scheduledDate(at: previousIndex))
            }
            return (previous, Dates.addDays(-1, to: next.date), true)
        }
        return natural
    }
    public static func funds(_ ledger: Ledger, now: Date = Date(), days: Int = Finance.observationDays) -> Funds {
        let horizon = max(0, min(366, days))
        if let cached = ledger.calculations.cachedFunds(now: now, days: horizon) { return cached }
        let accounts = ledger.accounts // Archived accounts still own money and obligations.
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) }); let entries = ledger.entries.lazy.filter { $0.deletedAt == nil }
        var deltas: [UUID: Int64] = [:]
        for entry in entries {
            if let account = accountsByID[entry.accountID] {
                let date = entry.postingDate(for: account.id)
                if account.includes(entry, posting: date) && date <= now { deltas[account.id, default: 0] += entry.delta(for: account.id) }
            }
            if entry.nature.paired, let other = entry.otherAccountID, other != entry.accountID, let account = accountsByID[other] {
                let date = entry.postingDate(for: other)
                if account.includes(entry, posting: date) && date <= now { deltas[other, default: 0] += entry.delta(for: other) }
            }
        }
        var cash: Int64 = 0; var creditNet: Int64 = 0; var debt: Int64 = 0; var investment: Int64 = 0; var receivables: Int64 = 0
        for account in accounts {
            let value = account.anchorBalance + deltas[account.id, default: 0]
            switch account.kind {
            case .cash, .bank: cash += value
            case .credit: creditNet += value; debt += max(0, -value)
            case .investment: investment += value
            case .receivable: receivables += value
            }
        }
        let occurrences = occurrences(in: ledger, now: now, days: horizon)
        let cycle = cycleInfo(in: ledger, now: now)
        let payday = nextPayday(in: ledger, now: now)
        let paydayDate = cycle.payday ? cycle.nextPayday : payday?.date
        let paydayTitle = cycle.payday ? anchorPlan(in: ledger, now: now)?.title : payday?.title
        let horizonEnd = cycle.end
        let horizonDays = Dates.calendar.dateComponents([.day], from: Dates.day(now), to: horizonEnd).day ?? horizon
        // Credit principal is reserved once as debt. A credit-repayment plan only changes its payment date.
        let repayments = Set(ledger.plans.filter { $0.nature == .repayment }.map(\.id))
        let reserved = self.occurrences(in: ledger, now: now, days: horizonDays + 1)
        let commitments = reserved.filter { !$0.inflow && Dates.day($0.date) <= horizonEnd && !($0.planID.map { repayments.contains($0) } ?? false) }
        let committed = commitments.reduce(Int64(0)) { $0 + $1.amount }
        let goals = ledger.goals.reduce(Int64(0)) { $0 + $1.reserved }
        let daily = estimatedDailyLiving(ledger, now: now)
        let living: Int64 = 0
        // An unresolved inflow after the most recent reconciliation is withheld until its nature is known.
        let uncertain = entries.filter { e in
            e.nature == .unknownIn && e.date <= now && accountsByID[e.accountID].map { $0.includes(e, posting: e.date) && ($0.kind == .cash || $0.kind == .bank) } == true
        }.reduce(Int64(0)) { $0 + $1.amount }
        let emergency = ledger.fixedSavingsTotal(now: now)
        let cycleRows = entries.filter { $0.date >= cycle.start && $0.date <= now }
        let income = cycleRows.filter { $0.nature == .income && !$0.intoFixedSavings }.reduce(Int64(0)) { $0 + $1.amount }
        let reserveIDs = Set(entries.filter { $0.fromReserve }.map(\.id))
        let spent = cycleRows.reduce(Int64(0)) { total, row in
            if row.fromReserve || (row.nature == .refund && row.relatedEntryID.map { reserveIDs.contains($0) } == true) { return total }
            return total + spendingAmount(row, ledger: ledger)
        }
        let savingRuleTarget = (ledger.savingRule?.target(income: income) ?? 0) +
            Reserve.paybackAmounts(ledger, cycleStart: cycle.start, now: now).reduce(0) { $0 + $1.amount }
        let savingTarget = ledger.effectiveSavingTarget(savingRuleTarget, cycleStart: cycle.start, now: now)
        let liquid = cash - debt - emergency - goals - uncertain
        let yearlySetAside = YearlyBillReserves.rows(in: ledger, now: now, committedThrough: horizonEnd).reduce(Int64(0)) { $0 + $1.reserved }
        let available = liquid - savingTarget - committed - yearlySetAside
        let expectedIncome = occurrences.filter(\.inflow).reduce(Int64(0)) { $0 + $1.amount }
        var warnings: [String] = []
        if accounts.isEmpty { warnings.append("还没有账户") }
        if accounts.contains(where: { !$0.reconciled }) { warnings.append("有账户还没对过账。") }
        if accounts.contains(where: { now.timeIntervalSince($0.anchorDate) > 14 * 86400 }) { warnings.append("部分账户上次对账已超过 14 天，请补齐账单。") }
        if entries.contains(where: { $0.nature.uncertain }) { warnings.append("有账目没写用途，请补上。") }
        if occurrences.contains(where: \.overdue) { warnings.append("有固定收付已到期，请确认是否已付。") }
        if entries.contains(where: { $0.nature.paired && $0.otherAccountID == nil }) { warnings.append("有转账没选另一账户，请补上。") }
        let baseline = cash - debt - goals - uncertain
        var points: [ForecastPoint] = []
        let start = Dates.day(now); let occurrenceDays = occurrences.map { Dates.day($0.date) }
        var cursor = 0; var out: Int64 = 0; var incoming: Int64 = 0
        for offset in 0...horizon {
            let date = Dates.addDays(offset, to: start)
            while cursor < occurrences.count && occurrenceDays[cursor] <= date {
                let item = occurrences[cursor]
                if item.inflow { incoming += item.amount }
                else if !(item.planID.map { repayments.contains($0) } ?? false) { out += item.amount }
                cursor += 1
            }
            let conservative = baseline - out - Int64(offset) * daily
            points.append(ForecastPoint(date: date, conservative: conservative, expected: conservative + incoming))
        }
        var value = Funds(cash: cash, debt: debt, investments: investment, receivables: receivables, netWorth: cash + creditNet + investment + receivables,
                     livingEstimated: true, committed: committed, goals: goals, emergency: emergency, living: living,
                     uncertainInflow: uncertain, available: available, expectedIncome: expectedIncome,
                     occurrences: occurrences, points: points, warnings: warnings, floorRoom: nil,
                     horizonEnd: horizonEnd, horizonDays: horizonDays, payday: paydayDate, paydayTitle: paydayTitle)
        value.cycleStart = cycle.start; value.cycleEnd = cycle.end; value.cycleIsPayday = cycle.payday
        value.liquidStart = liquid - income + spent; value.cycleIncome = income; value.savingTarget = savingTarget
        value.cycleSpent = spent; value.dueRest = committed
        value.yearlySetAside = yearlySetAside
        value.savingRuleTarget = savingRuleTarget
        value.salaryLateDays = cycle.lateSince.map { Dates.calendar.dateComponents([.day], from: $0, to: Dates.day(now)).day ?? 0 }
        value.dailyAllowance = max(0, available) / Int64(max(1, horizonDays + 1))
        value.savingShortfall = min(savingTarget, max(0, -available))
        ledger.calculations.storeFunds(value, in: ledger, now: now, days: horizon)
        return value
    }
    public static func spendingAmount(_ entry: Entry, ledger: Ledger) -> Int64 {
        spendingAmount(entry, rent: entry.rentID.flatMap { id in ledger.rents.first { $0.id == id } })
    }
    /// Indexed callers can share the same rules without a rent lookup per row.
    public static func spendingAmount(_ entry: Entry, rent: Rent?) -> Int64 {
        if entry.nature == .expense {
            if let personal = entry.personalExpense { return personal }
            if let rent, rent.monthlyTotal > 0 {
                return NSDecimalNumber(decimal: Decimal(entry.amount) * Decimal(rent.personalShare) / Decimal(rent.monthlyTotal)).int64Value
            }
            return entry.amount
        }
        if entry.nature == .refund { return -(entry.personalExpense ?? entry.amount) }
        return 0
    }
    /// Reuse a full-ledger lookup so refunds follow expenses outside the review period too.
    public static func spendingCategory(_ entry: Entry, entriesByID: [UUID: Entry]) -> String {
        guard entry.nature == .refund, let id = entry.relatedEntryID, let original = entriesByID[id], original.nature == .expense else { return entry.category }
        return original.category
    }
    public static func review(_ ledger: Ledger, from: Date, through end: Date) -> Review {
        let rows = ledger.activeEntries.filter { $0.date >= from && $0.date < end }
        let prior = ledger.activeEntries.filter { $0.date >= from.addingTimeInterval(-end.timeIntervalSince(from)) && $0.date < from }
        let entriesByID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let categories = Dictionary(grouping: rows.filter { $0.nature == .expense || $0.nature == .refund }, by: { ledger.normalizedCategory(for: $0, entriesByID: entriesByID).category })
        let byCategory = categories.map { name, entries in Breakdown(category: name, amount: entries.reduce(0) { $0 + spendingAmount($1, ledger: ledger) }, count: entries.count) }.sorted { $0.amount > $1.amount }
        return Review(spending: byCategory.reduce(0) { $0 + $1.amount }, income: rows.filter { $0.nature == .income }.reduce(0) { $0 + $1.amount },
                      refunds: rows.filter { $0.nature == .refund }.reduce(0) { $0 + $1.amount }, byCategory: byCategory,
                      previousSpending: prior.reduce(0) { $0 + spendingAmount($1, ledger: ledger) }, count: rows.count)
    }
    /// Pure, deterministic, half-open [start, end) aggregation. Transfers,
    /// repayments, contributions and uncertain natures are not income/spending.
    public static func cashFlow(_ ledger: Ledger, during interval: DateInterval) -> CashFlowSummary {
        let review = review(ledger, from: interval.start, through: interval.end)
        let incomeRows = ledger.activeEntries.filter { $0.nature == .income && $0.date >= interval.start && $0.date < interval.end }
        let incomeGroups = Dictionary(grouping: incomeRows) { ledger.normalizedCategory(for: $0).category }
        let incomeBreakdown: [Breakdown] = incomeGroups.map { category, rows in
            let amount = rows.reduce(Int64(0)) { $0 + $1.amount }
            return Breakdown(category: category, amount: amount, count: rows.count)
        }
        let income = incomeBreakdown.sorted {
            $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount
        }
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let expenseRows = ledger.entries.filter { $0.deletedAt == nil && $0.date >= interval.start && $0.date < interval.end && ($0.nature == .expense || $0.nature == .refund) }
        let expenseGroups = Dictionary(grouping: expenseRows) { entry -> String in
            let source = entry.nature == .refund ? entry.relatedEntryID.flatMap { lookup[$0] } ?? entry : entry
            return source.isUnitemized && Classification.isPending(source) ? Reconciliation.unitemizedTitle : ledger.normalizedCategory(for: entry, entriesByID: lookup).category
        }
        let spendingBreakdown: [Breakdown] = expenseGroups.map { name, rows in
            let amount = rows.reduce(Int64(0)) { $0 + spendingAmount($1, ledger: ledger) }
            return Breakdown(category: name, amount: amount, count: rows.count)
        }
        let spending = spendingBreakdown.sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount }
        return CashFlowSummary(income: review.income, spending: review.spending,
                               incomeByCategory: income, spendingByCategory: spending)
    }
    public static func subcategoryBreakdown(_ ledger: Ledger, category: String, income: Bool, during interval: DateInterval) -> [Breakdown] {
        let byID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let rows = ledger.activeEntries.filter { $0.date >= interval.start && $0.date < interval.end && (income ? $0.nature == .income : ($0.nature == .expense || $0.nature == .refund)) && ledger.normalizedCategory(for: $0, entriesByID: byID).category == ledger.resolveCategory(category, income: income) }
        let grouped = Dictionary(grouping: rows) { entry in
            return ledger.normalizedCategory(for: entry, entriesByID: byID).subcategory ?? "没分类"
        }
        return grouped.map { sub, rows in Breakdown(category: sub, amount: rows.reduce(0) { $0 + (income ? $1.amount : spendingAmount($1, ledger: ledger)) }, count: rows.filter { $0.nature == .expense || $0.nature == .income }.count) }
            .sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount }
    }
    public static func assessPurchase(_ ledger: Ledger, amount: Int64, title purchaseTitle: String = "", category: String? = nil, subcategory: String? = nil, now: Date = Date()) -> PurchaseAssessment {
        let f = funds(ledger, now: now); let after = f.available - amount
        let incomplete = ledger.accounts.isEmpty || ledger.accounts.contains { !$0.reconciled } || !f.warnings.isEmpty
        let severity = f.liquidNow - f.dueRest - amount < 0 ? 2 : (incomplete || amount > max(0, f.available) / 3 ? 1 : 0)
        let title = after < 0 ? "这笔购买会挤占已安排的资金" : (incomplete ? "买前先核对明细" : "已知安排内，可以承受")
        let explanation = after < 0 ? "还差 \(Money.text(-after))，可以少花一些或晚点再买。" : "买了以后还能花 \(Money.text(after))。"
        let horizon = f.payday == nil ? "到 \(Dates.calendar.component(.month, from: f.horizonEnd))月\(Dates.calendar.component(.day, from: f.horizonEnd))日已知付款" : "发工资前已知付款"
        let bounds = PurchaseBounds.compute(ledger: ledger, amount: amount, title: purchaseTitle, category: category, subcategory: subcategory, now: now)
        let verdict: PurchaseVerdict = bounds.allowedVerdicts == [.skip] ? .skip : !bounds.allowedVerdicts.contains(.buy) || amount > max(0, f.available) / 3 ? .wait : .buy
        var sample = Entry(date: now, amount: amount, accountID: UUID(), title: purchaseTitle, category: category ?? Classification.pendingCategory)
        sample.subcategory = subcategory
        let hasPart = SpendingParts.part(for: sample, in: ledger) != nil
        let reason = hasPart || !bounds.allowedVerdicts.contains(.buy) ? bounds.boundReason : verdict == .wait ? "这笔 \(Money.text(amount)) 超过当前还能花 \(Money.text(f.available)) 的三分之一。" : bounds.boundReason
        let facts = ["当前现金 \(Money.text(f.cash))", "信用卡要还 \(Money.text(f.debt))", "\(horizon) \(Money.text(f.committed))", "在存钱 \(Money.text(f.goals))", "存着不动 \(Money.text(f.emergency))", "要攒 \(Money.text(f.savingTarget))"]

        return PurchaseAssessment(verdict: verdict, reason: reason, title: title, explanation: explanation, afterPurchase: after, severity: severity,
                                  facts: facts + f.warnings,
                                  questions: ["它具体解决什么经常发生的问题？", "现有物品能否满足同样需要？", "如果等 48 小时，还会同样想买吗？"])
    }
}

/// Rendering caches are owned by AppStore and deliberately kept outside Observation.
/// The owner advances revision for every ledger change, including undo and restore.
public struct LedgerPresentationCache {
    private var revision: UInt64?
    private var ledgerID: UUID?
    private var entryDates: [Date] = []
    private var sortedEntries: [Entry]?
    private var byID: [UUID: Entry]?
    private struct FlowKey: Hashable { let start: Int; let end: Int }
    private struct RecordsKey: Hashable {
        let categories: [String]; let income: Bool; let interval: DateInterval; let subcategory: String?
    }
    private var flows: [FlowKey: CashFlowSummary] = [:]
    private var slices: [FlowKey: (income: [CashFlowSlice], spending: [CashFlowSlice])] = [:]
    private var records: [RecordsKey: [Entry]] = [:]
    private struct SubcategoryKey: Hashable { let category: String; let income: Bool; let interval: DateInterval }
    private struct EvidenceKey: Hashable { let ids: Set<UUID>; let activeOnly: Bool }
    private var subcategories: [SubcategoryKey: [Breakdown]] = [:]
    private var evidence: [EvidenceKey: [Entry]] = [:]
    private var candidates: [SubscriptionCandidate]?
    private var settingsValue: (value: LedgerSettingsSummary, at: Date, expires: Date, zone: TimeZone)?
    private var savingsValue: (value: LedgerSavingsTotals, at: Date, expires: Date, zone: TimeZone)?
    private var capturesValue: (value: [Entry], at: Date, expires: Date, zone: TimeZone)?
    public init() {}
    private mutating func prepare(_ ledger: Ledger, revision: UInt64) {
        guard self.revision != revision || ledgerID != ledger.id else { return }
        self.revision = revision; ledgerID = ledger.id
        entryDates = ledger.entries.filter { $0.deletedAt == nil }.map(\.date).sorted()
        sortedEntries = nil; byID = nil; flows = [:]; slices = [:]; records = [:]; subcategories = [:]; evidence = [:]; candidates = nil; settingsValue = nil; savingsValue = nil; capturesValue = nil
    }
    // Two half-open intervals in the same gaps between posting dates select exactly
    // the same rows. This also caches a live interval whose end is Date() each render,
    // without rounding dates or missing a future entry as it becomes eligible.
    private func boundary(_ date: Date) -> Int {
        var low = 0, high = entryDates.count
        while low < high {
            let mid = (low + high) / 2
            if entryDates[mid] < date { low = mid + 1 } else { high = mid }
        }
        return low
    }
    public mutating func cashFlow(in ledger: Ledger, during interval: DateInterval, revision: UInt64) -> CashFlowSummary {
        prepare(ledger, revision: revision)
        let key = FlowKey(start: boundary(interval.start), end: boundary(interval.end))
        if let value = flows[key] { return value }
        let value = Finance.cashFlow(ledger, during: interval)
        if flows.count >= 32 { flows.removeAll(keepingCapacity: true) }
        flows[key] = value; return value
    }
    public mutating func cashFlowSlices(in ledger: Ledger, during interval: DateInterval, income: Bool, revision: UInt64) -> [CashFlowSlice] {
        let summary = cashFlow(in: ledger, during: interval, revision: revision)
        let key = FlowKey(start: boundary(interval.start), end: boundary(interval.end))
        if let value = slices[key] { return income ? value.income : value.spending }
        let value = (income: summary.slices(income: true), spending: summary.slices(income: false))
        if slices.count >= 32 { slices.removeAll(keepingCapacity: true) }
        slices[key] = value; return income ? value.income : value.spending
    }
    public mutating func flowRecords(in ledger: Ledger, categories: [String], income: Bool,
                                    interval: DateInterval, subcategory: String? = nil, revision: UInt64) -> [Entry] {
        prepare(ledger, revision: revision)
        let key = RecordsKey(categories: categories, income: income, interval: interval, subcategory: subcategory)
        if let value = records[key] { return value }
        if sortedEntries == nil { sortedEntries = ledger.entries.sorted { $0.date > $1.date } }
        if byID == nil { byID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) }) }
        let lookup = byID!
        let resolved = Set(categories.map { ledger.resolveCategory($0, income: income) })
        let value = sortedEntries!.filter { entry in
            guard entry.deletedAt == nil, entry.date >= interval.start, entry.date < interval.end,
                  income ? entry.nature == .income : (entry.nature == .expense || entry.nature == .refund) else { return false }
            let choice = ledger.normalizedCategory(for: entry, entriesByID: lookup)
            return resolved.contains(choice.category) && (subcategory == nil || (choice.subcategory ?? "其他") == subcategory)
        }
        if records.count >= 32 { records.removeAll(keepingCapacity: true) }
        records[key] = value; return value
    }
    public mutating func subcategoryBreakdown(in ledger: Ledger, category: String, income: Bool, during interval: DateInterval, revision: UInt64) -> [Breakdown] {
        prepare(ledger, revision: revision)
        let key = SubcategoryKey(category: category, income: income, interval: interval)
        if let value = subcategories[key] { return value }
        let value = Finance.subcategoryBreakdown(ledger, category: category, income: income, during: interval)
        if subcategories.count >= 32 { subcategories.removeAll(keepingCapacity: true) }
        subcategories[key] = value; return value
    }
    public mutating func evidenceEntries(in ledger: Ledger, ids: Set<UUID>, activeOnly: Bool, revision: UInt64) -> [Entry] {
        prepare(ledger, revision: revision)
        let key = EvidenceKey(ids: ids, activeOnly: activeOnly)
        if let value = evidence[key] { return value }
        if sortedEntries == nil { sortedEntries = ledger.entries.sorted { $0.date > $1.date } }
        let value = sortedEntries!.filter { ids.contains($0.id) && (!activeOnly || $0.deletedAt == nil) }
        if evidence.count >= 32 { evidence.removeAll(keepingCapacity: true) }
        evidence[key] = value; return value
    }
    public mutating func subscriptions(in ledger: Ledger, revision: UInt64) -> [SubscriptionCandidate] {
        prepare(ledger, revision: revision)
        if let candidates { return candidates }
        let value = SubscriptionCheck.candidates(ledger: ledger)
        candidates = value; return value
    }
    public mutating func savings(in ledger: Ledger, revision: UInt64, now: Date = Date()) -> LedgerSavingsTotals {
        prepare(ledger, revision: revision)
        let zone = TimeZone.current
        if let cached = savingsValue, cached.zone == zone, now >= cached.at, now < cached.expires { return cached.value }
        let month = Dates.calendar.dateInterval(of: .month, for: now)!
        let value = LedgerSavingsTotals(total: Savings.total(ledger: ledger, now: now),
            month: Savings.summary(ledger: ledger, from: month.start, to: now, now: now).total)
        var expires = Dates.addDays(1, to: Dates.day(now))
        // total uses < now + 1ms, while the month uses < now. Retain both
        // thresholds, including the exact boundary where strict < still excludes.
        func boundary(_ date: Date) -> Date? {
            let early = date.addingTimeInterval(-0.001)
            if early >= now { return early }
            return date >= now ? date : nil
        }
        for wish in ledger.wishlist where wish.status == .dropped {
            if let date = wish.droppedAt, let next = boundary(date) { expires = min(expires, next) }
        }
        for plan in ledger.stoppedSubscriptions.map(\.plan) + ledger.plans {
            for item in plan.schedule(through: expires.addingTimeInterval(0.001)) {
                if let next = boundary(item.date) { expires = min(expires, next) }
            }
        }
        savingsValue = (value, now, expires, zone); return value
    }
    public mutating func recentCaptures(in ledger: Ledger, revision: UInt64, now: Date = Date()) -> [Entry] {
        prepare(ledger, revision: revision)
        let zone = TimeZone.current
        if let cached = capturesValue, cached.zone == zone, now >= cached.at, now < cached.expires { return cached.value }
        let start = Dates.addDays(-6, to: Dates.day(now))
        var expires = Dates.addDays(1, to: Dates.day(now))
        var rows: [Entry] = []
        for entry in ledger.entries where entry.deletedAt == nil && entry.quickCapture != nil {
            let date = entry.recordedAt ?? entry.date
            if date > now { expires = min(expires, date) }
            if date >= start && date <= now { rows.append(entry) }
        }
        capturesValue = (rows, now, expires, zone); return rows
    }
    public mutating func settings(in ledger: Ledger, revision: UInt64, now: Date = Date()) -> LedgerSettingsSummary {
        prepare(ledger, revision: revision)
        let zone = TimeZone.current
        if let cached = settingsValue, cached.zone == zone, now >= cached.at, now < cached.expires { return cached.value }
        let cash = ledger.accounts.filter { $0.kind == .bank || $0.kind == .cash }
        let balances = cash.map { Finance.balance($0, in: ledger, at: now) }
        let week = ButlerCards.isoWeek(now)
        let value = LedgerSettingsSummary(cashAccounts: cash, cashBalances: balances,
            thinkingCount: ledger.wishlist.filter { $0.status == .thinking }.count,
            followUpCount: ledger.wishlist.filter { $0.status == .bought && $0.followUpAnswer == nil && $0.followUpAt.map { $0 <= now } == true }.count,
            memoryCount: ledger.memories.count,
            weeklyMemoryCount: ledger.memories.filter { ButlerCards.isoWeek($0.createdAt) == week }.count,
            fixedFlowTitles: FixedFlowArrangement.rows(in: ledger).map(\.title))
        var expires = Dates.addDays(1, to: Dates.day(now))
        for entry in ledger.entries where entry.deletedAt == nil {
            if entry.date > now { expires = min(expires, entry.date) }
            if let date = entry.otherDate, date > now { expires = min(expires, date) }
        }
        for wish in ledger.wishlist {
            if let date = wish.followUpAt, date > now { expires = min(expires, date) }
        }
        settingsValue = (value, now, expires, zone); return value
    }
}
public struct LedgerSettingsSummary: Equatable, Sendable {
    public let cashAccounts: [Account]
    public let cashBalances: [Int64]
    public let thinkingCount: Int
    public let followUpCount: Int
    public let memoryCount: Int
    public let weeklyMemoryCount: Int
    public let fixedFlowTitles: [String]
}

public struct LedgerSavingsTotals: Equatable, Sendable {
    public let total: Int64
    public let month: Int64
}
