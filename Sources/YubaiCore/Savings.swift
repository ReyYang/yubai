import Foundation

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
