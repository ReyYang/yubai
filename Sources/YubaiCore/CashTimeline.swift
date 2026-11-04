import Foundation

public struct CashTimelineEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Signed movement of cash/bank balances, in cents.
    public var amount: Int64
    public var date: Date
}

public struct CashTimelinePoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var balance: Int64
    public var lower: Int64
    public var upper: Int64
    public var events: [CashTimelineEvent]
}

/// Consecutive vertices can share a date: fixed receipts/payments jump vertically
/// without smearing across days. The line never invents a lower intraday balance
/// than the daily minimum by spending an income day's allowance before receipt.
public struct CashTimelineVertex: Identifiable, Equatable, Sendable {
    public var id: Int
    public var date: Date
    public var balance: Int64
    public var lower: Int64
    public var upper: Int64
}

public struct CashTimelineWindow: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var isDefault: Bool
    public var history: [CashTimelinePoint]
    public var forecast: [CashTimelinePoint]
    public var forecastLine: [CashTimelineVertex]
    public var minimum: CashTimelinePoint?
    public var floor: Int64?
    public var belowFloor: Bool {
        guard let floor, let minimum else { return false }
        return minimum.balance < floor
    }
    public var showsZero: Bool { (history + forecast).contains { $0.lower < 0 } }
    /// Fractions of the complete scrollable date range, for a passive indicator.
    public var indicatorStart: Double
    public var indicatorLength: Double

    public func point(on date: Date) -> CashTimelinePoint? {
        let day = Dates.day(date)
        // Today reads the actual balance; its outstanding bills are forecast events.
        return history.first { $0.date == day } ?? forecast.first { $0.date == day }
    }
}

public struct CashTimeline: Equatable, Sendable {
    public var today: Date
    public var start: Date
    public var end: Date
    public var defaultStart: Date
    public var dailyLiving: Int64
    public var floor: Int64?
    /// Closing daily cash balances; today is the balance at `now`.
    public var history: [CashTimelinePoint]
    /// Today includes outstanding due/overdue items, after the actual anchor.
    public var forecast: [CashTimelinePoint]
    public var forecastLine: [CashTimelineVertex]

    public var visibleDays: Int { Dates.calendar.dateComponents([.day], from: defaultStart, to: end).day ?? 0 }

    /// Fixed-width calendar window. No imported history can extend the three-month
    /// bound and no drag can extend beyond the forecast horizon.
    public func window(startingAt requested: Date? = nil) -> CashTimelineWindow {
        let first = max(start, min(defaultStart, Dates.day(requested ?? defaultStart)))
        let last = min(end, Dates.addDays(visibleDays, to: first))
        let actual = history.filter { $0.date >= first && $0.date <= last }
        let predicted = forecast.filter { $0.date >= first && $0.date <= last }
        let isDefault = first == defaultStart
        let candidates = isDefault ? (history.filter { $0.date == today } + predicted) : (actual + predicted)
        // Earliest date wins tied minima, including flat/no-spending histories.
        let minimum = candidates.min { $0.balance == $1.balance ? $0.date < $1.date : $0.balance < $1.balance }
        let total = max(1, Dates.calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        let offset = Dates.calendar.dateComponents([.day], from: start, to: first).day ?? 0
        return CashTimelineWindow(start: first, end: last, isDefault: isDefault, history: actual, forecast: predicted,
                                  forecastLine: forecastLine.filter { $0.date >= first && $0.date <= last },
                                  minimum: minimum, floor: floor,
                                  indicatorStart: Double(offset) / Double(total),
                                  indicatorLength: Double(visibleDays) / Double(total))
    }
}

extension Finance {
    public static func cashTimeline(_ ledger: Ledger, now: Date = Date(), days: Int = observationDays) -> CashTimeline {
        cashTimeline(ledger, funds: funds(ledger, now: now, days: days), now: now)
    }

