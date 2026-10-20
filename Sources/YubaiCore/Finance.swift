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
    public var title: String; public var explanation: String; public var afterPurchase: Int64
    public var severity: Int; public var facts: [String]; public var questions: [String]
}

public enum Finance {
    public static let observationDays = 90
    /// Median of nine 10-day spending totals / 10 over the last 90 calendar days.
    /// Includes zero-spend days; excludes single bills above ¥500 and plan/rent-linked
    /// expenses. Linked refunds offset their original; unlinked refunds offset their
    /// own 10-day window. The median resists a few unusually expensive windows.
    public static func estimatedDailyLiving(_ ledger: Ledger, now: Date) -> Int64 {
        let start = Dates.addDays(-89, to: Dates.day(now))
        let entries = ledger.activeEntries.filter { $0.date <= now }
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
    private struct PaymentKey: Hashable { var id: UUID; var period: Date }
    public static func balance(_ account: Account, in ledger: Ledger, at: Date = Date()) -> Int64 {
        account.anchorBalance + ledger.entries.lazy.filter { $0.deletedAt == nil && $0.postingDate(for: account.id) > account.anchorDate && $0.postingDate(for: account.id) <= at }.reduce(Int64(0)) { $0 + $1.delta(for: account.id) }
    }
    public static func occurrences(in ledger: Ledger, now: Date = Date(), days: Int? = nil) -> [Occurrence] {
        let start = Dates.day(now); let end = Dates.addDays(days ?? observationDays, to: start)
        let calendar = Dates.calendar
        func month(_ date: Date) -> Date { calendar.date(from: calendar.dateComponents([.year, .month], from: date))! }
        var planPaid: [PaymentKey: Int64] = [:]; var rentPaid: [PaymentKey: Int64] = [:]; var rentReceived: [PaymentKey: Int64] = [:]
        for entry in ledger.entries where entry.deletedAt == nil {
            if let id = entry.planID, let date = entry.occurrence { planPaid[PaymentKey(id: id, period: calendar.startOfDay(for: date)), default: 0] += entry.amount }
            if let id = entry.rentID, let date = entry.rentPeriod {
                if entry.nature == .expense { rentPaid[PaymentKey(id: id, period: calendar.startOfDay(for: date)), default: 0] += entry.amount }
                if entry.nature == .contribution { rentReceived[PaymentKey(id: id, period: month(date)), default: 0] += entry.amount }
            }
        }
        var result: [Occurrence] = []
        for p in ledger.plans where p.active {
            // Always derive from the original day (Jan 31 → Feb 28 → Mar 31), never chained dates.
            for index in 0..<2400 {
                let date = p.frequency.advance(p.dueDate, by: index)
                if date > end || (p.endDate != nil && date > p.endDate!) { break }
                let day = calendar.startOfDay(for: date); let paid = planPaid[PaymentKey(id: p.id, period: day), default: 0]
                if paid < p.amount {
                    result.append(Occurrence(id: "\(p.id)-\(date.timeIntervalSince1970)", title: p.title, date: date, amount: p.amount - paid, inflow: p.inflow, planID: p.id, overdue: day < start))
                }
                if p.frequency == .once { break }
            }
        }
        for r in ledger.rents where r.active {
            let endDay = r.endDate.map { calendar.startOfDay(for: $0) }
            for index in 0..<240 {
                let due = Dates.addMonths(index * r.monthsPerPayment, to: r.nextDueDate)
                let day = calendar.startOfDay(for: due)
                if due > end || (endDay != nil && day > endDay!) { break }
                let paid = rentPaid[PaymentKey(id: r.id, period: day), default: 0]
                let dueAmount = r.monthlyTotal * Int64(r.monthsPerPayment)
                if paid < dueAmount { result.append(Occurrence(id: "rent-\(r.id)-\(due.timeIntervalSince1970)", title: r.title, date: due, amount: dueAmount - paid, inflow: false, rentID: r.id, overdue: day < start)) }
            }
            let firstMonth = month(r.startDate)
            for index in 0..<1200 {
                let month = Dates.addMonths(index, to: firstMonth)
                let receiveDate = max(Dates.addDays(r.receiveDay - 1, to: month), r.startDate)
                let day = calendar.startOfDay(for: receiveDate)
                if receiveDate > end || (endDay != nil && day > endDay!) { break }
                let paid = rentReceived[PaymentKey(id: r.id, period: month), default: 0]
                let amount = r.monthlyTotal - r.personalShare - paid
                if amount > 0 { result.append(Occurrence(id: "share-\(r.id)-\(month.timeIntervalSince1970)", title: r.title + " · 应收分摊", date: receiveDate, amount: amount, inflow: true, rentID: r.id, overdue: day < start, rentMonth: month)) }
            }
        }
        return result.sorted { $0.date < $1.date }
    }
    public static func funds(_ ledger: Ledger, now: Date = Date(), days: Int = Finance.observationDays) -> Funds {
        let horizon = max(0, min(366, days))
        let accounts = ledger.accounts // Archived accounts still own money and obligations.
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) }); let entries = ledger.activeEntries
        var deltas: [UUID: Int64] = [:]
        for entry in entries {
            if let account = accountsByID[entry.accountID] {
                let date = entry.postingDate(for: account.id)
                if date > account.anchorDate && date <= now { deltas[account.id, default: 0] += entry.delta(for: account.id) }
            }
            if entry.nature.paired, let other = entry.otherAccountID, other != entry.accountID, let account = accountsByID[other] {
                let date = entry.postingDate(for: other)
                if date > account.anchorDate && date <= now { deltas[other, default: 0] += entry.delta(for: other) }
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
        // Credit principal is reserved once as debt. A credit-repayment plan only changes its payment date.
        let repayments = Set(ledger.plans.filter { $0.nature == .repayment }.map(\.id))
        let commitments = occurrences.filter { !$0.inflow && !($0.planID.map { repayments.contains($0) } ?? false) }
        let committed = commitments.reduce(Int64(0)) { $0 + $1.amount }
        let goals = ledger.goals.reduce(Int64(0)) { $0 + $1.reserved }
        let daily = estimatedDailyLiving(ledger, now: now)
        let living = daily * Int64(horizon)
        // An unresolved inflow after the most recent reconciliation is withheld until its nature is known.
        let uncertain = entries.filter { e in
            e.nature == .unknownIn && e.date <= now && accountsByID[e.accountID].map { e.date > $0.anchorDate && ($0.kind == .cash || $0.kind == .bank) } == true
        }.reduce(Int64(0)) { $0 + $1.amount }
        let emergency = ledger.profile.floorAmount ?? 0
        let available = cash - debt - committed - goals - emergency - living - uncertain
        let expectedIncome = occurrences.filter(\.inflow).reduce(Int64(0)) { $0 + $1.amount }
        var warnings: [String] = []
        if accounts.isEmpty { warnings.append("先添加账户并核对余额，才能判断可动用资金。") }
        if accounts.contains(where: { !$0.reconciled }) { warnings.append("有账户尚未核对余额，资金判断仅供参考。") }
        if accounts.contains(where: { now.timeIntervalSince($0.anchorDate) > 14 * 86400 }) { warnings.append("部分余额已超过 14 天未核对；请确认没有遗漏账单。") }
        if entries.contains(where: { $0.nature.uncertain }) { warnings.append("有资金性质待明确；余额核对后新增的未知流入已保守扣除，历史未知仍需核对用途。") }
        if occurrences.contains(where: \.overdue) { warnings.append("有已到期但未登记完成的安排，仍计入预留。") }
        if entries.contains(where: { $0.nature.paired && $0.otherAccountID == nil }) { warnings.append("有内部移动尚未关联另一账户，可以问余白协助核对，避免重复计算。") }
        let baseline = cash - debt - goals - emergency - uncertain
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
                     occurrences: occurrences, points: points, warnings: warnings)
    }
    public static func spendingAmount(_ entry: Entry, ledger: Ledger) -> Int64 {
        if entry.nature == .expense {
            if let personal = entry.personalExpense { return personal }
            if let rentID = entry.rentID, let rent = ledger.rents.first(where: { $0.id == rentID }), rent.monthlyTotal > 0 {
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
    public static func assessPurchase(_ ledger: Ledger, amount: Int64, now: Date = Date()) -> PurchaseAssessment {
        let f = funds(ledger, now: now); let after = f.available - amount
        let incomplete = ledger.accounts.isEmpty || ledger.accounts.contains { !$0.reconciled } || !f.warnings.isEmpty
        let severity = after < 0 ? 2 : (incomplete || amount > max(0, f.available) / 3 ? 1 : 0)
        let title = after < 0 ? "这笔购买会挤占已安排的资金" : (incomplete ? "资金有空间，但先核对这些依据" : "已知安排内，可以承受")
        let explanation = after < 0 ? "扣除已知义务和预留后，还差 \(Money.text(-after))。可以降低金额、延后购买，或明确调整某项安排。" : "购买后仍有 \(Money.text(after)) 的保守余量。这个判断不把未到账收入或投资市值当作现金。"
        return PurchaseAssessment(title: title, explanation: explanation, afterPurchase: after, severity: severity,
                                  facts: ["当前现金 \(Money.text(f.cash))", "信用待还 \(Money.text(f.debt))", "未来 \(observationDays) 天已知付款 \(Money.text(f.committed))", "目标、应急与生活预留 \(Money.text(f.goals + f.emergency + f.living))"] + f.warnings,
                                  questions: ["它具体解决什么经常发生的问题？", "现有物品能否满足同样需要？", "如果等 48 小时，还会同样想买吗？"])
    }
}
