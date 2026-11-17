import Foundation

public struct UsualSpending: Equatable, Identifiable, Sendable {
    public var category: String
    public var subcategory: String?
    public var amount: Int64
    public var usual: Int64
    public var id: String { category + ":" + (subcategory ?? "") }
    public var title: String { subcategory ?? Classification.displayCategory(category) }
    public var difference: Int64 { amount - usual }
}

public struct MonthlyCharge: Equatable, Identifiable, Sendable {
    public var plan: Plan
    public var amount: Int64
    /// A separate, explicitly named visit/use entry. Paying a subscription does
    /// not establish that the service was used.
    public var lastUsed: Date?
    public var id: UUID { plan.id }
}

public struct SavingOpportunities: Equatable, Sendable {
    public var charges: [MonthlyCharge]
    public var comparisons: [UsualSpending]
    public var previousCycleCount: Int
    public var entryCount: Int
    public var spent: Int64
    public var chargesTotal: Int64 { charges.reduce(0) { $0 + $1.amount } }
}

public struct WishFunding: Equatable, Sendable {
    public var remainingAfterPurchase: Int64
    public var shortfall: Int64
    public var monthly: Int64?
    public var enoughOn: Date?
    public var progress: Double
}

public struct WeeklyReview: Equatable, Sendable {
    public var interval: DateInterval
    public var spending: Int64
    public var previousSpending: Int64
    public var largestCategory: String?
    public var largestAmount: Int64
    public var droppedWishes: Int64
}

public struct SpendingAnswer: Equatable, Sendable {
    public var comparisons: [UsualSpending]
    public var frequentPlace: CategoryPlace?
    public var conclusion: String
    public var hasPreviousCycle: Bool
}

public enum SavingInsights {
    public static func categoryShares(_ ledger: Ledger, during interval: DateInterval) -> [CashFlowSlice] {
        let rows = Finance.cashFlow(ledger, during: interval).spendingByCategory
        let total = rows.reduce(Int64(0)) { $0 + max(0, $1.amount) }
        return rows.map { row in
            CashFlowSlice(title: row.category, categories: [row.category], amount: row.amount,
                          share: total > 0 && row.amount > 0 ? Double(row.amount) / Double(total) : 0)
        }
    }
    public static func spendingAnswer(_ ledger: Ledger, now: Date) -> SpendingAnswer {
        let cycle = Finance.cycle(in: ledger, now: now)
        let flow = Finance.cashFlow(ledger, during: DateInterval(start: cycle.start, end: now.addingTimeInterval(0.001)))
        let categories = Array(flow.spendingByCategory.filter { $0.amount > 0 }.prefix(2))
        var comparisons: [UsualSpending] = []
        var place: CategoryPlace?
        var hasPreviousCycle = false
        for (index, category) in categories.enumerated() {
            let detail = Finance.categoryDetail(ledger, category: category.category, now: now, previousCycles: 1)
            hasPreviousCycle = hasPreviousCycle || detail.cycles.count > 1
            if index == 0 { place = detail.frequentPlaces.first }
            comparisons.append(UsualSpending(category: category.category, amount: category.amount, usual: detail.cycles.dropFirst().first?.amount ?? 0))
        }
        let conclusion: String
        if let first = comparisons.first, first.category == "餐饮", first.amount > flow.spending / 2,
           first.usual > first.amount {
            conclusion = "一大半吃掉了，但比上个月少。"
        } else if let first = comparisons.first {
            conclusion = "花得最多 · " + Classification.displayCategory(first.category)
        } else { conclusion = "还没有支出" }
        return SpendingAnswer(comparisons: comparisons, frequentPlace: place, conclusion: conclusion, hasPreviousCycle: hasPreviousCycle)
    }
    public static func wishSavings(_ ledger: Ledger, now: Date) -> (total: Int64, month: Int64) {
        let month = Dates.calendar.dateInterval(of: .month, for: now)!.start
        let wishes = ledger.wishlist.filter { $0.status == .dropped && $0.droppedAt.map { $0 <= now } == true }
        return (wishes.reduce(0) { $0 + $1.amount }, wishes.filter { $0.droppedAt! >= month }.reduce(0) { $0 + $1.amount })
    }
    public static func opportunities(_ ledger: Ledger, now: Date) -> SavingOpportunities {
        let cycle = Finance.cycle(in: ledger, now: now)
        let past = Finance.pastCycles(ledger, now: now, limit: 3)
        let offset = max(0, Dates.calendar.dateComponents([.day], from: cycle.start, to: Dates.day(now)).day ?? 0) + 1
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let active = ledger.entries.filter { $0.deletedAt == nil && $0.date <= now }
        func totals(_ range: DateInterval) -> [String: UsualSpending] {
            var result: [String: UsualSpending] = [:]
            for entry in active where range.contains(entry.date) && (entry.nature == .expense || entry.nature == .refund) {
                let source = entry.nature == .refund ? entry.relatedEntryID.flatMap { lookup[$0] } ?? entry : entry
                guard source.planID == nil, source.rentID == nil, !source.isUnitemized else { continue }
                let choice = ledger.normalizedCategory(for: entry, entriesByID: lookup)
                guard !Classification.isPending(choice.category) else { continue }
                let key = choice.category + ":" + (choice.subcategory ?? "")
                var row = result[key] ?? UsualSpending(category: choice.category, subcategory: choice.subcategory, amount: 0, usual: 0)
                row.amount += Finance.spendingAmount(entry, ledger: ledger)
                result[key] = row
            }
            return result
        }
        let current = totals(DateInterval(start: cycle.start, end: now.addingTimeInterval(0.001)))
        var usual: [String: UsualSpending] = [:]
        for period in past {
            let range = DateInterval(start: period.start, end: min(period.end, Dates.addDays(offset, to: period.start)))
            for (key, row) in totals(range) {
                var value = usual[key] ?? UsualSpending(category: row.category, subcategory: row.subcategory, amount: 0, usual: 0)
                value.usual += row.amount; usual[key] = value
            }
        }
        let comparisons: [UsualSpending] = past.isEmpty ? [] : Set(current.keys).union(usual.keys).compactMap { key in
            guard var row = current[key] ?? usual[key] else { return nil }
            row.amount = current[key]?.amount ?? 0
            row.usual = Int64((Double(usual[key]?.usual ?? 0) / Double(past.count)).rounded())
            return row.difference == 0 ? nil : row
        }.sorted { abs($0.difference) == abs($1.difference) ? $0.id < $1.id : abs($0.difference) > abs($1.difference) }
        let payments = FixedFlowPayments(in: ledger, now: now)
        let charges = ledger.plans.compactMap { plan -> MonthlyCharge? in
            guard plan.active, !plan.inflow, plan.nature == .expense, plan.frequency == .monthly,
                  plan.stoppedAt == nil, plan.endDate.map({ $0 >= Dates.day(now) }) ?? true else { return nil }
            let key = CategoryMemory.key(plan.title)
            let lastUsed = active.filter { entry in
                guard entry.nature == .expense, entry.planID == nil, entry.rentID == nil else { return false }
                let title = CategoryMemory.key(entry.displayTitle)
                return !key.isEmpty && title != key && title.contains(key) && entry.amount != plan.amount
            }.map(\.date).max()
            return MonthlyCharge(plan: plan, amount: payments.amount(for: plan), lastUsed: lastUsed)
        }.sorted { $0.amount == $1.amount ? $0.id.uuidString < $1.id.uuidString : $0.amount > $1.amount }
        let spending = Finance.cashFlow(ledger, during: DateInterval(start: cycle.start, end: now.addingTimeInterval(0.001))).spending
        return SavingOpportunities(charges: charges, comparisons: comparisons, previousCycleCount: past.count,
                                   entryCount: active.count, spent: spending)
    }

