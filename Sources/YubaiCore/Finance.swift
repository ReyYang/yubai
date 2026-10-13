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
public struct PurchaseAssessment: Sendable {
    public var title: String; public var explanation: String; public var afterPurchase: Int64
    public var severity: Int; public var facts: [String]; public var questions: [String]
}

public enum Finance {
    public static func balance(_ account: Account, in ledger: Ledger, at: Date = Date()) -> Int64 {
        account.anchorBalance + ledger.entries.lazy.filter { $0.deletedAt == nil && $0.postingDate(for: account.id) > account.anchorDate && $0.postingDate(for: account.id) <= at }.reduce(Int64(0)) { $0 + $1.delta(for: account.id) }
    }
    public static func occurrences(in ledger: Ledger, now: Date = Date(), days: Int? = nil) -> [Occurrence] {
        let start = Dates.day(now); let end = Dates.addDays(days ?? ledger.preferences.horizonDays, to: start)
        let entries = ledger.activeEntries
        var result: [Occurrence] = []
        for p in ledger.plans where p.active {
            // Always derive from the original day (Jan 31 → Feb 28 → Mar 31), never chained dates.
            for index in 0..<2400 {
                let date = p.frequency.advance(p.dueDate, by: index)
                if date > end || (p.endDate != nil && date > p.endDate!) { break }
                let paid = entries.filter { $0.planID == p.id && $0.occurrence.map(Dates.day) == Dates.day(date) }.reduce(Int64(0)) { $0 + $1.amount }
                if paid < p.amount {
                    result.append(Occurrence(id: "\(p.id)-\(date.timeIntervalSince1970)", title: p.title, date: date, amount: p.amount - paid, inflow: p.inflow, planID: p.id, overdue: Dates.day(date) < start))
                }
                if p.frequency == .once { break }
            }
        }
        for r in ledger.rents where r.active {
            for index in 0..<240 {
                let due = Dates.addMonths(index * r.monthsPerPayment, to: r.nextDueDate)
                if due > end || (r.endDate != nil && Dates.day(due) > Dates.day(r.endDate!)) { break }
                let paid = entries.filter { $0.rentID == r.id && $0.nature == .expense && $0.rentPeriod.map(Dates.day) == Dates.day(due) }.reduce(Int64(0)) { $0 + $1.amount }
                let dueAmount = r.monthlyTotal * Int64(r.monthsPerPayment)
                if paid < dueAmount { result.append(Occurrence(id: "rent-\(r.id)-\(due.timeIntervalSince1970)", title: r.title, date: due, amount: dueAmount - paid, inflow: false, rentID: r.id, overdue: Dates.day(due) < start)) }
            }
            let firstMonth = Dates.calendar.date(from: Dates.calendar.dateComponents([.year, .month], from: r.startDate))!
            for index in 0..<1200 {
                let month = Dates.addMonths(index, to: firstMonth)
                let receiveDate = max(Dates.addDays(r.receiveDay - 1, to: month), r.startDate)
                if receiveDate > end || (r.endDate != nil && Dates.day(receiveDate) > Dates.day(r.endDate!)) { break }
                let paid = entries.filter { $0.rentID == r.id && $0.nature == .contribution && $0.rentPeriod.map { Dates.calendar.isDate($0, equalTo: month, toGranularity: .month) } == true }.reduce(Int64(0)) { $0 + $1.amount }
                let amount = r.monthlyTotal - r.personalShare - paid
                if amount > 0 { result.append(Occurrence(id: "share-\(r.id)-\(month.timeIntervalSince1970)", title: r.title + " · 应收分摊", date: receiveDate, amount: amount, inflow: true, rentID: r.id, overdue: Dates.day(receiveDate) < start, rentMonth: month)) }
            }
        }
        return result.sorted { $0.date < $1.date }
    }
    public static func funds(_ ledger: Ledger, now: Date = Date()) -> Funds {
        let accounts = ledger.accounts // Archived accounts still own money and obligations.
        let cash = accounts.filter { $0.kind == .cash || $0.kind == .bank }.reduce(Int64(0)) { $0 + balance($1, in: ledger, at: now) }
        let creditNet = accounts.filter { $0.kind == .credit }.reduce(Int64(0)) { $0 + balance($1, in: ledger, at: now) }
        let debt = accounts.filter { $0.kind == .credit }.reduce(Int64(0)) { $0 + max(0, -balance($1, in: ledger, at: now)) }
        let investment = accounts.filter { $0.kind == .investment }.reduce(Int64(0)) { $0 + balance($1, in: ledger, at: now) }
        let receivables = accounts.filter { $0.kind == .receivable }.reduce(Int64(0)) { $0 + balance($1, in: ledger, at: now) }
        let occurrences = occurrences(in: ledger, now: now)
        // Credit principal is reserved once as debt. A credit-repayment plan only changes its payment date.
        let commitments = occurrences.filter { !$0.inflow && !($0.planID.flatMap { id in ledger.plans.first { $0.id == id } }.map { $0.nature == .repayment } ?? false) }
        let committed = commitments.reduce(Int64(0)) { $0 + $1.amount }
        let goals = ledger.goals.reduce(Int64(0)) { $0 + $1.reserved }
        let living = ledger.preferences.dailyLiving * Int64(ledger.preferences.horizonDays)
        // An unresolved inflow after the most recent reconciliation is withheld until its nature is known.
        let uncertain = ledger.activeEntries.filter { e in
            e.nature == .unknownIn && e.date <= now && accounts.contains { $0.id == e.accountID && e.date > $0.anchorDate && ($0.kind == .cash || $0.kind == .bank) }
        }.reduce(Int64(0)) { $0 + $1.amount }
        let available = cash - debt - committed - goals - ledger.preferences.emergencyReserve - living - uncertain
        let expectedIncome = occurrences.filter(\.inflow).reduce(Int64(0)) { $0 + $1.amount }
        var warnings: [String] = []
        if accounts.isEmpty { warnings.append("先添加账户并核对余额，才能判断可动用资金。") }
        if accounts.contains(where: { !$0.reconciled }) { warnings.append("有账户尚未核对余额，资金判断仅供参考。") }
        if accounts.contains(where: { now.timeIntervalSince($0.anchorDate) > 14 * 86400 }) { warnings.append("部分余额已超过 14 天未核对；请确认没有遗漏账单。") }
        if ledger.activeEntries.contains(where: { $0.nature.uncertain }) { warnings.append("有资金性质待明确；余额核对后新增的未知流入已保守扣除，历史未知仍需核对用途。") }
        if occurrences.contains(where: \.overdue) { warnings.append("有已到期但未登记完成的安排，仍计入预留。") }
        if ledger.preferences.dailyLiving == 0 { warnings.append("尚未设置日常生活预留，未来零碎开销没有计入。") }
        if ledger.activeEntries.contains(where: { $0.nature.paired && $0.otherAccountID == nil }) { warnings.append("有内部移动尚未关联另一账户，请在账本中补全，避免重复计算。") }
        let baseline = cash - debt - goals - ledger.preferences.emergencyReserve - uncertain
        var points: [ForecastPoint] = []
        for offset in 0...ledger.preferences.horizonDays {
            let date = Dates.addDays(offset, to: Dates.day(now))
            let out = commitments.filter { Dates.day($0.date) <= date }.reduce(Int64(0)) { $0 + $1.amount }
            let incoming = occurrences.filter { $0.inflow && Dates.day($0.date) <= date }.reduce(Int64(0)) { $0 + $1.amount }
            let conservative = baseline - out - Int64(offset) * ledger.preferences.dailyLiving
            points.append(ForecastPoint(date: date, conservative: conservative, expected: conservative + incoming))
        }
        return Funds(cash: cash, debt: debt, investments: investment, receivables: receivables, netWorth: cash + creditNet + investment + receivables,
                     committed: committed, goals: goals, emergency: ledger.preferences.emergencyReserve, living: living,
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
    public static func review(_ ledger: Ledger, from: Date, through end: Date) -> Review {
        let rows = ledger.activeEntries.filter { $0.date >= from && $0.date < end }
        let prior = ledger.activeEntries.filter { $0.date >= from.addingTimeInterval(-end.timeIntervalSince(from)) && $0.date < from }
        let categories = Dictionary(grouping: rows.filter { $0.nature == .expense || $0.nature == .refund }, by: \.category)
        let byCategory = categories.map { name, entries in Breakdown(category: name, amount: entries.reduce(0) { $0 + spendingAmount($1, ledger: ledger) }, count: entries.count) }.sorted { $0.amount > $1.amount }
        return Review(spending: byCategory.reduce(0) { $0 + $1.amount }, income: rows.filter { $0.nature == .income }.reduce(0) { $0 + $1.amount },
                      refunds: rows.filter { $0.nature == .refund }.reduce(0) { $0 + $1.amount }, byCategory: byCategory,
                      previousSpending: prior.reduce(0) { $0 + spendingAmount($1, ledger: ledger) }, count: rows.count)
    }
    public static func assessPurchase(_ ledger: Ledger, amount: Int64, now: Date = Date()) -> PurchaseAssessment {
        let f = funds(ledger, now: now); let after = f.available - amount
        let incomplete = ledger.accounts.isEmpty || ledger.accounts.contains { !$0.reconciled } || !f.warnings.isEmpty
        let severity = after < 0 ? 2 : (incomplete || amount > max(0, f.available) / 3 ? 1 : 0)
        let title = after < 0 ? "这笔购买会挤占已安排的资金" : (incomplete ? "资金有空间，但先核对这些依据" : "已知安排内，可以承受")
        let explanation = after < 0 ? "扣除已知义务和预留后，还差 \(Money.text(-after))。可以降低金额、延后购买，或明确调整某项安排。" : "购买后仍有 \(Money.text(after)) 的保守余量。这个判断不把未到账收入或投资市值当作现金。"
        return PurchaseAssessment(title: title, explanation: explanation, afterPurchase: after, severity: severity,
                                  facts: ["当前现金 \(Money.text(f.cash))", "信用待还 \(Money.text(f.debt))", "未来 \(ledger.preferences.horizonDays) 天已知付款 \(Money.text(f.committed))", "目标、应急与生活预留 \(Money.text(f.goals + f.emergency + f.living))"] + f.warnings,
                                  questions: ["它具体解决什么经常发生的问题？", "现有物品能否满足同样需要？", "如果等 48 小时，还会同样想买吗？"])
    }
}
