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
        ledger.paydayConfirmSince = plan.nextScheduledDate(after: Dates.day(now)).map(Dates.day)
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
            guard let occurrence = entry.occurrence else { continue }
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
        let starts: [Date] = periods.compactMap { day in day < Dates.day(since) ? day : confirmations[day] }.sorted()
        let start = starts.last { $0 <= today } ?? scheduled.start
        if let nextStart = starts.first(where: { $0 > start && $0 > today }) {
            // A known next actual start closes historical dates even if a missed
            // scheduled payday lies between them.
            return CycleInfo(start: start, end: Dates.addDays(-1, to: nextStart), payday: true,
                             nextPayday: nextStart, known: true)
        }
        let late = periods.first { $0 > start && $0 <= today && $0 >= Dates.day(since) && confirmations[$0] == nil }
            ?? periods.first { $0 == today && $0 == start && $0 >= Dates.day(since) && confirmations[$0] == nil }
        let next = periods.first { $0 > max(start, today) } ?? Dates.addDays(1, to: scheduled.end)
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
        let lastConfirmed = paid.max()
        guard let day = plan.schedule(through: Dates.addDays(1, to: today).addingTimeInterval(-0.001)).map({ Dates.day($0.date) })
            .first(where: { day in day >= since && (lastConfirmed.map { day > $0 } ?? true) && !plan.isSkipped(on: day) && !paid.contains(day) }) else { return nil }
        return Due(planID: plan.id, occurrence: day, title: plan.title, usual: FixedFlowPayments(in: ledger).amount(for: plan),
                   lateDays: Dates.calendar.dateComponents([.day], from: day, to: today).day ?? 0)
    }

    public static func confirm(_ due: Due, amount: Int64, extraToSavings: Bool, accountID: UUID?, in ledger: inout Ledger, now: Date) throws {
        guard amount > 0, amount <= Money.limit, let plan = ledger.plans.first(where: { $0.id == due.planID && $0.active }),
              plan.inflow, plan.nature == .income, plan.occurrenceIndex(on: due.occurrence) != nil, !plan.isSkipped(on: due.occurrence),
              !ledger.entries.contains(where: { $0.deletedAt == nil && $0.nature == .income && $0.planID == due.planID && $0.occurrence.map(Dates.day) == Dates.day(due.occurrence) }) else {
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
        next.entries.append(entry)
        if extra > 0 {
            var saved = Entry(date: now, amount: extra, nature: .income, accountID: account, title: plan.title,
                              category: plan.category, intoFixedSavings: true)
            saved.planID = due.planID; saved.occurrence = Dates.day(due.occurrence); saved.recordedAt = now
            next.entries.append(saved)
        }
        if let index = next.plans.firstIndex(where: { $0.id == due.planID }) {
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