    public static func funding(for wish: WishItem, ledger: Ledger, now: Date) -> WishFunding {
        let total = max(0, Reserve.overview(ledger, now: now).total)
        let shortfall = max(0, wish.amount - total)
        var monthly: Int64?, enoughOn: Date?
        // A share of irregular income has no promised arrival date.
        if case .fixed(let amount) = ledger.savingRule, amount > 0 {
            monthly = amount
            if shortfall > 0 {
                let periods = (shortfall - 1) / amount + 1
                let info = Finance.cycleInfo(in: ledger, now: now)
                if info.known, info.lateSince == nil, periods <= 1200 {
                    enoughOn = Dates.addMonths(Int(periods - 1), to: Dates.addDays(1, to: info.end))
                }
            }
        }
        return WishFunding(remainingAfterPurchase: total - wish.amount, shortfall: shortfall, monthly: monthly,
                           enoughOn: enoughOn, progress: wish.amount > 0 ? min(1, Double(total) / Double(wish.amount)) : 1)
    }

    public static func monthlyIncrease(_ ledger: Ledger, now: Date) -> Int64 {
        let start = Dates.calendar.dateInterval(of: .month, for: now)!.start
        return Reserve.overview(ledger, now: now).lines.filter { $0.date >= start && $0.date <= now }.reduce(0) { $0 + $1.amount }
    }

    public static func weekly(_ ledger: Ledger, now: Date) -> WeeklyReview {
        let week = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: Dates.addDays(-7, to: now))!
        let previous = DateInterval(start: Dates.addDays(-7, to: week.start), end: week.start)
        let flow = Finance.cashFlow(ledger, during: week)
        let top = flow.spendingByCategory.first
        let dropped = ledger.wishlist.filter { $0.status == .dropped && $0.droppedAt.map { week.contains($0) } == true }.reduce(Int64(0)) { $0 + $1.amount }
        return WeeklyReview(interval: week, spending: flow.spending, previousSpending: Finance.cashFlow(ledger, during: previous).spending,
                            largestCategory: top?.category, largestAmount: top?.amount ?? 0, droppedWishes: dropped)
    }
}
