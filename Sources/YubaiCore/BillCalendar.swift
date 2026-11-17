import Foundation

public struct BillCalendarDay: Identifiable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var bills: [FixedFlowOccurrence]
    public var payday: Bool
    public var yearly: Bool
}
public struct BillCalendarMonth: Sendable {
    public var month: Date
    public var leadingDays: Int
    public var weekdaySymbols: [String]
    public var days: [BillCalendarDay]
    public var remaining: Int64
    public var unpaidCount: Int
    public var paid: Int64
    public var yearlyMonths: Set<Int>
    public init(containing date: Date, in ledger: Ledger, now: Date, calendar system: Calendar = .current) {
        var calendar = Dates.calendar
        calendar.firstWeekday = system.firstWeekday
        month = calendar.dateInterval(of: .month, for: date)!.start
        leadingDays = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        weekdaySymbols = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        let rows = FixedFlows.month(containing: date, in: ledger, asOf: now).occurrences
        let plans = Dictionary(uniqueKeysWithValues: ledger.plans.map { ($0.id, $0) })
        let count = calendar.range(of: .day, in: .month, for: date)!.count
        let start = month
        days = (0..<count).map { offset in
            let day = Dates.addDays(offset, to: start)
            let bills = rows.filter { Dates.day($0.date) == day }.sorted {
                if $0.inflow != $1.inflow { return !$0.inflow }
                return $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title
            }
            return BillCalendarDay(date: day, bills: bills, payday: bills.contains { row in
                guard let plan = row.planID.flatMap({ plans[$0] }) else { return false }
                return plan.inflow && plan.nature == .income && (plan.category == "工资" || plan.category == "工资奖金" || plan.title.contains("工资"))
            }, yearly: bills.contains { $0.planID.flatMap { plans[$0] }?.frequency == .yearly })
        }
        let outgoing = rows.filter { !$0.inflow }
        remaining = outgoing.filter { $0.state != .paid }.reduce(0) { $0 + $1.amount }
        unpaidCount = outgoing.filter { $0.state != .paid }.count
        let payments = FixedFlowPayments(in: ledger, now: now)
        paid = outgoing.reduce(Int64(0)) { total, row in
            if let id = row.planID { return total + payments.plans[FixedFlowPaymentKey(id: id, day: Dates.day(row.date)), default: 0] }
            if let id = row.rentID { return total + payments.rentPaid[FixedFlowPaymentKey(id: id, day: Dates.day(row.date)), default: 0] }
            return total
        }
        let year = calendar.dateInterval(of: .year, for: date)!
        yearlyMonths = Set(ledger.plans.filter { $0.active && !$0.inflow && $0.frequency == .yearly }.flatMap { plan in
            plan.schedule(through: year.end.addingTimeInterval(-0.001)).filter { $0.date >= year.start && !plan.isSkipped(on: $0.date) }.map { calendar.component(.month, from: $0.date) }
        })
    }
}
