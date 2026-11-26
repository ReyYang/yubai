import Foundation

/// How the assistant speaks. `AskYubai.prompt(now:tone:)` reads it.
public enum AssistantTone: String, Codable, CaseIterable, Sendable { case gentle, direct }

/// When the weekly review is sent. `weekday` is 1 (Monday) … 7 (Sunday).
public struct WeeklyReviewTime: Codable, Equatable, Sendable {
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    public init(weekday: Int, hour: Int, minute: Int) { self.weekday = weekday; self.hour = hour; self.minute = minute }
    public static let standard = WeeklyReviewTime(weekday: 7, hour: 21, minute: 0)
    public var isValid: Bool { (1...7).contains(weekday) && (0...23).contains(hour) && (0...59).contains(minute) }

    /// The repeating trigger. Foundation counts Sunday as 1, this type counts Monday as 1.
    public var dateComponents: DateComponents {
        var value = DateComponents()
        value.weekday = weekday % 7 + 1; value.hour = hour; value.minute = minute
        return value
    }

    /// The first moment strictly after `date` that matches this weekday and time.
    public func nextFire(after date: Date, calendar: Calendar = Dates.calendar) -> Date? {
        calendar.nextDate(after: date, matching: dateComponents, matchingPolicy: .nextTime)
    }
}

extension Preferences {
    public var tone: AssistantTone { assistantTone ?? .gentle }
    public var reviewTime: WeeklyReviewTime { weeklyReviewTime ?? .standard }
    public var shiftsWeekendPayday: Bool { paydayWeekendShift == true }
}

/// The day a spending cycle starts, with the optional move of a weekend payday to the Friday before.
public enum CycleStart {
    /// Stored for 「每月最后一天」; every month clamps it to its own last day.
    public static let lastDay = 31

    /// Saturday and Sunday move to the Friday before; other days are unchanged.
    public static func shifted(_ date: Date) -> Date {
        let day = Dates.day(date)
        switch Dates.calendar.component(.weekday, from: day) {
        case 7: return Dates.addDays(-1, to: day)
        case 1: return Dates.addDays(-2, to: day)
        default: return day
        }
    }

    public static func payday(day: Int, inMonthOf date: Date, weekendShift: Bool) -> Date {
        let nominal = Payday.nominalDate(day: day, inMonthOf: date)
        return weekendShift ? shifted(nominal) : nominal
    }

    /// The cycle that contains `now` for a monthly start day.
    public static func cycle(day: Int, weekendShift: Bool, now: Date) -> (start: Date, end: Date) {
        let today = Dates.day(now)
        let starts = (-2...2).map { payday(day: day, inMonthOf: Dates.addMonths($0, to: today), weekendShift: weekendShift) }
        let start = starts.last { $0 <= today } ?? starts[0]
        let next = starts.first { $0 > start } ?? Dates.addMonths(1, to: start)
        return (start, Dates.addDays(-1, to: next))
    }

    /// The cycle after the one that contains `now`.
    public static func nextCycle(day: Int, weekendShift: Bool, now: Date) -> (start: Date, end: Date) {
        cycle(day: day, weekendShift: weekendShift, now: Dates.addDays(1, to: cycle(day: day, weekendShift: weekendShift, now: now).end))
    }

    /// The chosen start day: the salary plan's day, then the stored day, then the calendar month.
    public static func day(in ledger: Ledger, now: Date) -> Int {
        if ledger.cycleAnchor != .calendarMonth, let plan = Finance.anchorPlan(in: ledger, now: now), plan.frequency == .monthly {
            return plan.monthlyDay ?? Dates.calendar.component(.day, from: plan.dueDate)
        }
        if ledger.cycleAnchor == .payday, let day = ledger.preferences.cycleStartDay { return day }
        return 1
    }

    /// Sets the cycle start day. A salary plan keeps its amount and account and moves to the new day.
    public static func set(day: Int, weekendShift: Bool, in ledger: inout Ledger, now: Date) throws {
        guard (1...lastDay).contains(day) else { throw YubaiError.invalid("请选择 1 到 28 日或每月最后一天。") }
        var next = ledger
        next.cycleAnchor = .payday
        next.preferences.cycleStartDay = day
        next.preferences.paydayWeekendShift = weekendShift ? true : nil
        if let plan = Finance.anchorPlan(in: next, now: now), Payday.isSalaryPlan(plan),
           (plan.monthlyDay ?? Dates.calendar.component(.day, from: plan.dueDate)) != day,
           let account = plan.accountID ?? ManualBookkeeping.defaultAccount(in: next, nature: .income)?.id {
            try Payday.configure(day: day, amount: plan.amount, accountID: account, in: &next, now: now)
        }
        next.updatedAt = max(next.updatedAt, now)
        try next.validate()
        ledger = next
    }
}

