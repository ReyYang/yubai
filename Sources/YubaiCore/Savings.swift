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

extension Ledger {
    public mutating func switchSavingMode(sharing: Bool) {
        savingRule = sharing ? .share(lastSavingSharePercent ?? 20) : .fixed(lastFixedSavingTarget ?? 0)
    }

    /// Only posted income in cash/bank accounts contributes, using the same
    /// reconciliation boundary as Finance's cash balance (including archived accounts).
    func fixedSavingsFromIncome(now: Date) -> Int64 {
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        return entries.reduce(Int64(0)) { total, entry in
            guard entry.deletedAt == nil, entry.nature == .income, entry.intoFixedSavings,
                  let account = accountsByID[entry.accountID], account.kind == .cash || account.kind == .bank else { return total }
            let posting = entry.postingDate(for: account.id)
            return posting <= now && account.includes(entry, posting: posting) ? total + entry.amount : total
        }
    }

    public func fixedSavingsTotal(now: Date = Date()) -> Int64 {
        (fixedSavings ?? 0) + fixedSavingsFromIncome(now: now) - reserveSpent(now: now) - reserveCovered(now: now)
    }

    /// Reverse all derived income and withdrawals to keep the stored base
    /// nonnegative; editing/deleting source entries reverses their contribution.
    public mutating func setFixedSavingsTotal(_ total: Int64, now: Date = Date()) {
        fixedSavings = max(0, min(Money.limit, total) - fixedSavingsFromIncome(now: now) + reserveSpent(now: now) + reserveCovered(now: now))
    }
}
public enum LeftoverChoice: String, Codable, Equatable, Sendable { case keep, save }

public struct CycleSaving: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { cycleStart }
    public var cycleStart: Date
    public var cycleEnd: Date
    public var income: Int64
    public var target: Int64
    public var saved: Int64
    /// Unspent funds explicitly saved, or merged by versions before round 45.
    public var leftover: Int64 = 0
    public var unspent: Int64?
    public var leftoverChoice: LeftoverChoice?
    /// False when no saving rule existed during the cycle, so a rule set later
    /// is never applied to months before it. Leftover may still have been merged.
    public var tracked = true
    public init(cycleStart: Date, cycleEnd: Date, income: Int64, target: Int64, saved: Int64, leftover: Int64 = 0, tracked: Bool = true, unspent: Int64? = nil, leftoverChoice: LeftoverChoice? = nil) {
        self.cycleStart = cycleStart; self.cycleEnd = cycleEnd; self.income = income; self.target = target; self.saved = saved; self.leftover = leftover; self.tracked = tracked
        self.unspent = unspent; self.leftoverChoice = leftoverChoice
    }
    private enum CodingKeys: String, CodingKey { case cycleStart, cycleEnd, income, target, saved, leftover, tracked, unspent, leftoverChoice }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cycleStart = try c.decode(Date.self, forKey: .cycleStart); cycleEnd = try c.decode(Date.self, forKey: .cycleEnd)
        income = try c.decode(Int64.self, forKey: .income); target = try c.decode(Int64.self, forKey: .target)
        saved = try c.decode(Int64.self, forKey: .saved); tracked = try c.decodeIfPresent(Bool.self, forKey: .tracked) ?? true
        leftover = try c.decodeIfPresent(Int64.self, forKey: .leftover) ?? 0
        unspent = try c.decodeIfPresent(Int64.self, forKey: .unspent)
        leftoverChoice = try c.decodeIfPresent(LeftoverChoice.self, forKey: .leftoverChoice)
    }
}

