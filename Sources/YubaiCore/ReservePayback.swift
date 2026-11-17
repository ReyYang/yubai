import Foundation

public enum ReserveWithdrawal: Codable, Equatable, Sendable, Hashable {
    case purchase(UUID), cover(UUID), transfer(UUID)
}
public struct ReservePaybackPayment: Codable, Equatable, Sendable {
    public var cycleStart: Date
    public var date: Date
    public var amount: Int64
}
/// A nil cycle count records the user's one-time decision not to pay back.
public struct ReservePayback: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var withdrawal: ReserveWithdrawal
    public var amount: Int64
    public var decidedAt: Date
    public var start: Date
    public var cycles: Int?
    public var payments: [ReservePaybackPayment]?
}
public struct ReservePaybackOffer: Equatable, Sendable, Identifiable {
    public var id: ReserveWithdrawal { withdrawal }
    public var withdrawal: ReserveWithdrawal
    public var title: String
    public var date: Date
    public var amount: Int64
}
public struct ReservePaybackProgress: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var withdrawal: ReserveWithdrawal
    public var amount: Int64
    public var paid: Int64
    public var remaining: Int64
    public var thisCycle: Int64
    public var completed: Bool
}
extension Reserve {
    static func withdrawals(_ ledger: Ledger, now: Date) -> [ReservePaybackOffer] {
        var refunds: [UUID: Int64] = [:]
        for entry in ledger.entries where entry.deletedAt == nil && entry.nature == .refund && entry.date <= now {
            if let id = entry.relatedEntryID { refunds[id, default: 0] += entry.amount }
        }
        var result = ledger.entries.compactMap { entry -> ReservePaybackOffer? in
            guard entry.deletedAt == nil, entry.nature == .expense, entry.fromReserve, entry.date <= now else { return nil }
            let amount = max(0, entry.amount - refunds[entry.id, default: 0])
            guard amount > 0 else { return nil }
            return ReservePaybackOffer(withdrawal: .purchase(entry.id), title: entry.displayTitle, date: entry.date, amount: amount)
        }
        result += ledger.cycleCovers.filter { $0.source == .fromReserve && $0.date <= now }.map {
            ReservePaybackOffer(withdrawal: .cover($0.id), title: "", date: $0.date, amount: $0.amount)
        }
        result += ledger.savingsTransfers.filter { $0.direction == .take && $0.date <= now }.map {
            ReservePaybackOffer(withdrawal: .transfer($0.id), title: "", date: $0.date, amount: $0.amount)
        }
        return result.sorted { $0.date == $1.date ? String(describing: $0.id) < String(describing: $1.id) : $0.date > $1.date }
    }
    public static func paybackOffers(_ ledger: Ledger, now: Date) -> [ReservePaybackOffer] {
        let answered = Set((ledger.reservePaybacks ?? []).map(\.withdrawal) + ledger.savingsTopupDecisions.flatMap(\.withdrawals))
        return withdrawals(ledger, now: now).filter { !answered.contains($0.withdrawal) }
    }
    /// Positive N accepts; nil declines. Raises this cycle's target immediately.
    public static func answerPayback(_ withdrawal: ReserveWithdrawal, cycles: Int?, in ledger: inout Ledger, now: Date) throws {
        guard cycles.map({ (1...120).contains($0) }) ?? true,
              let offer = paybackOffers(ledger, now: now).first(where: { $0.withdrawal == withdrawal }) else {
            throw YubaiError.invalid("攒钱的金额或周期无效。")
        }
        var next = ledger
        var rows = next.reservePaybacks ?? []
        rows.append(ReservePayback(id: UUID(), withdrawal: withdrawal, amount: offer.amount, decidedAt: now,
                                  start: Finance.cycle(in: ledger, now: now).start, cycles: cycles))
        next.reservePaybacks = rows; next.updatedAt = max(next.updatedAt, now)
        // The combined target must remain valid even with several active paybacks.
        guard Finance.funds(next, now: now).savingRuleTarget <= Money.limit else { throw YubaiError.invalid("攒钱的金额或周期无效。") }
        try next.validate(); ledger = next
    }
    public static func paybackProgress(_ ledger: Ledger, now: Date) -> [ReservePaybackProgress] {
        let start = Finance.cycle(in: ledger, now: now).start
        let sources = Dictionary(uniqueKeysWithValues: withdrawals(ledger, now: now).map { ($0.withdrawal, $0.amount) })
        return (ledger.reservePaybacks ?? []).filter { $0.cycles != nil && $0.decidedAt <= now }.map { row in
            let total = min(row.amount, sources[row.withdrawal] ?? 0)
            let paid = min(total, (row.payments ?? []).filter { $0.date <= now }.reduce(0) { $0 + $1.amount })
            return ReservePaybackProgress(id: row.id, withdrawal: row.withdrawal, amount: total, paid: paid,
                remaining: total - paid, thisCycle: paybackDue(row, sourceAmount: total, cycleStart: start, now: now), completed: paid >= total)
        }
    }
    static func paybackDue(_ row: ReservePayback, sourceAmount: Int64, cycleStart: Date, now: Date) -> Int64 {
        guard let cycles = row.cycles, cycles > 0, row.decidedAt <= now, row.start <= cycleStart else { return 0 }
        let payments = (row.payments ?? []).filter { $0.date <= now }
        if let payment = payments.first(where: { abs($0.cycleStart.timeIntervalSince(cycleStart)) < 36 * 3600 }) { return payment.amount }
        let paid = payments.filter { $0.cycleStart < cycleStart }.reduce(Int64(0)) { $0 + $1.amount }
        return min(max(0, min(row.amount, sourceAmount) - paid), (row.amount + Int64(cycles) - 1) / Int64(cycles))
    }
    static func paybackAmounts(_ ledger: Ledger, cycleStart: Date, now: Date) -> [(id: UUID, amount: Int64)] {
        guard let rows = ledger.reservePaybacks, !rows.isEmpty else { return [] }
        let sources = Dictionary(uniqueKeysWithValues: withdrawals(ledger, now: now).map { ($0.withdrawal, $0.amount) })
        return rows.map { ($0.id, paybackDue($0, sourceAmount: sources[$0.withdrawal] ?? 0, cycleStart: cycleStart, now: now)) }.filter { $0.amount > 0 }
    }
    static func recordPaybacks(_ ledger: inout Ledger, cycleStart: Date, saved: Int64, baseTarget: Int64, close: Date) {
        let amounts = paybackAmounts(ledger, cycleStart: cycleStart, now: close)
        var remaining = max(0, saved - baseTarget)
        guard var rows = ledger.reservePaybacks else { return }
        for item in amounts {
            guard let index = rows.firstIndex(where: { $0.id == item.id }) else { continue }
            let amount = min(remaining, item.amount)
            if amount > 0 {
                rows[index].payments = (rows[index].payments ?? []) + [ReservePaybackPayment(cycleStart: cycleStart, date: close, amount: amount)]
                remaining -= amount
            }
        }
        ledger.reservePaybacks = rows
    }
    static func validatePaybacks(in ledger: Ledger) throws {
        let rows = ledger.reservePaybacks ?? []
        func valid(_ date: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970) }
        guard rows.count <= 5000, Set(rows.map(\.id)).count == rows.count, Set(rows.map(\.withdrawal)).count == rows.count,
              rows.allSatisfy({ row in
                  let payments = row.payments ?? []
                  return (1...Money.limit).contains(row.amount) && valid(row.start) && valid(row.decidedAt) &&
                      (row.cycles.map { (1...120).contains($0) } ?? payments.isEmpty) &&
                      Set(payments.map(\.cycleStart)).count == payments.count && payments.count <= 5000 &&
                      payments.allSatisfy { valid($0.cycleStart) && valid($0.date) && $0.cycleStart >= row.start && (1...row.amount).contains($0.amount) } &&
                      payments.reduce(Int64(0)) { $0 + $1.amount } <= row.amount
              }) else { throw YubaiError.invalid("攒钱的金额或周期无效。") }
    }
}
