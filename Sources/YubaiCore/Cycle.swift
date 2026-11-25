import Foundation

extension Finance {
    public struct CycleInfo: Equatable, Sendable {
        public var start: Date; public var end: Date; public var payday: Bool
        public var lateSince: Date?; public var nextPayday: Date?; public var known: Bool
    }

    public static func anchorPlan(in ledger: Ledger, now: Date) -> Plan? {
        var source = ledger
        if ledger.cycleAnchor == .payday {
            source.plans.removeAll { $0.frequency != .monthly }
            var salaries = source
            salaries.plans = source.plans.filter(Payday.isSalaryPlan)
            if let anchor = scheduledAnchor(in: salaries, now: now) { return anchor }
        }
        return scheduledAnchor(in: source, now: now)
    }

    private static func scheduledAnchor(in source: Ledger, now: Date) -> Plan? {
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
        guard ledger.cycleAnchor != .calendarMonth, let plan = anchorPlan(in: ledger, now: now) else {
            return CycleInfo(start: scheduled.start, end: scheduled.end, payday: scheduled.payday,
                             nextPayday: scheduled.payday ? Dates.addDays(1, to: scheduled.end) : nil,
                             known: ledger.cycleAnchor == .calendarMonth)
        }
        guard let threshold = ledger.paydayConfirmSince else {
            return CycleInfo(start: scheduled.start, end: scheduled.end, payday: scheduled.payday,
                             nextPayday: scheduled.payday ? Dates.addDays(1, to: scheduled.end) : nil, known: true)
        }
        let today = Dates.day(now)
        var confirmations: [Date: Date] = [:]
        for entry in ledger.entries where entry.deletedAt == nil && entry.nature == .income && entry.planID == plan.id {
            let effective = entry.countsFromCycleStart ?? entry.date
            // A future-dated record made at this evaluation instant is pending.
            // Later actual confirmations still close retrospective intervals.
            guard !(effective > now && entry.recordedAt.map { $0 <= now } == true),
                  let occurrence = entry.occurrence else { continue }
            let key = Dates.day(occurrence), date = Dates.day(effective)
            confirmations[key] = min(confirmations[key] ?? date, date)
        }
        // Include future confirmed periods for historical end boundaries, and a
        // scheduled predecessor even when the arrangement was only just created.
        let through = max(Dates.addDays(366, to: today), confirmations.keys.max() ?? today)
        var periods = plan.schedule(through: through).map { Dates.day($0.date) }
        var since = Dates.day(threshold)
        // The former setup could enable confirmation a month too late. A
        // recorded predecessor and an unpaid current occurrence expose that gap.
        if ledger.cycleAnchor == .payday, Payday.isSalaryPlan(plan),
           let previous = periods.last(where: { plan.originalOccurrenceDate(on: $0) < since && !plan.isSkipped(on: $0) }),
           previous == scheduled.start, confirmations[previous] == nil,
           confirmations.contains(where: { $0.key < previous && $0.value <= today }),
           !ledger.entries.contains(where: { $0.deletedAt == nil && $0.planID == nil && $0.date <= now &&
               Dates.day($0.date) >= previous && Payday.isSalary($0) }) {
            since = plan.originalOccurrenceDate(on: previous)
        }
        periods += confirmations.keys
        periods.append(scheduled.start)
        periods.append(scheduledCycle(in: ledger, now: min(scheduled.start, since).addingTimeInterval(-0.001)).start)
        periods = Array(Set(periods)).filter { !plan.isSkipped(on: $0) }.sorted()
        let starts: [(occurrence: Date, date: Date)] = periods.compactMap { day in
            let original = plan.originalOccurrenceDate(on: day)
            let actual = confirmations[day] ?? (original < since ? day : nil)
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
        let late = remaining.first { $0 <= today && plan.originalOccurrenceDate(on: $0) >= since }
        let next = remaining.first { $0 > max(start, today) } ?? Dates.addDays(1, to: scheduled.end)
        return CycleInfo(start: start, end: late == nil ? Dates.addDays(-1, to: next) : today,
                         payday: true, lateSince: late, nextPayday: late == nil ? next : nil, known: true)
    }

    public static func cycle(in ledger: Ledger, now: Date = Dates.now) -> (start: Date, end: Date, payday: Bool) {
        let info = cycleInfo(in: ledger, now: now)
        return (info.start, info.end, info.payday)
    }
}

public enum Payday {
    public static let defaultDay = 10
    public struct Due: Equatable, Sendable {
        public var planID: UUID; public var occurrence: Date; public var title: String; public var usual: Int64; public var lateDays: Int
    }
    public struct Preview: Equatable, Sendable { public var delta: Int64; public var cycleBudget: Int64 }

    public static func nominalDate(day: Int, inMonthOf date: Date) -> Date {
        let calendar = Dates.calendar
        let month = calendar.dateInterval(of: .month, for: date)!.start
        let last = calendar.range(of: .day, in: .month, for: month)!.count
        return Dates.addDays(min(max(1, day), last) - 1, to: month)
    }