public enum EntryHint: Equatable, Sendable {
    /// Separate draft result keeps existing receipt consumers source compatible
    /// until the app adds the destination control and its rendering.
    public enum DraftResult: Equatable, Sendable {
        case fixedSavings(newTotal: Int64)
        case receipt(EntryHint)
    }
    public static func make(ledger: Ledger, draft: EntryDraft, isFixedBill: Bool, now: Date = Date()) -> DraftResult {
        if draft.nature == .income && draft.intoFixedSavings {
            var projected = ledger
            var entry = Entry(date: draft.date, amount: draft.amount, nature: draft.nature, accountID: draft.accountID,
                              title: draft.title, intoFixedSavings: true)
            entry.recordedAt = now
            projected.entries.append(entry)
            return .fixedSavings(newTotal: projected.fixedSavingsTotal(now: now))
        }
        return .receipt(make(ledger: ledger, amount: draft.amount, category: draft.category, isFixedBill: isFixedBill,
                             now: now, nature: draft.nature, subcategory: draft.subcategory, partID: draft.partID))
    }
    case normal(after: Int64, daily: Int64, over: Bool, part: SpendingPartHint? = nil)
    case restrain(areaTitle: String, countThisWeek: Int, limit: Int?, weekSpent: Int64)
    case big(after: Int64, daily: Int64, over: Bool)
    /// Non-expenses use a normal receipt; restraint takes precedence over size.
    public static func make(ledger: Ledger, amount: Int64, category: String, isFixedBill: Bool, now: Date = Date(), nature: Nature = .expense, subcategory: String? = nil, partID: UUID? = nil) -> EntryHint {
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
        var partHint: SpendingPartHint?
        if expense && !isFixedBill && !ledger.spendingParts.isEmpty {
            sample.partID = partID
            let summary = SpendingParts.summary(ledger, now: now)
            let part = SpendingParts.part(for: sample, in: ledger)
            let balance = part.flatMap { p in summary.parts.first { $0.id == p.id } }
            let remaining = balance.map { $0.allowance - $0.spent } ?? summary.unassigned
            partHint = SpendingPartHint(id: part?.id, name: part?.name ?? "没分的", after: remaining - amount,
                overBy: part == nil ? 0 : max(0, amount - remaining))
        }
        return .normal(after: after, daily: daily, over: after < 0, part: partHint)
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
        let current = Finance.cycleInfo(in: ledger, now: now)
        guard current.lateSince == nil else { return }
        let close = current.start.addingTimeInterval(-0.001)
        let previous = Finance.cycle(in: ledger, now: close)
        // Stored calendar boundaries are instants created in the then-current zone.
        // A later device-zone or anchor change must not reserve an already
        // closed period again. A changed anchor starts closing at its next full,
        // nonoverlapping period, preserving the existing history and balances.
        let alreadyClosed = ledger.savingHistory.contains {
            (abs($0.cycleStart.timeIntervalSince(previous.start)) <= 36 * 3600 &&
                abs($0.cycleEnd.timeIntervalSince(previous.end)) <= 36 * 3600) ||
                ($0.cycleStart <= previous.end && previous.start <= $0.cycleEnd)
        }
        guard previous.end < Dates.day(now), !alreadyClosed else { return }
        let snapshot = WeeklyLetter.snapshot(ledger, at: close)
        SpendingParts.closeCycle(&ledger, snapshot: snapshot, close: close, nextStart: current.start)
        let funds = Finance.funds(snapshot, now: close)
        // Funds excludes earmarked income from both cycle income and liquid
        // funds, so it can never be merged into the base a second time.
        // Available already excludes the saving target; do not add part balances again.
        let unspent = max(0, funds.available)
        guard ledger.savingRule != nil else {
            ledger.savingHistory.append(CycleSaving(cycleStart: previous.start, cycleEnd: previous.end, income: 0, target: 0, saved: 0, tracked: false, unspent: unspent))
            return
        }
        let saved = max(0, min(funds.savingTarget, funds.savingTarget + funds.available))
        ledger.fixedSavings = (ledger.fixedSavings ?? 0) + saved
        ledger.savingHistory.append(CycleSaving(cycleStart: previous.start, cycleEnd: previous.end, income: funds.cycleIncome, target: funds.savingRuleTarget, saved: saved, unspent: unspent))
    }

    public static func pendingLeftover(in ledger: Ledger) -> CycleSaving? {
        ledger.savingHistory.filter { $0.leftoverChoice == nil && ($0.unspent ?? 0) > 0 }.max { $0.cycleStart < $1.cycleStart }
    }
    public static func resolveLeftover(cycleStart: Date, choice: LeftoverChoice, in ledger: inout Ledger) throws {
        guard let index = ledger.savingHistory.firstIndex(where: { abs($0.cycleStart.timeIntervalSince(cycleStart)) <= 36 * 3600 }),
              ledger.savingHistory[index].leftoverChoice == nil, let unspent = ledger.savingHistory[index].unspent, unspent > 0 else {
            throw YubaiError.invalid("攒钱的金额或周期无效。")
        }
        var next = ledger
        if choice == .save {
            next.fixedSavings = (next.fixedSavings ?? 0) + unspent
            next.savingHistory[index].leftover = unspent
        }
        next.savingHistory[index].leftoverChoice = choice
        try next.validate(); ledger = next
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
