import Foundation

/// A change of earmarking, never a bank transaction or an expense.
public struct SavingsTransfer: Codable, Equatable, Identifiable, Sendable {
    public enum Direction: String, Codable, Sendable { case take, putBack }
    public var id: UUID
    public var date: Date
    public var cycleStart: Date
    public var direction: Direction
    public var amount: Int64
    /// A withdrawal can also release this cycle's saving target. That portion
    /// must not be deducted from the base again when the cycle closes.
    public var fromSetAside: Int64
    public var delta: Int64 { direction == .putBack ? amount : -(amount - fromSetAside) }
}

public struct SavingsTopupDecision: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var withdrawals: [ReserveWithdrawal]
    public var date: Date
    public var amount: Int64
    public var transferID: UUID?
}

public struct SavingsTopupOffer: Equatable, Identifiable, Sendable {
    public var withdrawals: [ReserveWithdrawal]
    public var amount: Int64
    public var payday: Date
    public var id: String { "savingsTopup:" + withdrawals.map(\.key).sorted().joined(separator: ":") }
}

extension ReserveWithdrawal {
    var key: String {
        switch self {
        case .purchase(let id): "purchase:" + id.uuidString
        case .cover(let id): "cover:" + id.uuidString
        case .transfer(let id): "transfer:" + id.uuidString
        }
    }
}

extension Reserve {
    public struct TransferPreview: Equatable, Sendable {
        public var savedBefore: Int64
        public var savedAfter: Int64
        public var availableBefore: Int64
        public var availableAfter: Int64
        public var valid: Bool
    }

    public static func transferPreview(_ ledger: Ledger, direction: SavingsTransfer.Direction, amount: Int64, now: Date) -> TransferPreview {
        let funds = Finance.funds(ledger, now: now)
        let saved = funds.fixedSavingsTotal + funds.savingTarget
        let maximum = direction == .take ? max(0, saved) : max(0, funds.available)
        guard (0...Money.limit).contains(amount) else {
            return TransferPreview(savedBefore: saved, savedAfter: saved, availableBefore: funds.available, availableAfter: funds.available, valid: false)
        }
        let delta = direction == .take ? -amount : amount
        return TransferPreview(savedBefore: saved, savedAfter: saved + delta,
                               availableBefore: funds.available, availableAfter: funds.available - delta,
                               valid: amount > 0 && amount <= Money.limit && amount <= maximum &&
                                   (direction == .take || saved + amount <= Money.limit))
    }

    @discardableResult public static func transfer(_ direction: SavingsTransfer.Direction, amount: Int64, in ledger: inout Ledger, now: Date) throws -> SavingsTransfer {
        guard transferPreview(ledger, direction: direction, amount: amount, now: now).valid else {
            throw YubaiError.invalid(direction == .take ? "存下的钱不够。" : "还能花的金额不够。")
        }
        let funds = Finance.funds(ledger, now: now)
        let row = SavingsTransfer(id: UUID(), date: now, cycleStart: funds.cycleStart, direction: direction, amount: amount,
                                  fromSetAside: direction == .take ? max(0, amount - max(0, funds.fixedSavingsTotal)) : 0)
        var next = ledger
        next.savingsTransfers.append(row)
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
        return row
    }

    /// The App uses its shared whole-ledger undo snapshot; this operation also
    /// supports reversing a transfer by identity without altering cash postings.
    public static func undoTransfer(_ id: UUID, in ledger: inout Ledger, now: Date) throws {
        guard ledger.savingsTransfers.contains(where: { $0.id == id }) else { throw YubaiError.invalid("找不到这笔存取记录。") }
        var next = ledger
        next.savingsTransfers.removeAll { $0.id == id }
        next.savingsTopupDecisions.removeAll { $0.transferID == id }
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
    }

