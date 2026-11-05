import Foundation

public struct CashTimelineEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Signed cash/bank movement, in cents; internal same-day transfers cancel.
    public var amount: Int64
    public var date: Date
    public var isSalary = false
    public var isRecurring = false
}

public struct CashTimelinePoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var balance: Int64
    public var events: [CashTimelineEvent]
}

/// Duplicate dates preserve known bill steps without interpolating across days.
public struct CashTimelineVertex: Identifiable, Equatable, Sendable {
    public var id: Int
    public var date: Date
    public var balance: Int64
}

public struct CashTimelineCycle: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var previousStart: Date
    public var previousEnd: Date
}

public struct CashTimelineWindow: Equatable, Sendable {
    public var cycle: CashTimelineCycle
    public var isDefault: Bool
    public var history: [CashTimelinePoint]
    public var forecast: [CashTimelinePoint]
    public var forecastLine: [CashTimelineVertex]
    /// Dates are projected onto this cycle by elapsed calendar days, not M/D.
    public var previous: [CashTimelinePoint]
    public var floor: Int64?
    public var previousClosingBalance: Int64?
    public var start: Date { cycle.start }
    public var end: Date { cycle.end }
    public var endpoint: CashTimelinePoint? { forecast.last ?? history.last }
    public var belowFloor: Bool {
        guard isDefault, let floor, let endpoint else { return false }
        return endpoint.balance < floor
    }
    public var showsZero: Bool { (history + forecast + previous).contains { $0.balance < 0 } }
    public var points: [CashTimelinePoint] { history + forecast.filter { $0.date > (history.last?.date ?? .distantPast) } }
    public func point(on date: Date) -> CashTimelinePoint? { points.first { $0.date == Dates.day(date) } }
    public func previousPoint(on date: Date) -> CashTimelinePoint? { previous.first { $0.date == Dates.day(date) } }
    /// Current cycle compares today's actual cash; completed cycles compare closing cash.
    public var difference: Int64? {
        guard let actual = history.last, let prior = isDefault ? previousPoint(on: actual.date)?.balance : previousClosingBalance else { return nil }
        return actual.balance - prior
    }
    public var averageSpending: Int64 {
        let out = history.flatMap(\.events).filter { $0.amount < 0 }.reduce(Int64(0)) { $0 - $1.amount }
        let days = max(1, (Dates.calendar.dateComponents([.day], from: start, to: history.last?.date ?? start).day ?? 0) + 1)
        return out / Int64(days)
    }
    /// Display candidates only: all events remain available to scrubbing and AI.
    public var annotations: [CashTimelineEvent] {
        let average = averageSpending
        return Array(history.flatMap(\.events).filter {
            $0.isSalary || ($0.amount < 0 && ($0.isRecurring || -$0.amount >= average * 3))
        }.sorted {
            abs($0.amount) == abs($1.amount) ? $0.id < $1.id : abs($0.amount) > abs($1.amount)
        }.prefix(4))
    }
}

public struct CashTimeline: Equatable, Sendable {
    public var today: Date
    /// Earliest allowed cycle start (three calendar months before today).
    public var start: Date
    public var hasPayday: Bool
    /// Newest first. The comparison preceding the oldest selectable cycle is read-only.
    public var cycles: [CashTimelineCycle]
    public var dailyLiving: Int64
    public var floor: Int64?
    public var history: [CashTimelinePoint]
    public var forecast: [CashTimelinePoint]
    public var forecastLine: [CashTimelineVertex]
    public var end: Date { cycles[0].end }
    public var defaultStart: Date { cycles[0].start }