    static func isSalary(_ entry: Entry) -> Bool {
        entry.nature == .income && entry.subcategory != "奖金" &&
            (entry.subcategory == "工资" || entry.category == "工资" || entry.category == "工资奖金" || entry.displayTitle.contains("工资"))
    }

    static func isSalaryPlan(_ plan: Plan) -> Bool {
        plan.inflow && plan.nature == .income && plan.frequency == .monthly &&
            (["工资", "工资奖金"].contains(plan.category) || plan.title.contains("工资"))
    }

    static func isWithinArrivalWindow(_ date: Date, occurrence: Date) -> Bool {
        let day = Dates.day(date), due = Dates.day(occurrence)
        return due >= Dates.addDays(-25, to: day) && due <= Dates.addDays(10, to: day)
    }

    static func receiptOccurrence(for entry: Entry, plan: Plan, in ledger: Ledger) -> Date? {
        let day = Dates.day(entry.date)
        let end = Dates.addDays(11, to: day).addingTimeInterval(-0.001)
        let receipts = ledger.entries.filter { $0.deletedAt == nil && $0.planID == plan.id }
        let claimed = Set(receipts.compactMap { $0.occurrence.map(Dates.day) })
        let last = receipts.filter { $0.date <= entry.date }.compactMap { $0.occurrence.map { plan.originalOccurrenceDate(on: $0) } }.max()
        return plan.schedule(through: end).map { Dates.day($0.date) }.filter { occurrence in
            isWithinArrivalWindow(day, occurrence: occurrence) && !plan.isSkipped(on: occurrence) && !claimed.contains(occurrence) &&
                (last.map { plan.originalOccurrenceDate(on: occurrence) > $0 } ?? true)
        }.min {
            let a = abs($0.timeIntervalSince(day)), b = abs($1.timeIntervalSince(day))
            return a == b ? $0 < $1 : a < b
        }
    }

    /// Store settlement independently of the amount expected on the plan.
    static func recordReceipt(_ entry: Entry, planIndex: Int, in ledger: inout Ledger) {
        guard let occurrence = entry.occurrence.map(Dates.day) else { return }
        let original = ledger.plans[planIndex].originalOccurrenceDate(on: occurrence)
        if !ledger.plans[planIndex].settledOccurrences.contains(where: { Dates.day($0) == occurrence }) {
            ledger.plans[planIndex].settledOccurrences.append(occurrence)
        }
        if ledger.cycleAnchor == .payday {
            ledger.paydayConfirmSince = min(ledger.paydayConfirmSince ?? original, original)
        }
    }

