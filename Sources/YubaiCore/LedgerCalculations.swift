import Foundation

/// Copies share read-only results until any stored ledger field changes. Neither
/// the cache nor its lock is encoded or included in Ledger equality.
final class LedgerCalculations: @unchecked Sendable {
    private let lock = NSLock()
    private var validatedZone: (current: TimeZone, formatter: TimeZone)?
    private var funds: (at: Date, expires: Date, zone: TimeZone, days: Int, value: Funds)?
    private var living: (day: Date, zone: TimeZone, value: Int64)?
    private var salary: (at: Date, expires: Date, zone: TimeZone, value: SalaryCandidate?)?
    var isValidated: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let validatedZone else { return false }
        return validatedZone.current == TimeZone.current && validatedZone.formatter == NSTimeZone.default
    }
    func markValidated() {
        lock.lock(); defer { lock.unlock() }; validatedZone = (TimeZone.current, NSTimeZone.default)
    }
    func cachedFunds(now: Date, days: Int) -> Funds? {
        lock.lock(); defer { lock.unlock() }
        guard let funds, funds.zone == .current, funds.days == days, now >= funds.at, now < funds.expires else { return nil }
        return funds.value
    }
    func storeFunds(_ value: Funds, in ledger: Ledger, now: Date, days: Int) {
        var expires = Dates.addDays(1, to: Dates.day(now))
        for entry in ledger.entries where entry.deletedAt == nil {
            if entry.date > now { expires = min(expires, entry.date) }
            if let date = entry.otherDate, date > now { expires = min(expires, date) }
        }
        for cover in ledger.cycleCovers where cover.date > now { expires = min(expires, cover.date) }
        for account in ledger.accounts {
            // The warning uses strict >, so equality must not reuse a cache.
            let stale = account.anchorDate.addingTimeInterval(14 * 86400)
            if stale >= now { expires = min(expires, stale) }
        }
        lock.lock(); defer { lock.unlock() }
        funds = (now, expires, .current, days, value)
    }
    func dailyLiving(on day: Date) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        return living.flatMap { $0.day == day && $0.zone == .current ? $0.value : nil }
    }
    func storeDailyLiving(_ value: Int64, day: Date) {
        lock.lock(); defer { lock.unlock() }; living = (day, .current, value)
    }
    func cachedSalary(now: Date) -> SalaryCandidate?? {
        lock.lock(); defer { lock.unlock() }
        guard let salary, salary.zone == .current, now >= salary.at, now < salary.expires else { return nil }
        return .some(salary.value)
    }
    func storeSalary(_ value: SalaryCandidate?, in ledger: Ledger, now: Date) {
        var expires = Dates.addDays(1, to: Dates.day(now))
        for entry in ledger.entries where entry.deletedAt == nil && entry.nature == .income && entry.date > now { expires = min(expires, entry.date) }
        lock.lock(); defer { lock.unlock() }; salary = (now, expires, .current, value)
    }
}
