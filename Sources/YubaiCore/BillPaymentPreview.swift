import Foundation

extension FixedFlows {
    /// The UI's explicit "paid" answer closes this occurrence at its actual
    /// amount. `settle` remains available to callers recording a partial payment.
    public static func confirmPayment(planID: UUID, occurrence: Date, amount: Int64? = nil, accountID: UUID? = nil,
                                      in ledger: Ledger, now: Date) throws -> ChangeSet {
        var change = try settle(planID: planID, occurrence: occurrence, amount: amount, accountID: accountID, in: ledger, now: now)
        guard var plan = ledger.plans.first(where: { $0.id == planID }) else { throw YubaiError.invalid("找不到这期固定收付。") }
        let day = Dates.day(occurrence)
        if !plan.settledOccurrences.contains(where: { Dates.day($0) == day }) { plan.settledOccurrences.append(day) }
        change.items.append(.updatePlan(plan))
        var preview = ledger; try change.apply(to: &preview)
        return change
    }
    public static func confirmRecordedPayment(planID: UUID, occurrence: Date, in ledger: inout Ledger, now: Date) throws {
        let day = Dates.day(occurrence), payments = FixedFlowPayments(in: ledger, now: now)
        guard let index = ledger.plans.firstIndex(where: { $0.id == planID }), ledger.plans[index].occurrenceIndex(on: day) != nil,
              payments.plans[FixedFlowPaymentKey(id: planID, day: day), default: 0] > 0 else { throw YubaiError.invalid("找不到原记录。") }
        var next = ledger
        if !next.plans[index].settledOccurrences.contains(where: { Dates.day($0) == day }) { next.plans[index].settledOccurrences.append(day) }
        try next.validate(); ledger = next
    }
    /// Run the same mutation as confirmation, so a matched entry's cash is
    /// never subtracted a second time and annual envelopes release correctly.
    public static func availableAfterPayment(planID: UUID, occurrence: Date, amount: Int64, matchedEntryID: UUID? = nil,
                                             in ledger: Ledger, now: Date) -> Int64? {
        var next = ledger
        do {
            if let matchedEntryID { try markPaid(planID: planID, occurrence: occurrence, with: matchedEntryID, in: &next) }
            else {
                var change = try confirmPayment(planID: planID, occurrence: occurrence, amount: amount, in: ledger, now: now)
                change.createdAt = now
                try change.apply(to: &next)
            }
            return Finance.funds(next, now: now).available
        } catch { return nil }
    }
}