    public func window(cycleOffset: Int = 0) -> CashTimelineWindow {
        let index = min(max(0, cycleOffset), cycles.count - 1), cycle = cycles[index]
        let actual = history.filter { $0.date >= cycle.start && $0.date <= cycle.end }
        let predicted = index == 0 ? forecast : []
        let count = Dates.calendar.dateComponents([.day], from: cycle.start, to: cycle.end).day ?? 0
        let previous = history.filter { $0.date >= cycle.previousStart && $0.date <= cycle.previousEnd }.compactMap { point -> CashTimelinePoint? in
            let offset = Dates.calendar.dateComponents([.day], from: cycle.previousStart, to: point.date).day ?? 0
            guard offset <= count else { return nil }
            var aligned = point; aligned.date = Dates.addDays(offset, to: cycle.start)
            return aligned
        }
        return CashTimelineWindow(cycle: cycle, isDefault: index == 0, history: actual, forecast: predicted,
                                  forecastLine: index == 0 ? forecastLine : [], previous: previous, floor: floor,
                                  previousClosingBalance: history.first { $0.date == cycle.previousEnd }?.balance)
    }
}

/// A small deterministic 1/2/5 scale shared by plotting and tests. Values are yuan.
public struct CashTimelineScale: Equatable, Sendable {
    public var domain: ClosedRange<Double>
    public var ticks: [Double]
    public init(window: CashTimelineWindow) {
        var values = (window.history + window.forecast + window.previous).map { Double($0.balance) / 100 }
        values += window.forecastLine.map { Double($0.balance) / 100 }
        if window.belowFloor, let floor = window.floor { values.append(Double(floor) / 100) }
        let low = min(0, values.min() ?? 0), high = max(0, values.max() ?? 0)
        let span = max(1, high - low), raw = span / 4
        let power = pow(10, floor(log10(raw)))
        let steps: [Double] = [power, 2 * power, 5 * power, 10 * power]
        let step: Double = steps.first { value in
            let intervals = ceil(high / value) - floor(low / value)
            return intervals <= 4
        } ?? (power * 10)
        let bottom = floor(low / step) * step
        let top = max(bottom + 2 * step, ceil(high / step) * step)
        ticks = stride(from: bottom, through: top + step * 0.001, by: step).map { $0 }
        domain = (bottom - step * 0.08)...(top + step * 0.22)
    }
    public static func label(_ value: Double) -> String {
        let magnitude = abs(value), sign = value < 0 ? "−" : ""
        let divisor: Double = magnitude >= 1_000_000 ? 1_000_000 : (magnitude >= 1000 ? 1000 : 1)
        let suffix = divisor == 1_000_000 ? "m" : (divisor == 1000 ? "k" : "")
        return sign + String(format: "%g", magnitude / divisor) + suffix
    }
}

extension Finance {
    public static func cashTimeline(_ ledger: Ledger, now: Date = Date(), days: Int = observationDays) -> CashTimeline {
        cashTimeline(ledger, funds: funds(ledger, now: now, days: days), now: now)
    }

