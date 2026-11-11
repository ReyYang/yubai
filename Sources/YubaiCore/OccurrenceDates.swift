import Foundation

extension FixedFlows {
    /// `occurrence` is the currently displayed date, including an earlier move.
    public static func moveOccurrence(planID: UUID, occurrence: Date, to date: Date, in ledger: inout Ledger, now: Date) throws {
        try changeOccurrenceDate(planID: planID, occurrence: occurrence, replacement: date, in: &ledger, now: now)
    }

    public static func clearOccurrenceMove(planID: UUID, occurrence: Date, in ledger: inout Ledger, now: Date) throws {
        try changeOccurrenceDate(planID: planID, occurrence: occurrence, replacement: nil, in: &ledger, now: now)
    }

    private static func changeOccurrenceDate(planID: UUID, occurrence: Date, replacement: Date?, in ledger: inout Ledger, now: Date) throws {
        guard let index = ledger.plans.firstIndex(where: { $0.id == planID }),
              ledger.plans[index].occurrenceIndex(on: occurrence) != nil,
              replacement.map({ validOverrideDate($0) }) ?? true else { throw YubaiError.invalid("找不到这期固定收付。") }
        var next = ledger, plan = next.plans[index]
        let old = Dates.day(occurrence)
        let original = plan.occurrenceDateOverrides?.first { Dates.day($0.value) == old }?.key ?? old
        let new = replacement.map(Dates.day) ?? original
        var overrides = plan.occurrenceDateOverrides ?? [:]
        overrides.removeValue(forKey: original)
        if new != original { overrides[original] = new }
        plan.occurrenceDateOverrides = overrides.isEmpty ? nil : overrides
        plan.skippedOccurrences = plan.skippedOccurrences.map { Dates.day($0) == old ? new : $0 }
        plan.settledOccurrences = plan.settledOccurrences.map { Dates.day($0) == old ? new : $0 }
        try validateDateOverrides(plan)
        next.plans[index] = plan
        for i in next.entries.indices where next.entries[i].planID == planID && next.entries[i].occurrence.map(Dates.day) == old {
            next.entries[i].occurrence = new
        }
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
    }

    private static func validOverrideDate(_ date: Date) -> Bool {
        (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970)
    }
    static func validateDateOverrides(_ plan: Plan) throws {
        guard let overrides = plan.occurrenceDateOverrides, !overrides.isEmpty else { return }
        var base = plan; base.occurrenceDateOverrides = nil; base.endDate = nil
        guard overrides.count <= 2400, overrides.allSatisfy({ original, replacement in
            validOverrideDate(original) && validOverrideDate(replacement) && original == Dates.day(original) &&
            replacement == Dates.day(replacement) && base.occurrenceIndex(on: original) != nil
        }) else { throw YubaiError.invalid("资金安排的日期无效。") }
        // Two periods on the same day cannot be identified by the existing API.
        let dates = base.baseSchedule(through: max(overrides.keys.max()!, overrides.values.max()!)).map {
            Dates.day(overrides[Dates.day($0.date)] ?? $0.date)
        }
        guard Set(dates).count == dates.count else { throw YubaiError.invalid("资金安排的日期无效。") }
    }
}
