import Foundation

extension Finance {
    public struct CycleInfo: Equatable, Sendable {
        public var start: Date; public var end: Date; public var payday: Bool
        public var lateSince: Date?; public var nextPayday: Date?; public var known: Bool
    }

    public static func anchorPlan(in ledger: Ledger, now: Date) -> Plan? {
        var source = ledger
        if ledger.cycleAnchor == .payday { source.plans.removeAll { $0.frequency != .monthly } }
        guard let next = nextPayday(in: source, now: now) else { return nil }
        return source.plans.filter { $0.active && $0.inflow && $0.nature == .income && $0.frequency != .once && $0.title == next.title }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first { $0.occurrenceIndex(on: next.date) != nil }
    }

    public static func enablePaydayConfirmation(_ ledger: inout Ledger, now: Date) {
        guard ledger.paydayConfirmSince == nil, let plan = anchorPlan(in: ledger, now: now) else { return }
        ledger.paydayConfirmSince = plan.nextScheduledDate(after: Dates.day(now)).map { plan.originalOccurrenceDate(on: $0) }
    }

    /// All actual starts are derived from the full ledger, including later
    /// confirmations, so asking for a historical date gives a closed interval.
    public static func cycleInfo(in ledger: Ledger, now: Date) -> CycleInfo {
        let scheduled = scheduledCycle(in: ledger, now: now)
        let known = ledger.cycleAnchor == .calendarMonth || anchorPlan(in: ledger, now: now) != nil
        guard ledger.cycleAnchor != .calendarMonth, let since = ledger.paydayConfirmSince,
              let plan = anchorPlan(in: ledger, now: now) else {
            return CycleInfo(start: scheduled.start, end: scheduled.end, payday: scheduled.payday,
                             nextPayday: scheduled.payday ? Dates.addDays(1, to: scheduled.end) : nil, known: known)
        }
        let today = Dates.day(now)
        var confirmations: [Date: Date] = [:]
        for entry in ledger.entries where entry.deletedAt == nil && entry.nature == .income && entry.planID == plan.id {
            // A future-dated record made at this evaluation instant is pending.
            // Later actual confirmations still close retrospective intervals.
            guard !(entry.date > now && entry.recordedAt.map { $0 <= now } == true),
                  let occurrence = entry.occurrence else { continue }
            let key = Dates.day(occurrence), date = Dates.day(entry.date)
            confirmations[key] = min(confirmations[key] ?? date, date)
        }
        // Include future confirmed periods for historical end boundaries, and a
        // scheduled predecessor even when the arrangement was only just created.
        let through = max(Dates.addDays(366, to: today), confirmations.keys.max() ?? today)
        var periods = plan.schedule(through: through).map { Dates.day($0.date) }
        periods.append(scheduled.start)
        periods.append(scheduledCycle(in: ledger, now: min(scheduled.start, Dates.day(since)).addingTimeInterval(-0.001)).start)
        periods = Array(Set(periods)).filter { !plan.isSkipped(on: $0) }.sorted()
        let starts: [(occurrence: Date, date: Date)] = periods.compactMap { day in
            let original = plan.originalOccurrenceDate(on: day)
            let actual = original < Dates.day(since) ? day : confirmations[day]
            return actual.map { (original, $0) }
        }.sorted { $0.date == $1.date ? $0.occurrence < $1.occurrence : $0.date < $1.date }
        let current = starts.last { $0.date <= today }
        let start = current?.date ?? scheduled.start
        if let nextStart = starts.first(where: { candidate in
            candidate.date > today && (current.map { candidate.occurrence > $0.occurrence } ?? true)
        }) {
            // A known next actual start closes historical dates even if a missed
            // scheduled payday lies between them.
            return CycleInfo(start: start, end: Dates.addDays(-1, to: nextStart.date), payday: true,
                             nextPayday: nextStart.date, known: true)
        }
        // An early arrival consumes its scheduled occurrence. Compare period
        // identities, not actual start dates, for both overdue and next paydays.
        let remaining = periods.filter { day in
            let original = plan.originalOccurrenceDate(on: day)
            return confirmations[day] == nil && (current.map { original > $0.occurrence } ?? true)
        }
        let late = remaining.first { $0 <= today && plan.originalOccurrenceDate(on: $0) >= Dates.day(since) }
        let next = remaining.first { $0 > max(start, today) } ?? Dates.addDays(1, to: scheduled.end)
        return CycleInfo(start: start, end: late == nil ? Dates.addDays(-1, to: next) : today,
                         payday: true, lateSince: late, nextPayday: late == nil ? next : nil, known: true)
    }

