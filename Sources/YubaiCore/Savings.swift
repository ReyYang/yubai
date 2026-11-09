import Foundation

public enum SavingRule: Codable, Equatable, Sendable {
    case fixed(Int64)
    case share(Int)
    public var isValid: Bool {
        switch self { case .fixed(let amount): (0...Money.limit).contains(amount); case .share(let percent): (1...90).contains(percent) }
    }
    public func target(income: Int64) -> Int64 {
        switch self {
        case .fixed(let amount): return max(0, amount)
        case .share(let percent):
            var value = Decimal(max(0, income)) * Decimal(percent) / 100
            var rounded = Decimal(); NSDecimalRound(&rounded, &value, 0, .plain)
            return NSDecimalNumber(decimal: rounded).int64Value
        }
    }
}
public struct CycleSaving: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { cycleStart }
    public var cycleStart: Date
    public var cycleEnd: Date
    public var income: Int64
    public var target: Int64
    public var saved: Int64
    /// False when no saving rule existed during the cycle: it only marks the cycle
    /// closed, so a rule set later is never applied to months before it.
    public var tracked = true
    public init(cycleStart: Date, cycleEnd: Date, income: Int64, target: Int64, saved: Int64, tracked: Bool = true) {
        self.cycleStart = cycleStart; self.cycleEnd = cycleEnd; self.income = income; self.target = target; self.saved = saved; self.tracked = tracked
    }
    private enum CodingKeys: String, CodingKey { case cycleStart, cycleEnd, income, target, saved, tracked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cycleStart = try c.decode(Date.self, forKey: .cycleStart); cycleEnd = try c.decode(Date.self, forKey: .cycleEnd)
        income = try c.decode(Int64.self, forKey: .income); target = try c.decode(Int64.self, forKey: .target)
        saved = try c.decode(Int64.self, forKey: .saved); tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked) ?? true
    }
}

public enum EntryHint: Equatable, Sendable {
    case normal(after: Int64, daily: Int64, over: Bool)
    case restrain(areaTitle: String, countThisWeek: Int, limit: Int?, weekSpent: Int64)
    case big(after: Int64, daily: Int64, over: Bool)
    /// Non-expenses use a normal receipt; restraint takes precedence over size.
    public static func make(ledger: Ledger, amount: Int64, category: String, isFixedBill: Bool, now: Date = Date(), nature: Nature = .expense, subcategory: String? = nil) -> EntryHint {
        let funds = Finance.funds(ledger, now: now)
        let expense = nature == .expense
        let after = funds.available + (expense ? -amount : nature.inflow ? amount : 0)
            - (nature == .income ? (ledger.savingRule?.target(income: funds.cycleIncome + amount) ?? 0) - funds.savingTarget : 0)
        let days = max(1, (Dates.calendar.dateComponents([.day], from: Dates.day(now), to: funds.cycleEnd).day ?? 0) + 1)
        let daily = max(0, after) / Int64(days)
        var sample = Entry(date: now, amount: amount, accountID: UUID(), title: category, category: category)
        sample.subcategory = subcategory
        if expense, let area = ledger.profile.restrain.first(where: { ButlerCards.matches($0, entry: sample, ledger: ledger) }) {
            let usage = area.usage(in: ledger, now: now)
            let week = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let spent = area.usage(in: ledger, from: week, through: now).amount
            return .restrain(areaTitle: area.title, countThisWeek: usage.weekCount + 1, limit: area.softLimit?.perWeekCount, weekSpent: spent + amount)
        }
        if expense && !isFixedBill && amount > max(0, funds.available) / 5 { return .big(after: after, daily: daily, over: after < 0) }
        return .normal(after: after, daily: daily, over: after < 0)
    }
}