/// Values the settings rows and sheets display. Views only format them.
public enum SettingsSummary {
    /// Active outflow plans that repeat (subscriptions), soonest due first.
    public static func subscriptions(in ledger: Ledger, now: Date) -> [(plan: Plan, due: Date)] {
        let today = Dates.day(now)
        return ledger.plans.filter { $0.active && $0.stoppedAt == nil && !$0.inflow && $0.frequency != .once }
            .compactMap { plan in plan.nextScheduledDate(after: Dates.addDays(-1, to: today)).map { (plan, Dates.day($0)) } }
            .sorted { $0.due == $1.due ? $0.plan.title < $1.plan.title : $0.due < $1.due }
    }

    /// The plan's scheduled days inside `interval` (skipped days left out).
    public static func occurrences(of plan: Plan, in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var boundary = interval.start.addingTimeInterval(-1)
        while let next = plan.nextScheduledDate(after: boundary), next < interval.end, days.count < 62 {
            days.append(Dates.day(next)); boundary = next
        }
        return days
    }

    /// One month's share of a plan in CNY: yearly /12, quarterly /3, foreign currency at the saved rate.
    public static func monthlyShare(of plan: Plan, in ledger: Ledger, now: Date) -> Int64? {
        let amount: Int64
        if plan.currency == .cny { amount = plan.amount }
        else {
            guard let converted = FixedFlows.exchangeRate(for: plan.currency, in: ledger, now: now)?.convert(plan.amount) else { return nil }
            amount = converted
        }
        let value = Decimal(amount)
        let monthly: Decimal
        switch plan.frequency {
        case .once: return nil
        case .monthly: monthly = value
        case .quarterly: monthly = value / 3
        case .halfYearly: monthly = value / 6
        case .yearly: monthly = value / 12
        case .weekly: monthly = value * 52 / 12
        case .fortnightly: monthly = value * 26 / 12
        }
        var input = monthly, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    public static func monthlyFixed(in ledger: Ledger, now: Date) -> (total: Int64, count: Int) {
        let shares = subscriptions(in: ledger, now: now).compactMap { monthlyShare(of: $0.plan, in: ledger, now: now) }
        return (shares.reduce(0, +), shares.count)
    }

    /// Average spend per calendar month over the last `months` complete months that have spending.
    public static func averageMonthlySpend(in ledger: Ledger, now: Date, months: Int = 3) -> Int64 {
        let thisMonth = Dates.calendar.dateInterval(of: .month, for: now)!.start
        var totals: [Int64] = []
        for offset in 1...max(1, months) {
            let start = Dates.addMonths(-offset, to: thisMonth), end = Dates.addMonths(-offset + 1, to: thisMonth)
            let spent = ledger.entries.reduce(Int64(0)) { total, entry in
                guard entry.deletedAt == nil, entry.nature == .expense, entry.date >= start, entry.date < end else { return total }
                return total + entry.amount
            }
            if spent > 0 { totals.append(spent) }
        }
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0, +) / Int64(totals.count)
    }

    /// 3 and 6 months of the average monthly spend, for the floor chips. Empty without spending.
    public static func floorChips(in ledger: Ledger, now: Date) -> [Int64] {
        let average = averageMonthlySpend(in: ledger, now: now)
        guard average > 0 else { return [] }
        return [min(Money.limit, average * 3), min(Money.limit, average * 6)]
    }

    /// The monthly take-home pay: the salary plan's amount, else this cycle's income.
    public static func takeHome(in ledger: Ledger, now: Date) -> Int64 {
        if let plan = Finance.anchorPlan(in: ledger, now: now), plan.inflow { return plan.amount }
        return max(0, Finance.spendableBreakdown(ledger, now: now).income)
    }

    /// 10 % and 20 % of take-home pay, rounded to whole yuan.
    public static func savingChips(takeHome: Int64) -> [Int64] {
        guard takeHome > 0 else { return [] }
        return [10, 20].map { (takeHome * Int64($0) / 100) / 100 * 100 }
    }

    /// This month's 先攒 target under the current rule.
    public static func savingTarget(in ledger: Ledger, now: Date) -> Int64 {
        ledger.savingRule?.target(income: takeHome(in: ledger, now: now)) ?? 0
    }
}

public enum ExportRange: String, CaseIterable, Sendable {
    case current, previous, all

    public func interval(in ledger: Ledger, now: Date) -> ClosedRange<Date>? {
        let cycle = Finance.cycle(in: ledger, now: now)
        switch self {
        case .current: return Dates.day(cycle.start)...Dates.day(cycle.end)
        case .previous:
            let previous = Finance.cycle(in: ledger, now: Dates.day(cycle.start).addingTimeInterval(-1))
            return Dates.day(previous.start)...Dates.day(previous.end)
        case .all: return nil
        }
    }
}

extension LedgerBackup {
    static func exportedEntries(_ ledger: Ledger, in range: ClosedRange<Date>?) -> [Entry] {
        ledger.entries.filter { entry in
            guard entry.deletedAt == nil else { return false }
            guard let range else { return true }
            return range.contains(Dates.day(entry.date))
        }
    }

