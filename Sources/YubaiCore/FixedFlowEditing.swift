import Foundation

public struct FixedFlowEdit: Equatable, Sendable {
    public var title: String; public var amount: Int64; public var frequency: Frequency; public var date: Date
    public var accountID: UUID?; public var category: String; public var installments: Int?
    public var intoFixedSavings = false
    public var autoPay: Bool; public var estimated: Bool; public var inflow: Bool; public var stopped: Bool
}

public enum FixedFlowEditError: LocalizedError, Equatable, Sendable {
    case noChanges
    public var errorDescription: String? { "没有改动。" }
}

extension FixedFlows {
    /// Installments always means the total, including retained linked periods.
    public static func edit(planID: UUID, in ledger: Ledger, now: Date = Date()) -> FixedFlowEdit? {
        guard let plan = ledger.plans.first(where: { $0.id == planID }) else { return nil }
        let payments = FixedFlowPayments(in: ledger, now: now)
        let end = Date(timeIntervalSince1970: 7_258_118_400)
        let schedule = plan.schedule(through: end)
        let pending = schedule.first { !plan.isSkipped(on: $0.date) && payments.remaining(for: plan, on: $0.date) > 0 }
        let date: Date
        if let pending { date = pending.date }
        else {
            var unlimited = plan; unlimited.installments = nil; unlimited.endDate = nil
            let boundary = max(Dates.day(now), Dates.day(schedule.last?.date ?? now))
            date = unlimited.nextScheduledDate(after: Dates.addDays(1, to: boundary).addingTimeInterval(-0.001)) ?? plan.dueDate
        }
        return FixedFlowEdit(title: plan.title, amount: payments.amount(for: plan), frequency: plan.frequency,
                             date: Dates.day(date), accountID: plan.accountID,
                             category: plan.category, installments: plan.installments, intoFixedSavings: plan.intoFixedSavings, autoPay: plan.autoPay,
                             estimated: plan.estimated, inflow: plan.inflow,
                             stopped: !plan.active || ((plan.stoppedAt ?? plan.endDate).map { $0 <= now } ?? false))
    }

    public static func categories(inflow: Bool, in ledger: Ledger) -> [String] {
        ledger.categoryNames(income: inflow)
    }

    public static func update(planID: UUID, title: String, amount: Int64, frequency: Frequency, date: Date,
                              accountID: UUID?, category: String, installments: Int?, autoPay: Bool, estimated: Bool,
                              in ledger: Ledger, now: Date = Date(), intoFixedSavings: Bool? = nil) throws -> ChangeSet {
        guard let old = ledger.plans.first(where: { $0.id == planID }), let edit = edit(planID: planID, in: ledger, now: now) else {
            throw YubaiError.invalid("找不到要修改的安排。")
        }
        guard validDate(date), validDate(now) else { throw YubaiError.invalid("资金安排的日期无效。") }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title != edit.title || amount != edit.amount || frequency != edit.frequency || Dates.day(date) != edit.date ||
                accountID != edit.accountID || category != edit.category || installments != edit.installments ||
                autoPay != edit.autoPay || estimated != edit.estimated || (intoFixedSavings ?? old.intoFixedSavings) != old.intoFixedSavings else { throw FixedFlowEditError.noChanges }
        var plan = old
        plan.title = title
        plan.intoFixedSavings = plan.inflow && plan.nature == .income && (intoFixedSavings ?? old.intoFixedSavings)
        // Saving another field must not overwrite an estimate's stored fallback.
        if amount != edit.amount || estimated != edit.estimated { plan.amount = amount }
        plan.frequency = frequency; plan.accountID = accountID; plan.category = category
        plan.installments = installments; plan.autoPay = autoPay; plan.estimated = estimated
        if frequency != edit.frequency || Dates.day(date) != edit.date {
            plan.dueDate = Dates.day(date)
            plan.monthlyDay = frequency == .monthly ? Dates.calendar.component(.day, from: date) : nil
        }
        plan = try replacement(plan, replacing: old, amountChanged: amount != edit.amount, in: ledger, now: now)
        var change = ChangeSet(source: "用户操作", reason: "修改安排「\(plan.title)」", items: [.updatePlan(plan)])
        change.createdAt = now
        var preview = ledger; try change.apply(to: &preview)
        return change
    }