    /// This is the existing personal floor, now editable from the savings page.
    /// It is a preference, not another deduction or an enforced withdrawal limit.
    public static func setFloor(_ amount: Int64?, in ledger: inout Ledger, now: Date) throws {
        guard amount.map({ (0...Money.limit).contains($0) }) ?? true else { throw YubaiError.invalid("金额无效。") }
        if ledger.fixedSavings == nil { ledger.fixedSavings = 0 }
        ledger.preferences.emergencyReserve = 0 // Do not resurrect a cleared legacy floor on the next decode.
        ledger.profile.floorAmount = amount.flatMap { $0 > 0 ? $0 : nil }
        ledger.profile.updatedAt = now
    }

    /// An unanswered question stays in the shared queue. A recorded answer,
    /// including zero, consumes every included withdrawal permanently.
    public static func topupOffer(_ ledger: Ledger, now: Date) -> SavingsTopupOffer? {
        guard let plan = Finance.anchorPlan(in: ledger, now: now) else { return nil }
        let answered = Set(ledger.savingsTopupDecisions.flatMap(\.withdrawals) + (ledger.reservePaybacks ?? []).map(\.withdrawal))
        let receipts = ledger.activeEntries.filter { $0.nature == .income && $0.planID == plan.id && $0.occurrence != nil }
        let pending = withdrawals(ledger, now: now).filter { !answered.contains($0.withdrawal) }
        guard !pending.isEmpty else { return nil }
        let schedule = plan.schedule(through: Dates.addDays(366, to: now)).filter { !plan.isSkipped(on: $0.date) }
        var eligible: [(ReservePaybackOffer, Date)] = []
        for withdrawal in pending {
            let first = schedule.compactMap { item -> Date? in
                let received = receipts.filter { Dates.day($0.occurrence!) == Dates.day(item.date) }.map(\.date).min()
                let date = received.map(Dates.day) ?? Dates.day(item.date)
                return date > Dates.day(withdrawal.date) ? date : nil
            }.min()
            if let first, first <= Dates.day(now) { eligible.append((withdrawal, first)) }
        }
        guard !eligible.isEmpty else { return nil }
        return SavingsTopupOffer(withdrawals: eligible.map { $0.0.withdrawal }.sorted { $0.key < $1.key },
                                 amount: eligible.reduce(0) { $0 + $1.0.amount }, payday: eligible.map(\.1).min()!)
    }

    public static func answerTopup(_ offer: SavingsTopupOffer, amount: Int64, in ledger: inout Ledger, now: Date) throws {
        guard topupOffer(ledger, now: now) == offer, amount >= 0, amount <= offer.amount else { throw YubaiError.invalid("这次存取记录已经变了。") }
        var next = ledger
        let transferID = amount > 0 ? try transfer(.putBack, amount: amount, in: &next, now: now).id : nil
        next.savingsTopupDecisions.append(SavingsTopupDecision(id: UUID(), withdrawals: offer.withdrawals, date: now, amount: amount, transferID: transferID))
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
    }

    static func validateFlexibleSavings(in ledger: Ledger) throws {
        func dateValid(_ date: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970) }
        let transfers = ledger.savingsTransfers, answers = ledger.savingsTopupDecisions
        let answered = answers.flatMap(\.withdrawals)
        guard transfers.count <= 100_000, Set(transfers.map(\.id)).count == transfers.count,
              transfers.allSatisfy({ dateValid($0.date) && dateValid($0.cycleStart) && (1...Money.limit).contains($0.amount) &&
                  (0...$0.amount).contains($0.fromSetAside) && ($0.direction == .take || $0.fromSetAside == 0) }),
              answers.count <= 100_000, Set(answers.map(\.id)).count == answers.count,
              Set(answered).count == answered.count,
              answers.allSatisfy({ answer in dateValid(answer.date) && !answer.withdrawals.isEmpty && answer.withdrawals.count <= 100_000 &&
                  (0...Money.limit).contains(answer.amount) && (answer.amount == 0 ? answer.transferID == nil : transfers.contains(where: { row in row.id == answer.transferID && row.direction == .putBack && row.amount == answer.amount })) })
        else { throw YubaiError.invalid("存取记录无效。") }
    }
}
