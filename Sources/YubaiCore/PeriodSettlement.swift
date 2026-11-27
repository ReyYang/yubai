import Foundation

public struct CarryRelease: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sourceCycleStart: Date
    public var cycleStart: Date
    public var date: Date
    public var amount: Int64
}

public struct PeriodReconciliation: Codable, Equatable, Sendable {
    public var cycleStart: Date
    public var date: Date
    public var floor: Int64
    public var entryIDs: [UUID]
}

extension Savings {
    /// Preserve the old saved headline (including its full pending target) once.
    /// Existing history and its choices are never rewritten or retro-settled.
    @discardableResult public static func migrateSpendableModel(in ledger: inout Ledger, now: Date) -> Bool {
        guard ledger.spendableModelVersion == nil else { return false }
        let value = Finance.spendableBreakdown(ledger, now: now)
        let difference = value.plannedSaving - value.savingSetAside
        ledger.migratedSavingCredit = difference
        ledger.spendableModelVersion = 1
        return true
    }

    /// A carry notice is a receipt for an automatic deposit, never an unanswered
    /// question about whether to save. Old history is left exactly as decoded.
    public static func carryNotice(in ledger: Ledger, now: Date) -> CycleSaving? {
        let current = Finance.cycle(in: ledger, now: now)
        guard let latest = ledger.savingHistory.filter({ $0.cycleEnd < current.start }).max(by: { $0.cycleEnd < $1.cycleEnd }),
              latest.autoSaved == true, latest.leftover > 0,
              !ledger.carryReleases.contains(where: { $0.sourceCycleStart == latest.cycleStart }),
              !HomeButler.isAnswered("leftover:" + Dates.text(latest.cycleStart), in: ledger, now: now) else { return nil }
        return latest
    }
    @discardableResult public static func keepLeftover(cycleStart: Date, in ledger: inout Ledger, now: Date) throws -> CarryRelease {
        guard let notice = carryNotice(in: ledger, now: now), notice.cycleStart == cycleStart,
              ledger.fixedSavingsTotal(now: now) >= notice.leftover else { throw YubaiError.invalid("这笔结余已经处理过了。") }
        let row = CarryRelease(id: UUID(), sourceCycleStart: cycleStart, cycleStart: Finance.cycle(in: ledger, now: now).start,
                               date: now, amount: notice.leftover)
        var next = ledger
        next.carryReleases.append(row)
        HomeButler.answer("leftover:" + Dates.text(cycleStart), in: &next, now: now)
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next; return row
    }
    public static func undoKeepLeftover(_ id: UUID, in ledger: inout Ledger, now: Date) throws {
        guard ledger.carryReleases.contains(where: { $0.id == id }) else { throw YubaiError.invalid("找不到这笔结余。") }
        var next = ledger
        // Undo returns the money to savings. The consumed notice stays consumed.
        next.carryReleases.removeAll { $0.id == id }
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
    }
    static func nonFloorAdjustment(_ ledger: Ledger, from: Date, through: Date, floor: Int64) -> Int64 {
        let cashIDs = Set(ledger.accounts.filter { $0.kind == .cash || $0.kind == .bank }.map(\.id))
        let net = ledger.entries.lazy.filter {
            $0.deletedAt == nil && $0.kind == .adjustment && $0.source == "对余额"
                && cashIDs.contains($0.accountID) && $0.date >= from && $0.date <= through
        }
            .reduce(Int64(0)) { $0 + ($1.nature.inflow ? -$1.amount : $1.amount) }
        return max(0, net - floor)
    }
}

extension Ledger {
    func validatePeriodState() throws {
        func date(_ d: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(d.timeIntervalSince1970) }
        guard spendableModelVersion.map({ $0 == 1 }) ?? true,
              (0...Int64.max / 4).contains(migratedSavingCredit), spendableModelVersion != nil || migratedSavingCredit == 0,
              carryReleases.count <= 100_000, Set(carryReleases.map(\.id)).count == carryReleases.count,
              Set(carryReleases.map(\.sourceCycleStart)).count == carryReleases.count,
              carryReleases.allSatisfy({ row in date(row.date) && date(row.cycleStart) && (1...Money.limit).contains(row.amount) &&
                  savingHistory.contains { $0.cycleStart == row.sourceCycleStart && $0.autoSaved == true && $0.leftover == row.amount } }),
              periodReconciliations.count <= 100_000,
              Set(periodReconciliations.map(\.cycleStart)).count == periodReconciliations.count,
              periodReconciliations.allSatisfy({ date($0.cycleStart) && date($0.date) && (0...Money.limit).contains($0.floor) }),
              lastReconciledAt.map(date) ?? true else { throw YubaiError.invalid("周期结余或对账记录无效。") }
    }
}
