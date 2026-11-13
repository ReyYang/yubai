import Foundation

public struct YearlyBillReserve: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var due: Date
    public var monthly: Int64
    public var reserved: Int64
}

public enum YearlyBillReserves {
    /// A full year uses twelfths. A newly added near-term bill catches up over
    /// the months remaining, including its due month. Rounding stays per bill.
    /// Accumulated envelopes remain withheld across cycles, outside savings.
    public static func rows(in ledger: Ledger, now: Date, committedThrough: Date? = nil) -> [YearlyBillReserve] {
        guard ledger.preferences.yearlyBillsSetAside != false else { return [] }
        let calendar = Dates.calendar, today = Dates.day(now)
        let month = calendar.dateInterval(of: .month, for: today)!.start
        let payments = FixedFlowPayments(in: ledger, now: now)
        return ledger.plans.compactMap { plan in
            guard plan.active, plan.stoppedAt == nil, !plan.inflow, plan.nature == .expense, plan.frequency == .yearly else { return nil }
            let end = Dates.addMonths(24, to: today)
            guard let due = plan.schedule(through: end).first(where: {
                !plan.isSkipped(on: $0.date) && payments.remaining(for: plan, on: $0.date) > 0
            })?.date else { return nil }
            let dueMonth = calendar.dateInterval(of: .month, for: due)!.start
            let since = calendar.dateInterval(of: .month, for: plan.yearlyReserveSince ?? now)!.start
            let start = max(since, Dates.addMonths(-11, to: dueMonth))
            let months = max(1, (calendar.dateComponents([.month], from: start, to: dueMonth).month ?? 0) + 1)
            let amount = payments.amount(for: plan)
            let monthly = (amount + Int64(months) - 1) / Int64(months)
            let elapsed = max(0, min(months, (calendar.dateComponents([.month], from: start, to: month).month ?? 0) + 1))
            // In the due month (or when a payday cycle already contains it),
            // the full unpaid occurrence is the sole deduction.
            let covered = dueMonth <= month || committedThrough.map { Dates.day(due) <= Dates.day($0) } == true
            return YearlyBillReserve(id: plan.id, title: plan.title, due: due, monthly: monthly,
                                     reserved: covered ? 0 : min(amount, monthly * Int64(elapsed)))
        }.sorted { $0.due == $1.due ? $0.id.uuidString < $1.id.uuidString : $0.due < $1.due }
    }
    public static func setEnabled(_ enabled: Bool, in ledger: inout Ledger, now: Date) {
        if enabled && ledger.preferences.yearlyBillsSetAside == false {
            for index in ledger.plans.indices where ledger.plans[index].frequency == .yearly { ledger.plans[index].yearlyReserveSince = Dates.day(now) }
        }
        ledger.preferences.yearlyBillsSetAside = enabled
    }
}
