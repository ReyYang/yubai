import Foundation

public struct PacePoint: Equatable, Sendable, Identifiable {
    public var id: Date { day }; public var day: Date; public var spent: Int64
}
public struct PaceBurst: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case weekend, lastDays(Int) }
    public var kind: Kind; public var amount: Int64; public var interval: DateInterval
}
public struct CyclePace: Equatable, Sendable {
    public var start: Date; public var end: Date; public var daysTotal: Int; public var daysLeft: Int
    public var available: Int64; public var morningAvailable: Int64; public var spent: Int64; public var budget: Int64
    public var baseDaily: Int64; public var evenToDate: Int64; public var daily: Int64?; public var overBy: Int64
    public var lateDays: Int?; public var isFast: Bool; public var burst: PaceBurst?; public var points: [PacePoint]
    public func dailyAfterSpending(_ amount: Int64) -> Int64? {
        guard daysLeft > 1, available >= 0, lateDays == nil else { return nil }
        return Finance.roundedDaily(max(0, available - amount), days: daysLeft - 1)
    }
}
extension Finance {
    static func roundedDaily(_ amount: Int64, days: Int) -> Int64 {
        let divisor = Int64(max(1, days))
        return (amount + divisor / 2) / divisor
    }
    public static func pace(_ ledger: Ledger, now: Date) -> CyclePace? {
        guard cycleInfo(in: ledger, now: now).known else { return nil }
        let funds = funds(ledger, now: now), today = Dates.day(now), calendar = Dates.calendar
        let daysTotal = max(1, (calendar.dateComponents([.day], from: funds.cycleStart, to: funds.cycleEnd).day ?? 0) + 1)
        let daysLeft = max(1, (calendar.dateComponents([.day], from: today, to: funds.cycleEnd).day ?? 0) + 1)
        let elapsed = max(0, calendar.dateComponents([.day], from: funds.cycleStart, to: today).day ?? 0)
        let dates = (0...elapsed + 1).map { Dates.addDays($0, to: funds.cycleStart) }
        var changes = Array(repeating: Int64(0), count: dates.count + 1)
        var todaySpent: Int64 = 0, spent: Int64 = 0
        let lookup = ledger.entries.contains { $0.deletedAt == nil && $0.nature == .refund } ? Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) }) : nil
        func index(_ date: Date) -> Int {
            var low = 0, high = dates.count
            while low < high { let mid = (low + high) / 2; if dates[mid] <= date { low = mid + 1 } else { high = mid } }
            return low - 1
        }
        for entry in ledger.entries where entry.deletedAt == nil && entry.date >= funds.cycleStart && entry.date <= now {
            let amount = SpendingParts.flexibleAmount(entry, in: ledger, entriesByID: lookup)
            guard amount != 0 else { continue }
            spent += amount
            // Reconciliation changes the known balance immediately, including
            // today's daily reference; it is not a purchase made this morning.
            if entry.date >= today && !entry.isUnitemized { todaySpent += amount }
            let last = min(elapsed, index(entry.date))
            if let from = entry.spreadFrom, from < Dates.day(entry.date) {
                let count = max(1, (calendar.dateComponents([.day], from: Dates.day(from), to: Dates.day(entry.date)).day ?? 0) + 1)
                let first = max(0, index(Dates.day(from)))
                if first <= last {
                    let share = amount / Int64(count)
                    changes[first] += share; changes[last + 1] -= share
                    changes[last] += amount % Int64(count); changes[last + 1] -= amount % Int64(count)
                }
            } else if last >= 0 {
                changes[last] += amount; changes[last + 1] -= amount
            }
        }
        var points: [PacePoint] = [], dayAmounts: [Int64] = [], dayAmount: Int64 = 0, cumulative: Int64 = 0
        for i in 0...elapsed {
            dayAmount += changes[i]; cumulative += dayAmount; dayAmounts.append(dayAmount)
            points.append(PacePoint(day: dates[i], spent: cumulative))
        }
        let budget = funds.available + spent, base = max(0, budget) / Int64(daysTotal)
        let divisor = Int64(daysTotal), wholeDays = Int64(elapsed)
        let even = (budget / divisor) * wholeDays + (budget % divisor) * wholeDays / divisor
        let difference = spent - even
        let fast = difference > 3 * base
        var burst: PaceBurst?
        if fast {
            let weekday = calendar.component(.weekday, from: today)
            let sinceSunday = (weekday - 1 + 7) % 7
            let sunday = Dates.addDays(-sinceSunday, to: today), saturday = Dates.addDays(-1, to: sunday)
            func sum(from start: Date, through end: Date) -> Int64 {
                let low = max(0, index(start)), high = min(elapsed, index(end))
                return low <= high ? dayAmounts[low...high].reduce(0, +) : 0
            }
            // On Saturday the current weekend is already the most recent one.
            let weekendStart = weekday == 7 ? today : saturday
            let weekendEnd = weekday == 7 ? Dates.addDays(1, to: today) : sunday
            let weekendAmount = sum(from: weekendStart, through: min(today, weekendEnd))
            if (weekday == 7 || sinceSunday <= 3), weekendEnd >= funds.cycleStart, weekendAmount >= (difference + 1) / 2 {
                burst = PaceBurst(kind: .weekend, amount: weekendAmount, interval: DateInterval(start: weekendStart, end: Dates.addDays(1, to: weekendEnd)))
            } else {
                let from = max(funds.cycleStart, Dates.addDays(-2, to: today))
                burst = PaceBurst(kind: .lastDays(3), amount: sum(from: from, through: today), interval: DateInterval(start: from, end: Dates.addDays(1, to: today)))
            }
        }
        let morning = funds.available + todaySpent
        return CyclePace(start: funds.cycleStart, end: funds.cycleEnd, daysTotal: daysTotal, daysLeft: daysLeft,
                         available: funds.available, morningAvailable: morning, spent: spent, budget: budget, baseDaily: base, evenToDate: even,
                         daily: funds.available < 0 || funds.salaryLateDays != nil ? nil : roundedDaily(max(0, morning), days: daysLeft),
                         overBy: max(0, -funds.available), lateDays: funds.salaryLateDays, isFast: fast, burst: burst, points: points)
    }
}
