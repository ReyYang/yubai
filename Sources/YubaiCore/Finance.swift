import Foundation

public struct Occurrence: Identifiable, Equatable, Sendable {
    public var id: String; public var title: String; public var date: Date; public var amount: Int64
    public var inflow: Bool; public var planID: UUID?; public var rentID: UUID?; public var overdue: Bool
    public var rentMonth: Date? = nil
}
public struct ForecastPoint: Identifiable, Sendable {
    public var id: Date { date }; public var date: Date; public var conservative: Int64; public var expected: Int64
}
public struct Funds: Sendable {
    public var cash: Int64; public var debt: Int64; public var investments: Int64; public var receivables: Int64; public var netWorth: Int64
    public var livingEstimated: Bool = false
    public var committed: Int64; public var goals: Int64; public var emergency: Int64; public var living: Int64
    public var uncertainInflow: Int64; public var available: Int64; public var expectedIncome: Int64
    public var occurrences: [Occurrence]; public var points: [ForecastPoint]; public var warnings: [String]
    /// Horizon remainder above the floor target; negative is a gap, nil means no target.
    public var floorRoom: Int64? = nil
    public var horizonEnd: Date = Dates.addDays(Finance.observationDays, to: Dates.day(Date()))
    public var horizonDays: Int = Finance.observationDays; public var payday: Date? = nil; public var paydayTitle: String? = nil
}
public struct Breakdown: Identifiable, Sendable {
    public var id: String { category }; public var category: String; public var amount: Int64; public var count: Int
}
public struct Review: Sendable {
    public var spending: Int64; public var income: Int64; public var refunds: Int64
    public var byCategory: [Breakdown]; public var previousSpending: Int64; public var count: Int
}
/// Net expense/refund accounting is shared with Review and the weekly letter.
/// Refunds offset spending, never appear as income. Categories may be negative
/// for a refund of a purchase made before this half-open interval.
public struct CashFlowSlice: Identifiable, Sendable {
    public var id: [String] { categories }
    public var title: String
    public var categories: [String]
    public var amount: Int64
    public var share: Double
}
public struct CashFlowSummary: Sendable {
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
        let entries = ledger.activeEntries.filter { $0.date < end }
        var refunds: [UUID: Int64] = [:]
        for e in entries where e.nature == .refund {
            if let id = e.relatedEntryID { refunds[id, default: 0] += e.amount }
        }
        var windows = Array(repeating: Int64(0), count: 9)
        for e in entries where e.date >= start {
            let day = Dates.calendar.dateComponents([.day], from: start, to: Dates.day(e.date)).day ?? -1
            guard (0..<90).contains(day) else { continue }
            if e.nature == .expense, e.planID == nil, e.rentID == nil, e.amount <= 50_000 {
                windows[day / 10] += max(0, e.amount - refunds[e.id, default: 0])
            } else if e.nature == .refund, e.relatedEntryID == nil {
                windows[day / 10] -= e.amount
            }
        }
        return min(Money.limit / 366, max(0, windows.sorted()[4]) / 10)
    }
    public static func balance(_ account: Account, in ledger: Ledger, at: Date = Date()) -> Int64 {
        account.anchorBalance + ledger.entries.lazy.filter { $0.deletedAt == nil && account.includes($0, posting: $0.postingDate(for: account.id)) && $0.postingDate(for: account.id) <= at }.reduce(Int64(0)) { $0 + $1.delta(for: account.id) }
    }
    public static func occurrences(in ledger: Ledger, now: Date = Date(), days: Int? = nil) -> [Occurrence] {
        let start = Dates.day(now); let end = Dates.addDays(days ?? observationDays, to: start)
        let calendar = Dates.calendar
        func month(_ date: Date) -> Date { calendar.date(from: calendar.dateComponents([.year, .month], from: date))! }
        let payments = FixedFlowPayments(in: ledger)
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
                if let index = plan.occurrenceIndex(on: day), !plan.isSkipped(on: day), plan.endDate.map({ plan.frequency.advance(plan.dueDate, by: index) <= $0 }) ?? true { return (day, plan.title) }
            }
            return nil
        }.min { $0.date == $1.date ? $0.title < $1.title : $0.date < $1.date }
    }
    public static func funds(_ ledger: Ledger, now: Date = Date(), days: Int = Finance.observationDays) -> Funds {
        let horizon = max(0, min(366, days))
        let accounts = ledger.accounts // Archived accounts still own money and obligations.
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) }); let entries = ledger.activeEntries
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
        let payday = nextPayday(in: ledger, now: now)
        let horizonEnd = payday?.date ?? Dates.addDays(horizon, to: Dates.day(now))
        let horizonDays = Dates.calendar.dateComponents([.day], from: Dates.day(now), to: horizonEnd).day ?? horizon
        // Credit principal is reserved once as debt. A credit-repayment plan only changes its payment date.
        let repayments = Set(ledger.plans.filter { $0.nature == .repayment }.map(\.id))
        let reserved = payday != nil ? self.occurrences(in: ledger, now: now, days: horizonDays + 1) : occurrences
        let commitments = reserved.filter { !$0.inflow && Dates.day($0.date) <= horizonEnd && !($0.planID.map { repayments.contains($0) } ?? false) }
        let committed = commitments.reduce(Int64(0)) { $0 + $1.amount }
        let goals = ledger.goals.reduce(Int64(0)) { $0 + $1.reserved }
        let daily = estimatedDailyLiving(ledger, now: now)
        let living = daily * Int64(horizonDays)
        // An unresolved inflow after the most recent reconciliation is withheld until its nature is known.
        let uncertain = entries.filter { e in
            e.nature == .unknownIn && e.date <= now && accountsByID[e.accountID].map { $0.includes(e, posting: e.date) && ($0.kind == .cash || $0.kind == .bank) } == true
        }.reduce(Int64(0)) { $0 + $1.amount }
        let emergency = ledger.profile.floorAmount ?? 0
        let available = cash - debt - committed - goals - living - uncertain
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
        return Funds(cash: cash, debt: debt, investments: investment, receivables: receivables, netWorth: cash + creditNet + investment + receivables,
                     livingEstimated: true, committed: committed, goals: goals, emergency: emergency, living: living,
                     uncertainInflow: uncertain, available: available, expectedIncome: expectedIncome,
                     occurrences: occurrences, points: points, warnings: warnings, floorRoom: ledger.profile.floorAmount.map { available - $0 },
                     horizonEnd: horizonEnd, horizonDays: horizonDays, payday: payday?.date, paydayTitle: payday?.title)
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
        let categories = Dictionary(grouping: rows.filter { $0.nature == .expense || $0.nature == .refund }, by: { spendingCategory($0, entriesByID: entriesByID) })
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
        let incomeGroups = Dictionary(grouping: incomeRows, by: \.category)
        let incomeBreakdown: [Breakdown] = incomeGroups.map { category, rows in
            let amount = rows.reduce(Int64(0)) { $0 + $1.amount }
            return Breakdown(category: category, amount: amount, count: rows.count)
        }
        let income = incomeBreakdown.sorted {
            $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount
        }
        let spending = review.byCategory.sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount }
        return CashFlowSummary(income: review.income, spending: review.spending,
                               incomeByCategory: income, spendingByCategory: spending)
    }
    public static func subcategoryBreakdown(_ ledger: Ledger, category: String, during interval: DateInterval) -> [Breakdown] {
        let byID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let income = ledger.categories.first { $0.name == ledger.resolveCategory(category) }?.income ?? false
        let rows = ledger.activeEntries.filter { $0.date >= interval.start && $0.date < interval.end && (income ? $0.nature == .income : ($0.nature == .expense || $0.nature == .refund)) && ledger.resolveCategory(spendingCategory($0, entriesByID: byID)) == ledger.resolveCategory(category) }
        let grouped = Dictionary(grouping: rows) { entry in
            let original = entry.nature == .refund ? entry.relatedEntryID.flatMap { byID[$0] } : nil
            return (original ?? entry).subcategory ?? "没分类"
        }
        return grouped.map { sub, rows in Breakdown(category: sub, amount: rows.reduce(0) { $0 + (income ? $1.amount : spendingAmount($1, ledger: ledger)) }, count: rows.filter { $0.nature == .expense || $0.nature == .income }.count) }
            .sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount }
    }
    public static func assessPurchase(_ ledger: Ledger, amount: Int64, title purchaseTitle: String = "", category: String? = nil, subcategory: String? = nil, now: Date = Date()) -> PurchaseAssessment {
        let f = funds(ledger, now: now); let after = f.available - amount
        let incomplete = ledger.accounts.isEmpty || ledger.accounts.contains { !$0.reconciled } || !f.warnings.isEmpty
        let severity = after < 0 ? 2 : (incomplete || amount > max(0, f.available) / 3 ? 1 : 0)
        let title = after < 0 ? "这笔购买会挤占已安排的资金" : (incomplete ? "买前先核对明细" : "已知安排内，可以承受")
        let explanation = after < 0 ? "还差 \(Money.text(-after))，可以少花一些或晚点再买。" : "买了以后还能花 \(Money.text(after))。"
        let horizon = f.payday == nil ? "到 \(Dates.calendar.component(.month, from: f.horizonEnd))月\(Dates.calendar.component(.day, from: f.horizonEnd))日已知付款" : "发工资前已知付款"
        let bounds = PurchaseBounds.compute(ledger: ledger, amount: amount, title: purchaseTitle, category: category, subcategory: subcategory, now: now)
        let verdict: PurchaseVerdict = after < 0 ? .skip : !bounds.allowedVerdicts.contains(.buy) || amount > max(0, f.available) / 3 ? .wait : .buy
        let reason = !bounds.allowedVerdicts.contains(.buy) ? bounds.boundReason : verdict == .wait ? "这笔 \(Money.text(amount)) 超过当前还能花 \(Money.text(f.available)) 的三分之一。" : bounds.boundReason
        var facts = ["当前现金 \(Money.text(f.cash))", "信用卡要还 \(Money.text(f.debt))", "\(horizon) \(Money.text(f.committed))", "在存钱与日常开销 \(Money.text(f.goals + f.living))"]
        if let room = f.floorRoom { facts.append("想始终留着 \(Money.text(f.emergency))，" + (room >= 0 ? "按现在能留住" : "还差 \(Money.text(-room))")) }
        return PurchaseAssessment(verdict: verdict, reason: reason, title: title, explanation: explanation, afterPurchase: after, severity: severity,
                                  facts: facts + f.warnings,
                                  questions: ["它具体解决什么经常发生的问题？", "现有物品能否满足同样需要？", "如果等 48 小时，还会同样想买吗？"])
    }
}
