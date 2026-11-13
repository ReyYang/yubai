import Foundation

/// An audit trail of explicit decisions, never an estimate of "spending less".
public struct ButlerSaving: Codable, Equatable, Identifiable, Sendable {
    public enum Cadence: String, Codable, Sendable {
        case monthly, yearly, once, weekly, quarterly
        static func from(_ frequency: Frequency) -> Self {
            switch frequency { case .monthly: .monthly; case .yearly: .yearly; case .once: .once; case .weekly: .weekly; case .quarterly: .quarterly }
        }
    }
    public var id: String
    public var item: String
    public var amount: Int64
    public var cadence: Cadence
    public var date: Date
    public var undoable: Bool
    public var undoneAt: Date?
    public var plan: Plan?
    public var wishID: UUID?
    public var endedAt: Date?
    public var waitedHours: Int?
    public init(id: String, item: String, amount: Int64, cadence: Cadence, date: Date, undoable: Bool,
                plan: Plan? = nil, wishID: UUID? = nil, endedAt: Date? = nil, waitedHours: Int? = nil) {
        self.id = id; self.item = item; self.amount = amount; self.cadence = cadence; self.date = date
        self.undoable = undoable; self.plan = plan; self.wishID = wishID; self.endedAt = endedAt; self.waitedHours = waitedHours
    }
}

public struct ButlerSavingResult: Equatable, Identifiable, Sendable {
    public var record: ButlerSaving
    public var amount: Int64
    public var periods: Int
    public var id: String { record.id }
}

public enum ButlerSavings {
    /// Also captures explicit decisions made before round 46. Stable source IDs
    /// prevent the same wish or stopped subscription being counted twice.
    public static func synchronize(_ ledger: inout Ledger, now: Date) {
        var records = ledger.butlerSavings
        var ids = Set(records.map(\.id))
        for stop in ledger.stoppedSubscriptions {
            let id = "subscription:" + stop.id.uuidString
            if let index = records.firstIndex(where: { $0.id == id }) { records[index].endedAt = stop.resumedAt }
            guard stop.plan.frequency != .once, ids.insert(id).inserted else { continue }
            records.append(ButlerSaving(id: id, item: stop.plan.title, amount: stop.plan.amount,
                                        cadence: .from(stop.plan.frequency),
                                        date: stop.stoppedAt, undoable: true, plan: stop.plan, endedAt: stop.resumedAt))
        }
        let captured = Set(records.compactMap { $0.plan?.id })
        for var plan in ledger.plans where !captured.contains(plan.id) && plan.nature == .expense && !plan.inflow && plan.frequency != .once {
            guard let date = plan.stoppedAt else { continue }
            if plan.endDate == date { plan.endDate = nil }
            let id = "plan:" + plan.id.uuidString + ":" + String(date.timeIntervalSince1970)
            guard ids.insert(id).inserted else { continue }
            records.append(ButlerSaving(id: id, item: plan.title, amount: plan.amount,
                                        cadence: .from(plan.frequency),
                                        date: date, undoable: true, plan: plan))
        }
        for wish in ledger.wishlist where wish.status == .dropped {
            guard let date = wish.droppedAt else { continue }
            let id = "wish:" + wish.id.uuidString
            guard ids.insert(id).inserted else { continue }
            let hours = max(0, Int(date.timeIntervalSince(wish.createdAt) / 3600))
            records.append(ButlerSaving(id: id, item: wish.title, amount: wish.amount, cadence: .once,
                                        date: date, undoable: true, wishID: wish.id, waitedHours: hours))
        }
        if records != ledger.butlerSavings { ledger.butlerSavings = records }
    }

    public static func results(_ ledger: Ledger, now: Date, year: Int? = nil) -> [ButlerSavingResult] {
        var snapshot = ledger
        synchronize(&snapshot, now: now)
        let calendar = Dates.calendar
        return snapshot.butlerSavings.filter { $0.undoneAt == nil && $0.date <= now }.map { record in
            guard let plan = record.plan else {
                let count = year.map { calendar.component(.year, from: record.date) == $0 } ?? true
                return ButlerSavingResult(record: record, amount: count ? record.amount : 0, periods: count ? 1 : 0)
            }
            var total: Int64 = 0, periods = 0
            let schedule = plan.schedule(through: plan.frequency.advance(now, by: 1))
            for (index, occurrence) in schedule.enumerated() {
                let due = occurrence.date
                guard due > record.date, due <= now, record.endedAt.map({ due < $0 }) ?? true,
                      year.map({ calendar.component(.year, from: due) == $0 }) ?? true else { continue }
                let next = index + 1 < schedule.count ? schedule[index + 1].date : plan.frequency.advance(due, by: 1)
                let paid = ledger.activeEntries.contains { entry in
                    guard entry.nature == .expense, entry.date <= now else { return false }
                    if entry.planID == plan.id, let date = entry.occurrence, Dates.day(date) == Dates.day(due) { return true }
                    return entry.date >= Dates.day(due) && entry.date < next && CategoryMemory.key(entry.title) == CategoryMemory.key(plan.title)
                        && (plan.accountID == nil || plan.accountID == entry.accountID)
                }
                if !paid { total += record.amount; periods += 1 }
            }
            return ButlerSavingResult(record: record, amount: total, periods: periods)
        }.sorted { $0.record.date == $1.record.date ? $0.id < $1.id : $0.record.date > $1.record.date }
    }
    public static func total(_ ledger: Ledger, now: Date) -> Int64 { results(ledger, now: now).reduce(0) { $0 + $1.amount } }
}
