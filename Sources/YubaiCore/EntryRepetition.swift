import Foundation

extension EntryKeypad {
    /// The highlighted amount is replaced by a digit/decimal, but edited in
    /// place by delete/operators. Also used on a copy to predict touch feedback.
    public mutating func press(_ key: String, replacingAmount: Bool) {
        if replacingAmount && (key == "." || (key.count == 1 && "0123456789".contains(key))) { reset() }
        press(key)
    }
}

extension ManualBookkeeping {
    /// Input is already sorted by recency. Stop as soon as the visible chips
    /// are filled, excluding every category and small-item display name.
    public static func recentPurposes(sortedEntries: [Entry], categories: [Category], limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }
        let names = Set([Classification.pendingCategory, Classification.displayCategory(Classification.pendingCategory)]
                        + categories.flatMap { [$0.name, Classification.displayCategory($0.name)] + $0.subcategories })
        var seen = Set<String>(); var result: [String] = []
        for entry in sortedEntries where entry.deletedAt == nil {
            let text = (entry.purpose ?? entry.title).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !names.contains(text), seen.insert(text).inserted else { continue }
            result.append(text)
            if result.count == limit { break }
        }
        return result
    }
}

extension FixedFlows {
    public static func monthlyPlan(from entry: Entry) throws -> Plan {
        guard entry.nature != .transfer else { throw YubaiError.invalid("转账不能重复。") }
        guard entry.amount > 0, entry.amount <= Money.limit else { throw YubaiError.invalid("请核对金额。") }
        let purpose = (entry.purpose ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var plan = Plan(title: purpose.isEmpty ? Classification.displayCategory(entry.category) : purpose,
                        amount: entry.amount, dueDate: Dates.day(entry.date), frequency: .monthly,
                        inflow: entry.nature.inflow, category: entry.category, nature: entry.nature)
        plan.monthlyDay = Dates.calendar.component(.day, from: entry.date)
        plan.accountID = entry.accountID
        plan.intoFixedSavings = entry.intoFixedSavings
        return plan
    }

    /// The first payment and its plan are applied/undone as one ChangeSet.
    public static func monthlyEntryChange(amount: Int64, nature: Nature, accountID: UUID, day: Date,
                                          purpose: String, category: String, now: Date = Dates.now, intoFixedSavings: Bool = false) throws -> ChangeSet {
        var entry = Entry(date: day, amount: amount, nature: nature, accountID: accountID, title: category, category: category, intoFixedSavings: intoFixedSavings)
        entry.purpose = purpose
        let plan = try monthlyPlan(from: entry)
        var change = try ManualBookkeeping.change(amount: amount, nature: nature, accountID: accountID, day: day,
                                                  purpose: purpose, category: category, link: (plan.id, plan.dueDate), now: now, intoFixedSavings: intoFixedSavings)
        change.items.insert(.addPlan(plan), at: 0)
        return change
    }

    /// Caller uses a single store.update; failed validation leaves both intact.
    public static func repeatMonthly(_ edited: Entry, in ledger: inout Ledger) throws {
        guard let original = ledger.entries.first(where: { $0.id == edited.id && $0.deletedAt == nil }) else {
            throw YubaiError.invalid("记录已移除。")
        }
        guard original.planID == nil, edited.planID == nil else { throw YubaiError.invalid("这笔已有固定收付。") }
        let plan = try monthlyPlan(from: edited)
        var entry = edited; entry.planID = plan.id; entry.occurrence = plan.dueDate
        var next = ledger; next.plans.append(plan)
        try ManualBookkeeping.edit(entry, in: &next)
        ledger = next
    }
}