    /// Reuses the app's funds anchor and payday; recognition never creates a plan.
    public static func cashTimeline(_ ledger: Ledger, funds: Funds, now: Date) -> CashTimeline {
        let calendar = Dates.calendar
        let today = calendar.startOfDay(for: now), boundary = Dates.addMonths(-3, to: calendar.startOfDay(for: now))
        let entries = ledger.entries.lazy.filter { $0.deletedAt == nil }
        let cashIDs = Set(ledger.accounts.filter { $0.kind == .cash || $0.kind == .bank }.map(\.id))
        var candidate = SalaryDetection.candidate(in: ledger, now: now)
        let salaryPlan = ledger.plans.filter { $0.active && $0.inflow && $0.nature == .income && $0.frequency != .once }
            .sorted { $0.id.uuidString < $1.id.uuidString }.first { plan in
                guard let payday = funds.payday, let index = plan.occurrenceIndex(on: payday) else { return false }
                return !plan.isSkipped(on: plan.scheduledDate(at: index)) && plan.title == funds.paydayTitle
            }
        // Confirming salary deliberately does not rewrite old entries. Recover its
        // local evidence from a copy so their original company titles still match.
        if candidate == nil, let plan = salaryPlan, plan.frequency == .monthly {
            var detectionLedger = ledger
            detectionLedger.plans.removeAll { $0.active && $0.inflow && $0.nature == .income && $0.frequency == .monthly }
            if let evidence = SalaryDetection.candidate(in: detectionLedger, now: now),
               plan.accountID == nil || plan.accountID == evidence.accountID,
               abs(Double(evidence.amount) - Double(plan.amount)) <= Double(plan.amount) * 0.1 {
                candidate = evidence
            }
        }
        let salaryIDs = Set(candidate?.entryIDs ?? [])
        func isSalary(_ entry: Entry) -> Bool {
            guard entry.nature == .income else { return false }
            if salaryIDs.contains(entry.id) { return true }
            guard let plan = salaryPlan else { return false }
            return entry.planID == plan.id || (SalaryDetection.payerKey(entry.title) == SalaryDetection.payerKey(plan.title)
                && (plan.accountID == nil || entry.accountID == plan.accountID))
        }
        let salaryEntries = Array(entries.filter { isSalary($0) && cashIDs.contains($0.accountID) && $0.postingDate(for: $0.accountID) <= now })
        let hasPayday = salaryPlan != nil || candidate != nil
        let month = Dates.calendar.dateInterval(of: .month, for: today)!.start
        func monthly(_ offset: Int, day: Int) -> Date {
            let first = Dates.addMonths(offset, to: month)
            let last = Dates.calendar.range(of: .day, in: .month, for: first)!.count
            return Dates.addDays(min(max(1, day), last) - 1, to: first)
        }
        var nominal: [Date] = []
        if let plan = salaryPlan, let payday = funds.payday, let nextIndex = plan.occurrenceIndex(on: payday) {
            // Derive every date from the original schedule to avoid Feb/Mar drift.
            for offset in -1..<400 {
                let day = Dates.day(plan.scheduledDate(at: nextIndex - offset))
                if !plan.isSkipped(on: day) { nominal.append(day) }
                if nominal.count >= 3 && day < Dates.addMonths(-2, to: boundary) { break }
            }
        } else {
            let anchor = candidate?.dayOfMonth ?? 1
            nominal = (-6...1).map { monthly($0, day: anchor) }.reversed()
        }
        let spacing = nominal.count > 1 ? abs(Dates.calendar.dateComponents([.day], from: nominal[1], to: nominal[0]).day ?? 30) : 30
        let tolerance = max(1, min(15, spacing / 2 - 1))
        let boundaries = Array(Set(nominal.map { expected -> Date in
            guard hasPayday else { return expected }
            let nearby = salaryEntries.filter { abs(Dates.calendar.dateComponents([.day], from: expected, to: Dates.day($0.postingDate(for: $0.accountID))).day ?? 999) <= tolerance }
            return nearby.min { lhs, rhs in
                let a = abs(lhs.postingDate(for: lhs.accountID).timeIntervalSince(expected)), b = abs(rhs.postingDate(for: rhs.accountID).timeIntervalSince(expected))
                return a == b ? lhs.amount > rhs.amount : a < b
            }.map { Dates.day($0.postingDate(for: $0.accountID)) } ?? expected
        })).sorted()
        let currentIndex = boundaries.lastIndex { $0 <= today }!
        var cycles: [CashTimelineCycle] = []
        for index in stride(from: currentIndex, through: 1, by: -1) {
            let first = boundaries[index]
            if index != currentIndex && first < boundary { break }
            cycles.append(CashTimelineCycle(start: first, end: Dates.addDays(-1, to: boundaries[index + 1]),
                                            previousStart: boundaries[index - 1], previousEnd: Dates.addDays(-1, to: first)))
        }
        let historyStart = cycles.last!.previousStart, end = cycles[0].end
        let plans = Dictionary(uniqueKeysWithValues: ledger.plans.map { ($0.id, $0) })
        var deltas: [Date: Int64] = [:], actualEvents: [Date: [CashTimelineEvent]] = [:]
        // DateFormatter creation used to dominate this loop. Event IDs retain
        // their exact format, with one formatting operation per calendar day.
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy-MM-dd"
        var dayLabels: [Date: String] = [:]
        for entry in entries {
            var movements: [Date: Int64] = [:], legs = [entry.accountID]
            if entry.nature.paired, let other = entry.otherAccountID, other != entry.accountID { legs.append(other) }
            for id in legs where cashIDs.contains(id) {
                let posting = entry.postingDate(for: id)
                guard posting <= now, posting >= historyStart else { continue }
                let day = calendar.startOfDay(for: posting)
                movements[day, default: 0] += entry.delta(for: id)
            }
            let recurring = entry.rentID != nil || entry.planID.flatMap { plans[$0] }.map { $0.frequency != .once } == true
            for (day, amount) in movements {
                deltas[day, default: 0] += amount
                if amount != 0 {
                    let label = dayLabels[day] ?? formatter.string(from: day)
                    dayLabels[day] = label
                    actualEvents[day, default: []].append(CashTimelineEvent(id: entry.id.uuidString + label, title: entry.displayTitle,
                        amount: amount, date: day, isSalary: isSalary(entry), isRecurring: recurring))
                }
            }
        }
        // Pre-reconciliation entries only reconstruct history; today's reconciled
        // funds.cash remains the anchor, including archived cash/bank accounts.
        var history: [CashTimelinePoint] = [], balance = funds.cash, day = today
        while day >= historyStart {
            let events = (actualEvents[day] ?? []).sorted { abs($0.amount) == abs($1.amount) ? $0.id < $1.id : abs($0.amount) > abs($1.amount) }
            history.append(CashTimelinePoint(date: day, balance: balance, events: events))
            balance -= deltas[day, default: 0]; day = Dates.addDays(-1, to: day)
        }
        history.reverse()
        let daily = estimatedDailyLiving(ledger, now: now)
        let days = Dates.calendar.dateComponents([.day], from: today, to: end).day ?? 0
        let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
        let rents = Dictionary(uniqueKeysWithValues: ledger.rents.map { ($0.id, $0) })
        var paidLedger = ledger
        paidLedger.entries = ledger.entries.filter { $0.date <= now }
        var scheduled: [Date: [CashTimelineEvent]] = [:]
        for item in occurrences(in: paidLedger, now: now, days: days + 1)
            where Dates.day(item.date) >= cycles[0].start && Dates.day(item.date) <= end {
            let plan = item.planID.flatMap { plans[$0] }
            // Recognition/confirmation leaves old unlinked payroll untouched. An
            // observed receipt must not become a second outstanding salary. Linked
            // partial payments still use FixedFlowPayments' remaining amount.
            if let salaryPlan, plan?.id == salaryPlan.id,
               salaryEntries.contains(where: { entry in
                   (entry.planID != salaryPlan.id || entry.occurrence == nil)
                       && abs(Dates.calendar.dateComponents([.day], from: Dates.day(entry.date), to: Dates.day(item.date)).day ?? 999) <= tolerance
               }) { continue }
            let accountID = plan?.accountID ?? item.rentID.flatMap { rents[$0]?.accountID }
            if let accountID, accounts[accountID] != nil, !cashIDs.contains(accountID), plan?.nature != .repayment { continue }
            let date = max(today, Dates.day(item.date))
            scheduled[date, default: []].append(CashTimelineEvent(id: item.id, title: item.title,
                amount: item.inflow ? item.amount : -item.amount, date: Dates.day(item.date)))
        }
        var forecast: [CashTimelinePoint] = []
        var line = [CashTimelineVertex(id: 0, date: today, balance: funds.cash)]
        balance = funds.cash
        for offset in 0...max(0, days) {
            let date = Dates.addDays(offset, to: today)
            balance -= offset > 0 ? daily : 0
            line.append(CashTimelineVertex(id: line.count, date: date, balance: balance))
            let events = (scheduled[date] ?? []).sorted { abs($0.amount) == abs($1.amount) ? $0.id < $1.id : abs($0.amount) > abs($1.amount) }
            balance += events.reduce(Int64(0)) { $0 + $1.amount }
            if !events.isEmpty { line.append(CashTimelineVertex(id: line.count, date: date, balance: balance)) }
            forecast.append(CashTimelinePoint(date: date, balance: balance, events: events))
        }
        return CashTimeline(today: today, start: boundary, hasPayday: hasPayday, cycles: cycles, dailyLiving: daily,
                            floor: ledger.profile.floorAmount, history: history, forecast: forecast, forecastLine: line)
    }
}