    private static func validDate(_ date: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970) }

    static func validateUpdateFields(_ plan: Plan) throws {
        guard !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw YubaiError.invalid("安排名字不能为空。") }
        guard plan.amount > 0, plan.amount <= Money.limit else { throw YubaiError.invalid("安排金额必须大于零且在有效范围内。") }
        guard validDate(plan.dueDate), plan.endDate.map(validDate) ?? true, plan.stoppedAt.map(validDate) ?? true,
              plan.autoPaySince.map(validDate) ?? true, plan.estimatedAmountSince.map(validDate) ?? true,
              plan.previousOccurrences.allSatisfy(validDate), plan.settledOccurrences.allSatisfy(validDate),
              plan.skippedOccurrences.allSatisfy(validDate) else { throw YubaiError.invalid("资金安排的日期无效。") }
        guard plan.installments.map({ $0 > 0 }) ?? true else { throw YubaiError.invalid("共几期必须大于零。") }
        guard plan.monthlyDay.map({ (1...31).contains($0) && plan.frequency == .monthly }) ?? true else { throw YubaiError.invalid("资金安排的日期无效。") }
        guard !plan.autoPay || plan.accountID != nil else { throw YubaiError.invalid("自动记需要选择账户。") }
    }

    static func validateUpdate(_ proposed: Plan, replacing old: Plan, in ledger: Ledger) throws {
        try validateUpdateFields(proposed)
        guard proposed.inflow == old.inflow, proposed.nature.inflow == old.nature.inflow else {
            throw YubaiError.invalid("不能把要付改为要收，或把要收改为要付。")
        }
        guard proposed.accountID == nil || ledger.accounts.contains(where: { $0.id == proposed.accountID }) else {
            throw YubaiError.invalid("资金安排的账户不存在。")
        }
    }

    private static func replacement(_ proposed: Plan, replacing old: Plan, amountChanged: Bool, in ledger: Ledger, now: Date) throws -> Plan {
        try validateUpdate(proposed, replacing: old, in: ledger)
        var plan = proposed; plan.title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let payments = FixedFlowPayments(in: ledger, now: now)
        let linked = payments.plans.keys.filter { $0.id == old.id && old.occurrenceIndex(on: $0.day) != nil }
        plan.settledOccurrences = Array(Set(old.settledOccurrences + linked.filter {
            !old.isSkipped(on: $0.day) && payments.remaining(for: old, on: $0.day) == 0
        }.map(\.day))).sorted()
        let rescheduled = Dates.day(plan.dueDate) != Dates.day(old.dueDate) || plan.frequency != old.frequency || plan.monthlyDay != old.monthlyDay
        if rescheduled { plan.occurrenceDateOverrides = nil }
        plan.previousOccurrences = rescheduled ? Array(Set(old.previousOccurrences + linked.map(\.day))).sorted() : old.previousOccurrences
        if let total = plan.installments {
            guard total >= plan.previousOccurrences.count else { throw YubaiError.invalid("共几期不能少于已保留的期数。") }
        }
        if rescheduled || plan.installments != old.installments {
            plan.skippedOccurrences = old.skippedOccurrences.filter { plan.occurrenceIndex(on: $0) != nil }
        }
        guard linked.allSatisfy({ plan.occurrenceIndex(on: $0.day) != nil }) else { throw YubaiError.invalid("共几期不能移除已经记过的期。") }
        plan.autoPaySince = plan.autoPay && !old.autoPay ? Dates.day(now) : old.autoPaySince
        plan.estimatedAmountSince = plan.estimated && amountChanged ? now : old.estimatedAmountSince
        return plan
    }

    static func describeUpdate(_ plan: Plan, in ledger: Ledger) -> String {
        guard let old = ledger.plans.first(where: { $0.id == plan.id }) else { return "修改安排「\(plan.title)」" }
        var fields: [String] = []
        let payments = FixedFlowPayments(in: ledger)
        if old.title != plan.title { fields.append("名字：\(old.title) → \(plan.title)") }
        if payments.amount(for: old) != payments.amount(for: plan) { fields.append("金额：\(Money.text(payments.amount(for: old))) → \(Money.text(payments.amount(for: plan)))") }
        if old.dueDate != plan.dueDate || old.frequency != plan.frequency || old.monthlyDay != plan.monthlyDay {
            fields.append("日期/频率：\(Dates.text(old.dueDate)) \(old.frequency.label) → \(Dates.text(plan.dueDate)) \(plan.frequency.label)")
        }
        if old.accountID != plan.accountID { fields.append("账户：\(old.accountID.map { ledger.accountName($0) } ?? "未指定") → \(plan.accountID.map { ledger.accountName($0) } ?? "未指定")") }
        if old.category != plan.category { fields.append("分类：\(Classification.displayCategory(old.category)) → \(Classification.displayCategory(plan.category))") }
        if old.installments != plan.installments { fields.append("共几期：\(old.installments.map(String.init) ?? "一直") → \(plan.installments.map(String.init) ?? "一直")") }
        if old.autoPay != plan.autoPay { fields.append("自动记：\(plan.autoPay ? "开" : "关")") }
        if old.estimated != plan.estimated { fields.append("金额会变：\(plan.estimated ? "开" : "关")") }
        if old.intoFixedSavings != plan.intoFixedSavings { fields.append("存着不动：\(plan.intoFixedSavings ? "开" : "关")") }
        return "修改安排「\(plan.title)」" + (fields.isEmpty ? "" : "，" + fields.joined(separator: "，"))
    }
}