    public static func cycle(in ledger: Ledger, now: Date = Date()) -> (start: Date, end: Date, payday: Bool) {
        let info = cycleInfo(in: ledger, now: now)
        return (info.start, info.end, info.payday)
    }
}

public enum Payday {
    public struct Due: Equatable, Sendable {
        public var planID: UUID; public var occurrence: Date; public var title: String; public var usual: Int64; public var lateDays: Int
    }
    public struct Preview: Equatable, Sendable { public var delta: Int64; public var cycleBudget: Int64 }

    public static func due(in ledger: Ledger, now: Date) -> Due? {
        guard ledger.cycleAnchor != .calendarMonth, let plan = Finance.anchorPlan(in: ledger, now: now) else { return nil }
        let today = Dates.day(now)
        let paid = Set(ledger.entries.filter { $0.deletedAt == nil && $0.nature == .income && $0.planID == plan.id && $0.date <= now }
            .compactMap { $0.occurrence.map(Dates.day) })
        let since = ledger.paydayConfirmSince.map(Dates.day) ?? today
        let lastConfirmed = paid.map { plan.originalOccurrenceDate(on: $0) }.max()
        guard let day = plan.schedule(through: Dates.addDays(1, to: today).addingTimeInterval(-0.001)).map({ Dates.day($0.date) })
            .first(where: { day in plan.originalOccurrenceDate(on: day) >= since &&
                (lastConfirmed.map { plan.originalOccurrenceDate(on: day) > $0 } ?? true) &&
                !plan.isSkipped(on: day) && !paid.contains(day) }) else { return nil }
        return Due(planID: plan.id, occurrence: day, title: plan.title, usual: FixedFlowPayments(in: ledger, now: now).amount(for: plan),
                   lateDays: Dates.calendar.dateComponents([.day], from: day, to: today).day ?? 0)
    }

    public static func confirm(_ due: Due, amount: Int64, extraToSavings: Bool, accountID: UUID?, in ledger: inout Ledger, now: Date) throws {
        guard amount > 0, amount <= Money.limit, let plan = ledger.plans.first(where: { $0.id == due.planID && $0.active }),
              plan.inflow, plan.nature == .income, plan.occurrenceIndex(on: due.occurrence) != nil, !plan.isSkipped(on: due.occurrence),
              !ledger.entries.contains(where: { $0.deletedAt == nil && $0.date <= now && $0.nature == .income && $0.planID == due.planID && $0.occurrence.map(Dates.day) == Dates.day(due.occurrence) }) else {
            throw YubaiError.invalid("找不到这期固定收付。")
        }
        guard let account = accountID ?? plan.accountID ?? ManualBookkeeping.defaultAccount(in: ledger)?.id else {
            throw YubaiError.invalid("先添加一个收付款账户。")
        }
        let extra = extraToSavings ? max(0, amount - due.usual) : 0
        var entry = Entry(date: now, amount: amount - extra, nature: .income, accountID: account, title: plan.title,
                          category: plan.category, intoFixedSavings: plan.intoFixedSavings)
        entry.planID = due.planID; entry.occurrence = Dates.day(due.occurrence); entry.recordedAt = now
        var next = ledger
        let pending = next.entries.filter { $0.deletedAt == nil && $0.date > now && $0.nature == .income && $0.planID == due.planID && $0.occurrence.map(Dates.day) == Dates.day(due.occurrence) }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        if let original = pending.first { entry.id = original.id }
        let pendingIDs = Set(pending.map(\.id))
        next.entries.removeAll { pendingIDs.contains($0.id) }
        next.entries.append(entry)
        if extra > 0 {
            var saved = Entry(date: now, amount: extra, nature: .income, accountID: account, title: plan.title,
                              category: plan.category, intoFixedSavings: true)
            saved.planID = due.planID; saved.occurrence = Dates.day(due.occurrence); saved.recordedAt = now
            next.entries.append(saved)
        }
        if let index = next.plans.firstIndex(where: { $0.id == due.planID }),
           !next.plans[index].settledOccurrences.contains(where: { Dates.day($0) == Dates.day(due.occurrence) }) {
            next.plans[index].settledOccurrences.append(Dates.day(due.occurrence))
        }
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
    }

    public static func preview(_ due: Due, amount: Int64, extraToSavings: Bool, in ledger: Ledger, now: Date) -> Preview {
        var projected = ledger
        try? confirm(due, amount: amount, extraToSavings: extraToSavings, accountID: nil, in: &projected, now: now)
        Savings.closeCycles(&projected, now: now)
        let funds = Finance.funds(projected, now: now)
        return Preview(delta: amount - due.usual, cycleBudget: Finance.pace(projected, now: now)?.budget ?? funds.available)
    }
}
