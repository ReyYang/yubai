import Foundation

public enum CreditPaymentDate {
    public static func next(day: Int, now: Date) -> Date {
        let calendar = Dates.calendar
        let month = calendar.dateInterval(of: .month, for: now)!.start
        func date(_ month: Date) -> Date {
            let last = calendar.range(of: .day, in: .month, for: month)!.count
            return Dates.addDays(min(max(1, day), last) - 1, to: month)
        }
        let current = date(month)
        return current >= Dates.day(now) ? current : date(Dates.addMonths(1, to: month))
    }
}