    public static func configure(day: Int, amount: Int64, accountID: UUID, currentPeriodAvailable: Int64? = nil,
                                 in ledger: inout Ledger, now: Date) throws {
        guard (1...31).contains(day), (1...Money.limit).contains(amount),
              currentPeriodAvailable.map({ (1...Money.limit).contains($0) }) ?? true,
              ledger.accounts.contains(where: { $0.id == accountID && !$0.archived }),
              (-2_208_988_800...7_258_118_400).contains(now.timeIntervalSince1970) else {
            throw YubaiError.invalid("请核对发薪日、金额和账户。")
        }
        let today = Dates.day(now)
        let thisMonth = nominalDate(day: day, inMonthOf: today)
        let nextMonth = nominalDate(day: day, inMonthOf: Dates.addMonths(1, to: today))
        let previousMonth = nominalDate(day: day, inMonthOf: Dates.addMonths(-1, to: today))
        var next = ledger
        next.cycleAnchor = .payday
        let existing = Finance.anchorPlan(in: next, now: now).flatMap { isSalaryPlan($0) ? $0 : nil }
        let categories = next.categoryNames(income: true)
        let category = ["工资奖金", "工资", existing?.category, "其他收入"].compactMap { $0 }
            .first(where: categories.contains) ?? Classification.pendingCategory
        var plan = existing ?? Plan(title: "工资", amount: amount, dueDate: thisMonth, frequency: .monthly,
                                    inflow: true, category: category, nature: .income)
        let oldDay = plan.monthlyDay ?? Dates.calendar.component(.day, from: plan.dueDate)
        let oldThisMonth = nominalDate(day: oldDay, inMonthOf: today)
        let paidThisMonth = next.entries.contains {
            $0.deletedAt == nil && $0.date <= now && $0.planID == existing?.id &&
                $0.occurrence.map { plan.originalOccurrenceDate(on: $0) == oldThisMonth } == true
        }
        if oldDay != day { plan.dueDate = paidThisMonth ? nextMonth : thisMonth }
        else if Dates.day(plan.dueDate) > thisMonth { plan.dueDate = thisMonth }
        plan.title = "工资"; plan.category = category; plan.amount = amount; plan.accountID = accountID
        plan.monthlyDay = day; plan.autoPay = false; plan.estimated = false; plan.currency = .cny
        let index: Int
        if let existing, let found = next.plans.firstIndex(where: { $0.id == existing.id }) {
            plan = try FixedFlows.replacement(plan, replacing: existing, amountChanged: amount != existing.amount, in: next, now: now)
            index = found; next.plans[index] = plan
        } else {
            index = next.plans.count; next.plans.append(plan)
        }
        let firstRequired = paidThisMonth ? nextMonth : thisMonth
        next.paydayConfirmSince = min(next.paydayConfirmSince ?? firstRequired, firstRequired)
        if thisMonth < today, !paidThisMonth, !plan.isSkipped(on: thisMonth),
           let available = currentPeriodAvailable,
           Finance.spendableBreakdown(next, now: now).income == 0 {
            next.paydayConfirmSince = nextMonth
            var opening = Entry(date: thisMonth, amount: 0, nature: .income, accountID: accountID,
                                title: "本期起点", category: category)
            opening.planID = plan.id; opening.occurrence = thisMonth; opening.recordedAt = now
            if next.categories.contains(where: { $0.name == category && $0.income && $0.subcategories.contains("工资") }) {
                opening.subcategory = "工资"
            }
            next.entries.append(opening)
            let openingIndex = next.entries.count - 1
            next.entries[openingIndex].amount = try startingIncome(for: available, in: next, now: now)
            if !next.plans[index].settledOccurrences.contains(where: { Dates.day($0) == thisMonth }) {
                next.plans[index].settledOccurrences.append(thisMonth)
            }
        } else if !paidThisMonth {
            // Reuse a uniquely identifiable receipt recorded before setup.
            for occurrence in [previousMonth, thisMonth] where !plan.isSkipped(on: occurrence) {
                let candidates = next.entries.indices.filter { index in
                    let entry = next.entries[index]
                    guard entry.deletedAt == nil, entry.planID == nil, entry.rentID == nil, entry.date <= now,
                          isSalary(entry), isWithinArrivalWindow(entry.date, occurrence: occurrence) else { return false }
                    let date = Dates.day(entry.date)
                    return [previousMonth, thisMonth].min {
                        abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
                    } == occurrence
                }
                let hasReceipt = next.entries.contains {
                    $0.deletedAt == nil && $0.planID == plan.id && $0.occurrence.map {
                        Dates.calendar.isDate(plan.originalOccurrenceDate(on: $0), equalTo: occurrence, toGranularity: .month)
                    } == true
                }
                guard candidates.count == 1, let entryIndex = candidates.first, !hasReceipt else { continue }
                if plan.occurrenceIndex(on: occurrence) == nil {
                    guard occurrence == previousMonth else { continue }
                    next.plans[index].previousOccurrences.append(occurrence)
                }
                next.entries[entryIndex].planID = plan.id; next.entries[entryIndex].occurrence = occurrence
                if !next.plans[index].settledOccurrences.contains(occurrence) { next.plans[index].settledOccurrences.append(occurrence) }
            }
        }
        next.updatedAt = max(next.updatedAt, now)
        try next.validate()
        ledger = next
    }

    private static func startingIncome(for available: Int64, in ledger: Ledger, now: Date) throws -> Int64 {
        let base = Finance.spendableBreakdown(ledger, now: now)
        func remaining(after income: Int64) -> Int64 {
            base.rawR + base.plannedSaving + income -
                Finance.plannedSaving(in: ledger, income: base.income + income, cycleStart: base.cycleStart, now: now)
        }
        // Percentage saving rounds to cents. Find the first positive income
        // that yields the requested remainder using that same rounding rule.
        var lower: Int64 = 1, upper = Money.limit
        while lower < upper {
            let mid = lower + (upper - lower) / 2
            if remaining(after: mid) < available { lower = mid + 1 } else { upper = mid }
        }
        guard remaining(after: lower) == available else { throw YubaiError.invalid("请核对这期还能花的金额。") }
        return lower
    }

    public static func due(in ledger: Ledger, now: Date) -> Due? {
        guard ledger.cycleAnchor != .calendarMonth, let plan = Finance.anchorPlan(in: ledger, now: now) else { return nil }
        let today = Dates.day(now)
        let paid = Set(ledger.entries.filter { $0.deletedAt == nil && $0.nature == .income && $0.planID == plan.id && $0.date <= now }
            .compactMap { $0.occurrence.map(Dates.day) })
        let threshold = ledger.paydayConfirmSince.map(Dates.day) ?? today
        let since = Finance.cycleInfo(in: ledger, now: now).lateSince.map {
            min(threshold, plan.originalOccurrenceDate(on: $0))
        } ?? threshold
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
        guard let account = accountID ?? plan.accountID ?? ManualBookkeeping.defaultAccount(in: ledger, nature: .income)?.id else {
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
        if let index = next.plans.firstIndex(where: { $0.id == due.planID }) { recordReceipt(entry, planIndex: index, in: &next) }
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
    }

    public static func preview(_ due: Due, amount: Int64, extraToSavings: Bool, in ledger: Ledger, now: Date) -> Preview {
        var projected = ledger
        try? confirm(due, amount: amount, extraToSavings: extraToSavings, accountID: nil, in: &projected, now: now)
        Savings.closeCycles(&projected, now: now)
        let funds = Finance.funds(projected, now: now)
        return Preview(delta: amount - due.usual, cycleBudget: funds.spendable.budget)
    }
}