public struct StoppedSubscription: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var plan: Plan
    public var stoppedAt: Date
    public var resumedAt: Date?
    public init(plan: Plan, stoppedAt: Date) { self.plan = plan; self.stoppedAt = stoppedAt }
}
public struct SavingsLine: Equatable, Identifiable, Sendable {
    public enum Source: String, Sendable { case droppedWish, stoppedSubscription }
    public let source: Source
    public let sourceID: UUID
    public let title: String
    public let amount: Int64
    public let date: Date
    public var id: String { source.rawValue + ":" + sourceID.uuidString + ":" + String(date.timeIntervalSince1970) }
}
public struct SavingsSummary: Equatable, Sendable {
    public let lines: [SavingsLine]
    public var total: Int64 { lines.reduce(0) { $0 + $1.amount } }
}
public enum Savings {
    /// Close only the latest completed cycle; history makes repeated foreground
    /// callbacks idempotent. Rewind anchors and payments to the closing instant.
    public static func closeCycles(_ ledger: inout Ledger, now: Date = Date()) {
        let current = Finance.cycle(in: ledger, now: now)
        let close = current.start.addingTimeInterval(-0.001)
        let previous = Finance.cycle(in: ledger, now: close)
        // Stored calendar boundaries are instants created in the then-current zone.
        // A later device-zone change must not turn the same period into a new saving.
        let alreadyClosed = ledger.savingHistory.contains {
            abs($0.cycleStart.timeIntervalSince(previous.start)) <= 36 * 3600 &&
                abs($0.cycleEnd.timeIntervalSince(previous.end)) <= 36 * 3600
        }
        guard previous.end < Dates.day(now), !alreadyClosed else { return }
        guard ledger.savingRule != nil else {
            ledger.savingHistory.append(CycleSaving(cycleStart: previous.start, cycleEnd: previous.end, income: 0, target: 0, saved: 0, tracked: false))
            return
        }
        let snapshot = WeeklyLetter.snapshot(ledger, at: close)
        let funds = Finance.funds(snapshot, now: close)
        let saved = max(0, min(funds.savingTarget, funds.savingTarget + funds.available))
        ledger.fixedSavings = (ledger.fixedSavings ?? 0) + saved
        ledger.savingHistory.append(CycleSaving(cycleStart: previous.start, cycleEnd: previous.end, income: funds.cycleIncome, target: funds.savingTarget, saved: saved))
    }

    /// Half-open [from, to). A stopped subscription accrues on each elapsed due
    /// date, never as an annualized estimate or as a future saving.
    public static func summary(ledger: Ledger, from: Date, to: Date, now: Date = Date()) -> SavingsSummary {
        let to = min(to, now.addingTimeInterval(0.001))
        guard from < to else { return SavingsSummary(lines: []) }
        var lines = ledger.wishlist.compactMap { wish -> SavingsLine? in
            guard wish.status == .dropped, let date = wish.droppedAt, date >= from, date < to else { return nil }
            return SavingsLine(source: .droppedWish, sourceID: wish.id, title: wish.title, amount: wish.amount, date: date)
        }
        var stopped = ledger.stoppedSubscriptions
        let captured = Set(stopped.map { $0.plan.id })
        // Older fixed-flow stops have an explicit timestamp, but no snapshot.
        for var plan in ledger.plans where !captured.contains(plan.id) {
            guard let date = plan.stoppedAt, SubscriptionCheck.eligible(plan, ledger: ledger) else { continue }
            if plan.endDate == date { plan.endDate = nil }
            stopped.append(StoppedSubscription(plan: plan, stoppedAt: date))
        }
        for stop in stopped {
            let plan = stop.plan
            guard SubscriptionCheck.eligible(plan, ledger: ledger) else { continue }
            let schedule = plan.schedule(through: plan.frequency.advance(to, by: 1))
            for (index, item) in schedule.enumerated() {
                let due = item.date
                guard due > stop.stoppedAt, due >= from, due < to, stop.resumedAt.map({ due < $0 }) ?? true else { continue }
                let next = index + 1 < schedule.count ? schedule[index + 1].date : plan.frequency.advance(due, by: 1)
                let paid = ledger.activeEntries.contains { entry in
                    guard entry.nature == .expense else { return false }
                    if entry.planID == plan.id, let occurrence = entry.occurrence, Dates.day(occurrence) == Dates.day(due) { return true }
                    // An unlinked charge by the same merchant also disproves a saving.
                    return entry.date >= Dates.day(due) && entry.date < next && CategoryMemory.key(entry.title) == CategoryMemory.key(plan.title)
                        && (plan.accountID == nil || plan.accountID == entry.accountID)
                }
                if !paid { lines.append(SavingsLine(source: .stoppedSubscription, sourceID: stop.id, title: plan.title, amount: plan.amount, date: due)) }
            }
        }
        return SavingsSummary(lines: lines.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date })
    }
    public static func total(ledger: Ledger, now: Date = Date()) -> Int64 {
        summary(ledger: ledger, from: Date(timeIntervalSince1970: -2_208_988_800), to: now.addingTimeInterval(0.001), now: now).total
    }
}