    /// `funds` must come from the same ledger/now; the app reuses its existing cache.
    public static func cashTimeline(_ ledger: Ledger, funds: Funds, now: Date) -> CashTimeline {
        let today = Dates.day(now), start = Dates.addMonths(-3, to: Dates.day(now))
        let end = max(today, Dates.day(funds.horizonEnd))
        let cashIDs = Set(ledger.accounts.filter { $0.kind == .cash || $0.kind == .bank }.map(\.id))
        var deltas: [Date: Int64] = [:], actualEvents: [Date: [CashTimelineEvent]] = [:]
        for entry in ledger.activeEntries {
            var movements: [Date: Int64] = [:]
            var legs = [entry.accountID]
            if entry.nature.paired, let other = entry.otherAccountID, other != entry.accountID { legs.append(other) }
            for id in legs where cashIDs.contains(id) {
                let posting = entry.postingDate(for: id), day = Dates.day(entry.postingDate(for: id))
                guard posting <= now, day >= start else { continue }
                movements[day, default: 0] += entry.delta(for: id)
            }
            for (day, amount) in movements {
                deltas[day, default: 0] += amount
                if amount != 0 && (entry.nature == .income || entry.planID != nil || entry.rentID != nil) {
                    actualEvents[day, default: []].append(CashTimelineEvent(id: entry.id.uuidString + Dates.text(day), title: entry.displayTitle, amount: amount, date: day))
                }
            }
        }
        // Deliberately include pre-reconciliation entries: they reconstruct history,
        // rather than changing today's reconciled anchor a second time.
        var history: [CashTimelinePoint] = [], balance = funds.cash, day = today
        while day >= start {
            let events = (actualEvents[day] ?? []).sorted { $0.id < $1.id }
            history.append(CashTimelinePoint(date: day, balance: balance, lower: balance, upper: balance, events: events))
            balance -= deltas[day, default: 0]
            day = Dates.addDays(-1, to: day)
        }
        history.reverse()

        let daily = estimatedDailyLiving(ledger, now: now)
        let days = Dates.calendar.dateComponents([.day], from: today, to: end).day ?? 0
        let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
        let plans = Dictionary(uniqueKeysWithValues: ledger.plans.map { ($0.id, $0) })
        let rents = Dictionary(uniqueKeysWithValues: ledger.rents.map { ($0.id, $0) })
        // Future-dated linked entries have not reached today's cash balance. Do not
        // let payment matching suppress their scheduled movement before posting.
        var paidLedger = ledger
        paidLedger.entries = ledger.entries.filter { $0.date <= now }
        var scheduled: [Date: [CashTimelineEvent]] = [:]
        for item in occurrences(in: paidLedger, now: now, days: days + 1) where Dates.day(item.date) <= end {
            let plan = item.planID.flatMap { plans[$0] }
            let accountID = plan?.accountID ?? item.rentID.flatMap { rents[$0]?.accountID }
            // Credit purchases do not move cash until repayment. Repayment itself
            // moves cash on its date; debt is never deducted from the anchor.
            if let accountID, accounts[accountID] != nil, !cashIDs.contains(accountID), plan?.nature != .repayment { continue }
            let date = max(today, Dates.day(item.date))
            scheduled[date, default: []].append(CashTimelineEvent(id: item.id, title: item.title,
                                                                 amount: item.inflow ? item.amount : -item.amount,
                                                                 date: Dates.day(item.date)))
        }
        var forecast: [CashTimelinePoint] = []
        var line = [CashTimelineVertex(id: 0, date: today, balance: funds.cash, lower: funds.cash, upper: funds.cash)]
        balance = funds.cash
        for offset in 0...days {
            let date = Dates.addDays(offset, to: today)
            let living = offset > 0 ? daily : 0
            // ±25% is a scenario range for daily living, not a statistical interval.
            // Known receipts/payments translate both bounds by exactly their amount.
            let spread = daily * Int64(offset) / 4
            let events = (scheduled[date] ?? []).sorted { $0.id < $1.id }
            let movement = events.reduce(Int64(0)) { $0 + $1.amount }
            if movement > 0 {
                // Credit the day's net receipt before its living allowance. Drawing
                // a pre-payday daily deduction first would invent an intraday trough
                // below every daily balance, contradicting the minimum readout.
                let priorSpread = daily * Int64(max(0, offset - 1)) / 4
                line.append(CashTimelineVertex(id: line.count, date: date, balance: balance, lower: balance - priorSpread, upper: balance + priorSpread))
                balance += movement
                line.append(CashTimelineVertex(id: line.count, date: date, balance: balance, lower: balance - priorSpread, upper: balance + priorSpread))
                balance -= living
                if living > 0 {
                    line.append(CashTimelineVertex(id: line.count, date: date, balance: balance, lower: balance - spread, upper: balance + spread))
                }
            } else {
                balance -= living
                line.append(CashTimelineVertex(id: line.count, date: date, balance: balance, lower: balance - spread, upper: balance + spread))
                balance += movement
                if !events.isEmpty {
                    line.append(CashTimelineVertex(id: line.count, date: date, balance: balance, lower: balance - spread, upper: balance + spread))
                }
            }
            forecast.append(CashTimelinePoint(date: date, balance: balance, lower: balance - spread, upper: balance + spread, events: events))
        }
        return CashTimeline(today: today, start: start, end: end, defaultStart: Dates.addMonths(-2, to: today), dailyLiving: daily,
                            floor: ledger.profile.floorAmount, history: history, forecast: forecast, forecastLine: line)
    }
}