    public static func exportCount(_ ledger: Ledger, in range: ClosedRange<Date>?) -> Int {
        exportedEntries(ledger, in: range).count
    }
}

/// Account creation, edits and archive for the settings and onboarding screens.
public enum Accounts {
    public struct Draft: Equatable, Sendable {
        public var name: String
        public var kind: AccountKind
        /// As stored: a credit card's amount owed is negative.
        public var balance: Int64
        public init(name: String, kind: AccountKind, balance: Int64) { self.name = name; self.kind = kind; self.balance = balance }
    }

    /// Opening balance as of `now`, like the old add-account screen.
    @discardableResult
    public static func add(_ draft: Draft, in ledger: inout Ledger, now: Date) throws -> UUID {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw YubaiError.invalid("请给账户起一个名称。") }
        guard !ledger.accounts.contains(where: { $0.name == name }) else { throw YubaiError.invalid("已有同名账户，换一个名称。") }
        guard abs(draft.balance) <= Money.limit else { throw YubaiError.invalid("金额超出范围。") }
        var next = ledger
        let account = Account(name: name, kind: draft.kind, balance: draft.balance, at: now)
        next.accounts.append(account)
        next.updatedAt = max(next.updatedAt, now)
        try next.validate()
        ledger = next
        return account.id
    }

    public struct Change: Equatable, Sendable {
        public var name: String?
        public var kind: AccountKind?
        public var creditLimit: Int64?
        /// Outer nil leaves the day alone; inner nil clears it.
        public var statementDay: Int??
        public var paymentDay: Int??
        public init(name: String? = nil, kind: AccountKind? = nil, creditLimit: Int64? = nil,
                    statementDay: Int?? = nil, paymentDay: Int?? = nil) {
            self.name = name; self.kind = kind; self.creditLimit = creditLimit
            self.statementDay = statementDay; self.paymentDay = paymentDay
        }
    }

    public static func update(_ id: UUID, _ change: Change, in ledger: inout Ledger, now: Date) throws {
        guard let index = ledger.accounts.firstIndex(where: { $0.id == id }) else { throw YubaiError.invalid("找不到这个账户。") }
        var next = ledger
        var account = next.accounts[index]
        if let name = change.name?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !name.isEmpty else { throw YubaiError.invalid("请给账户起一个名称。") }
            guard !next.accounts.contains(where: { $0.name == name && $0.id != id }) else { throw YubaiError.invalid("已有同名账户，换一个名称。") }
            account.name = name
        }
        if let kind = change.kind { account.kind = kind }
        if let limit = change.creditLimit { account.creditLimit = limit }
        if let day = change.statementDay { account.creditStatementDay = day }
        if let day = change.paymentDay { account.creditPaymentDay = day }
        if account.kind != .credit { account.creditStatementDay = nil; account.creditPaymentDay = nil; account.creditLimit = 0 }
        next.accounts[index] = account
        next.updatedAt = max(next.updatedAt, now)
        try next.validate()
        ledger = next
    }

    /// Archived accounts keep their entries and leave 资产 and 记一笔.
    public static func archive(_ id: UUID, in ledger: inout Ledger, now: Date) throws {
        guard let index = ledger.accounts.firstIndex(where: { $0.id == id }) else { throw YubaiError.invalid("找不到这个账户。") }
        var next = ledger
        next.accounts[index].archived = true
        next.updatedAt = max(next.updatedAt, now)
        try next.validate()
        ledger = next
    }
}

/// 首次打开: cycle day, 先攒, accounts and opening balances in one save.
public enum Onboarding {
    public static func finish(day: Int, takeHome: Int64, saving: Int64, floor: Int64?, accounts: [Accounts.Draft],
                              in ledger: inout Ledger, now: Date) throws {
        guard (0...Money.limit).contains(takeHome), (0...Money.limit).contains(saving) else { throw YubaiError.invalid("金额超出范围。") }
        var next = ledger
        for draft in accounts { try Accounts.add(draft, in: &next, now: now) }
        if next.accounts.isEmpty { FirstUse.prepareForEntry(&next, now: now) }
        next.preferences.onboardingComplete = true
        let pay = next.accounts.first { !$0.archived && ($0.kind == .bank || $0.kind == .cash) }
        if takeHome > 0, let pay {
            try Payday.configure(day: min(day, CycleStart.lastDay), amount: takeHome, accountID: pay.id, in: &next, now: now)
            // The balances just entered already include the latest payday, so the
            // first cycle starts there and only the next payday waits for arrival.
            next.paydayConfirmSince = nil
            Finance.enablePaydayConfirmation(&next, now: now)
        }
        try CycleStart.set(day: day, weekendShift: next.preferences.shiftsWeekendPayday, in: &next, now: now)
        if saving > 0 { next.savingRule = .fixed(saving) }
        if let floor { try Reserve.setFloor(floor, in: &next, now: now) }
        next.updatedAt = max(next.updatedAt, now)
        try next.validate()
        ledger = next
    }
}
