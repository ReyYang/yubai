import Foundation

public struct RecognizedPlanLink: Equatable, Sendable {
    public var entryID: UUID; public var occurrence: Date
}
public struct RecognizedImportPlan: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable { case salary, bill }
    public var id: UUID { plan.id }
    public var kind: Kind; public var plan: Plan; public var links: [RecognizedPlanLink]
}
public enum ImportRecognition {
    /// Deterministic local recognition. Existing plans and already linked rows
    /// are excluded; evidence may include earlier imports of the same merchant.
    public static func plans(batchID: UUID, in ledger: Ledger, now: Date) -> [RecognizedImportPlan] {
        guard ledger.imports.contains(where: { $0.id == batchID && $0.undoneAt == nil }) else { return [] }
        let targets = Set(ledger.entries.filter { $0.batchID == batchID && $0.deletedAt == nil && $0.date <= now }.map(\.id))
        guard !targets.isEmpty else { return [] }
        var result: [RecognizedImportPlan] = []
        if let salary = SalaryDetection.candidate(in: ledger, now: now), !targets.isDisjoint(with: salary.entryIDs) {
            let evidence = Set(salary.entryIDs)
            // Recognition can span a payroll account change. The new plan uses
            // the latest account; retain earlier accounts as unlinked history.
            let rows = ledger.entries.filter { evidence.contains($0.id) && $0.accountID == salary.accountID && $0.planID == nil && $0.rentID == nil }
                .sorted { $0.date < $1.date }
            if let first = rows.first {
                let month = Dates.calendar.dateInterval(of: .month, for: first.date)!.start
                let days = Dates.calendar.range(of: .day, in: .month, for: month)!.count
                var plan = Plan(title: "工资", amount: salary.amount, dueDate: Dates.addDays(min(days, salary.dayOfMonth) - 1, to: month),
                                frequency: .monthly, inflow: true, category: first.category, nature: .income)
                plan.monthlyDay = salary.dayOfMonth; plan.accountID = salary.accountID
                plan.id = stableID("salary:" + salary.key + ":" + salary.accountID.uuidString)
                if let candidate = recognized(plan, kind: .salary, rows: rows) { result.append(candidate) }
            }
        }
        let rows = ledger.entries.filter { $0.deletedAt == nil && $0.date <= now && (1...Money.limit).contains($0.amount) && $0.nature == .expense && !$0.fromReserve &&
            !$0.isUnitemized && $0.planID == nil && $0.rentID == nil && $0.relatedEntryID == nil && $0.otherAccountID == nil }
        let groups = Dictionary(grouping: rows) { $0.accountID.uuidString + ":" + CategoryMemory.key($0.displayTitle) }
        for (key, group) in groups {
            guard !targets.isDisjoint(with: group.map(\.id)) else { continue }
            let sorted = group.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
            guard let first = sorted.first, let last = sorted.last, !CategoryMemory.key(first.displayTitle).isEmpty,
                  let frequency = [Frequency.weekly, .monthly, .quarterly, .yearly].first(where: { RecurringDetection.matches(sorted, frequency: $0) }),
                  !ledger.plans.contains(where: { !$0.inflow && CategoryMemory.key($0.title) == CategoryMemory.key(first.displayTitle) &&
                      ($0.accountID == nil || $0.accountID == first.accountID) }) else { continue }
            var plan = Plan(title: last.displayTitle, amount: last.amount, dueDate: Dates.day(first.date), frequency: frequency,
                            category: last.category)
            plan.id = stableID("bill:" + key + ":" + frequency.rawValue); plan.accountID = first.accountID
            plan.estimated = Set(sorted.map(\.amount)).count > 1
            if let candidate = recognized(plan, kind: .bill, rows: sorted) { result.append(candidate) }
        }
        return result.sorted { $0.kind == $1.kind ? $0.id.uuidString < $1.id.uuidString : $0.kind == .salary }
    }
    /// Creates all currently recognized plans in one validated transaction and
    /// includes their links in the batch's existing undo delta.
    @discardableResult public static func addAll(batchID: UUID, in ledger: inout Ledger, now: Date) throws -> [Plan] {
        guard ledger.imports.contains(where: { $0.id == batchID && $0.undoneAt == nil }) else { throw YubaiError.invalid("找不到原记录。") }
        let candidates = plans(batchID: batchID, in: ledger, now: now)
        guard !candidates.isEmpty else { return [] }
        let items = candidates.flatMap { candidate in
            [ChangeItem.addPlan(candidate.plan)] + candidate.links.map { .linkPlan(entry: $0.entryID, plan: candidate.plan.id, occurrence: $0.occurrence) }
        }
        var change = ChangeSet(source: "导入", reason: "都加上", items: items); change.createdAt = now
        let before = ledger
        var next = ledger
        let skipped = try change.apply(to: &next)
        guard skipped.isEmpty else { throw YubaiError.invalid("记录信息无效。") }
        ImportOrganization.recordUndo(batchID: batchID, before: before, in: &next)
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
        return candidates.map(\.plan)
    }
    private static func recognized(_ input: Plan, kind: RecognizedImportPlan.Kind, rows: [Entry]) -> RecognizedImportPlan? {
        guard !rows.isEmpty else { return nil }
        var plan = input
        let schedule = plan.schedule(through: Dates.addDays(4, to: rows.last!.date))
        var links: [RecognizedPlanLink] = [], used: Set<Date> = []
        for row in rows {
            let matches = schedule.filter {
                abs(Dates.calendar.dateComponents([.day], from: Dates.day(row.date), to: Dates.day($0.date)).day ?? Int.max) <= 3
            }
            guard matches.count == 1, let occurrence = matches.first?.date, used.insert(occurrence).inserted else { return nil }
            links.append(RecognizedPlanLink(entryID: row.id, occurrence: occurrence))
        }
        plan.settledOccurrences = links.map(\.occurrence)
        return RecognizedImportPlan(kind: kind, plan: plan, links: links)
    }
    private static func stableID(_ key: String) -> UUID {
        let hex = Array(LedgerCodec.checksum(Data(key.utf8)).prefix(32))
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
        return UUID(uuidString: parts.joined(separator: "-"))!
    }
}