public struct SubscriptionCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var amount: Int64
    public var frequency: Frequency
    public var planID: UUID?
    public var entryIDs: [UUID]
}
/// Shared schedule validation for import recurring detection and subscription checks.
public enum RecurringDetection {
    public static func matches(_ rows: [Entry], frequency: Frequency) -> Bool {
        guard frequency != .once, rows.count >= 3, let first = rows.first else { return false }
        for (index, row) in rows.enumerated() {
            let expected = frequency.advance(Dates.day(first.date), by: index)
            let gap = Dates.calendar.dateComponents([.day], from: expected, to: Dates.day(row.date)).day ?? 99
            if abs(gap) > 3 { return false }
        }
        return true
    }
}
public enum SubscriptionAnswer: String, Sendable { case stillUsing, stop }
public enum SubscriptionCheck {
    static func eligible(_ plan: Plan, ledger: Ledger) -> Bool {
        !plan.inflow && plan.nature == .expense && plan.frequency != .once && plan.amount > 0 && plan.amount <= 20_000
    }
    public static func candidates(ledger: Ledger, now: Date = Date()) -> [SubscriptionCandidate] {
        let month = String(Dates.text(now).prefix(7)); let payments = FixedFlowPayments(in: ledger)
        var result = ledger.plans.compactMap { plan -> SubscriptionCandidate? in
            let id = "plan:" + plan.id.uuidString
            guard eligible(plan, ledger: ledger), payments.amount(for: plan) <= 20_000, plan.active,
                  plan.stoppedAt == nil, plan.endDate.map({ $0 > now }) ?? true,
                  plan.schedule(through: Dates.addDays(366, to: now)).contains(where: { $0.date >= Dates.day(now) }),
                  ledger.subscriptionChecks[id] != month else { return nil }
            return SubscriptionCandidate(id: id, title: plan.title, amount: payments.amount(for: plan), frequency: plan.frequency, planID: plan.id, entryIDs: [])
        }
        let rows = ledger.activeEntries.filter { $0.nature == .expense && $0.amount <= 20_000 && $0.date <= now && $0.planID == nil && $0.rentID == nil && $0.relatedEntryID == nil && $0.otherAccountID == nil }
        let groups = Dictionary(grouping: rows) { $0.accountID.uuidString + ":" + CategoryMemory.key($0.title) }
        for group in groups.values {
            let rows = group.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
            guard let first = rows.first, let latest = rows.last, !CategoryMemory.key(first.title).isEmpty,
                  let frequency = [Frequency.weekly, .monthly, .quarterly, .yearly].first(where: { RecurringDetection.matches(rows, frequency: $0) }),
                  now <= Dates.addDays(3, to: frequency.advance(latest.date, by: 1)),
                  !ledger.plans.contains(where: { CategoryMemory.key($0.title) == CategoryMemory.key(first.title) && ($0.accountID == nil || $0.accountID == first.accountID) }) else { continue }
            let id = "merchant:" + LedgerCodec.checksum(Data((first.accountID.uuidString + ":" + CategoryMemory.key(first.title)).utf8))
            guard ledger.subscriptionChecks[id] != month else { continue }
            result.append(SubscriptionCandidate(id: id, title: latest.title, amount: latest.amount, frequency: frequency, planID: nil, entryIDs: rows.map(\.id)))
        }
        return result.sorted { $0.id < $1.id }
    }
    public static func answer(_ candidate: SubscriptionCandidate, choice: SubscriptionAnswer, in ledger: inout Ledger, now: Date = Date()) throws {
        guard candidates(ledger: ledger, now: now).contains(candidate) else { throw YubaiError.invalid("这项固定收付已经变了，请刷新每周来信。") }
        var next = ledger
        if choice == .stop {
            var items: [ChangeItem] = []
            let id: UUID
            if let planID = candidate.planID { id = planID }
            else {
                let rows = candidate.entryIDs.compactMap { entryID in ledger.activeEntries.first { $0.id == entryID } }.sorted { $0.date < $1.date }
                guard let first = rows.first else { throw YubaiError.invalid("找不到原记录。") }
                var plan = Plan(title: candidate.title, amount: candidate.amount, dueDate: Dates.day(first.date), frequency: candidate.frequency, category: first.category)
                plan.accountID = first.accountID; id = plan.id; items.append(.addPlan(plan))
                items += rows.enumerated().map { index, entry in .linkPlan(entry: entry.id, plan: id, occurrence: candidate.frequency.advance(plan.dueDate, by: index)) }
            }
            items.append(.endPlan(id, now))
            var change = ChangeSet(source: "用户操作", reason: "停掉「\(candidate.title)」", items: items); change.createdAt = now
            try change.apply(to: &next)
        }
        next.subscriptionChecks[candidate.id] = String(Dates.text(now).prefix(7))
        next.updatedAt = max(now, next.updatedAt); try next.validate(); ledger = next
    }
}
