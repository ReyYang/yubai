import Foundation

public struct RecoveryParticipant: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var amount: Int64

    public init(id: UUID = UUID(), name: String, amount: Int64) {
        self.id = id
        self.name = name
        self.amount = amount
    }
}

public struct EntryRecovery: Equatable, Sendable {
    public struct Person: Equatable, Identifiable, Sendable {
        public var id: UUID { participant.id }
        public let participant: RecoveryParticipant
        public let receipt: Entry?
    }

    public let kind: PendingRecovery
    public let remaining: Int64
    public let people: [Person]
    public let receipts: [Entry]
    public var isSettled: Bool { remaining == 0 }

    public static func pendingAmount(for entry: Entry) -> Int64 {
        switch entry.pendingRecovery {
        case .reimbursement: entry.amount
        case .split: entry.personalExpense.map { entry.amount - $0 }
            ?? entry.recoveryParticipants?.reduce(0) { $0 + $1.amount } ?? 0
        case nil: 0
        }
    }

    public static func status(for original: Entry, in ledger: Ledger, now: Date) -> Self? {
        guard original.deletedAt == nil, let kind = original.pendingRecovery else { return nil }
        let receipts = ledger.entries.filter {
            $0.deletedAt == nil && $0.nature == .refund && $0.relatedEntryID == original.id && $0.date <= now
        }
        let people = (original.recoveryParticipants ?? []).map { participant in
            Person(participant: participant, receipt: receipts.first { $0.recoveryParticipantID == participant.id })
        }
        return Self(kind: kind, remaining: max(0, pendingAmount(for: original) - receipts.reduce(0) { $0 + $1.amount }),
                    people: people, receipts: receipts)
    }

    public static func defaultAccount(for original: Entry, in ledger: Ledger, now: Date = Dates.now) -> Account? {
        let active = ledger.accounts.filter { !$0.archived }
        let liquid = active.filter { $0.kind == .bank || $0.kind == .cash }
        if let paidFrom = liquid.first(where: { $0.id == original.accountID }) { return paidFrom }
        let plans = ledger.plans.filter {
            $0.active && $0.stoppedAt.map { $0 > now } != false &&
                $0.endDate.map { Dates.day($0) >= Dates.day(now) } != false &&
                $0.inflow && $0.nature == .income && $0.frequency != .once
        }
        for plan in plans.filter(Payday.isSalaryPlan) + plans.filter({ !Payday.isSalaryPlan($0) }) {
            if let account = liquid.first(where: { $0.id == plan.accountID }) { return account }
        }
        return liquid.first { $0.kind == .bank } ?? liquid.first { $0.kind == .cash }
    }

    static func redistribute(_ people: [RecoveryParticipant], originalID: UUID, pending: Int64, in ledger: Ledger) throws -> [RecoveryParticipant]? {
        let receipts = ledger.activeEntries.filter { $0.nature == .refund && $0.relatedEntryID == originalID }
        let received = receipts.reduce(Int64(0)) { $0 + $1.amount }
        guard pending >= received else { throw YubaiError.invalid("待收金额不能少于已收回的金额。") }
        let paid = Dictionary(uniqueKeysWithValues: receipts.compactMap { receipt in
            receipt.recoveryParticipantID.map { ($0, receipt.amount) }
        })
        let remaining = pending - received
        let unpaid = people.filter { paid[$0.id] == nil }
        let recipients = unpaid.isEmpty && remaining > 0 ? [RecoveryParticipant(name: "TA", amount: remaining)] : unpaid
        let count = Int64(recipients.count)
        let share = count > 0 ? remaining / count : 0
        let extra = count > 0 ? remaining % count : 0
        let allocations = Dictionary(uniqueKeysWithValues: recipients.enumerated().map {
            ($0.element.id, share + ($0.offset == 0 ? extra : 0))
        })
        let known = Set(people.map(\.id))
        let updated = (people + recipients.filter { !known.contains($0.id) }).compactMap { person -> RecoveryParticipant? in
            let amount = paid[person.id] ?? allocations[person.id] ?? 0
            guard amount > 0 else { return nil }
            return RecoveryParticipant(id: person.id, name: person.name, amount: amount)
        }
        return updated.isEmpty ? nil : updated
    }

    @discardableResult public static func receive(originalID: UUID, participantID: UUID? = nil, into accountID: UUID,
                                                  in ledger: inout Ledger, now: Date) throws -> Entry {
        guard let original = ledger.entries.first(where: { $0.id == originalID && $0.date <= now }),
              let status = status(for: original, in: ledger, now: now), status.remaining > 0 else {
            throw YubaiError.invalid("这笔钱已收回，或原账单已删除。")
        }
        guard ledger.accounts.contains(where: { $0.id == accountID }) else {
            throw YubaiError.invalid("收款账户已删除。")
        }
        let amount: Int64
        if let participantID {
            guard let person = status.people.first(where: { $0.id == participantID }), person.receipt == nil else {
                throw YubaiError.invalid("这笔分摊已收回。")
            }
            amount = min(person.participant.amount, status.remaining)
        } else {
            guard status.people.isEmpty else { throw YubaiError.invalid("请选择收到的分摊。") }
            amount = status.remaining
        }

        var receipt = Entry(date: now, amount: amount, nature: .refund, accountID: accountID,
                            title: original.displayTitle, category: original.category)
        receipt.recordedAt = now
        receipt.relatedEntryID = original.id
        receipt.recoveryParticipantID = participantID
        receipt.recoveryIntoReserve = original.date < Finance.cycle(in: ledger, now: now).start
        // Reports already show the original's personal share. The cash entry
        // still credits the receiving account and reverses the full hold.
        if status.kind == .split, original.personalExpense != nil { receipt.personalExpense = 0 }
        receipt.subcategory = original.subcategory
        var next = ledger
        next.entries.append(receipt)
        try next.validate()
        ledger = next
        return receipt
    }

    public static func delete(_ id: UUID, from ledger: inout Ledger, now: Date) throws {
        guard let index = ledger.entries.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw YubaiError.invalid("账单已删除。")
        }
        var next = ledger
        let original = next.entries[index]
        next.entries[index].deletedAt = now
        if original.pendingRecovery != nil {
            for index in next.entries.indices where next.entries[index].relatedEntryID == id
                && next.entries[index].nature == .refund && next.entries[index].deletedAt == nil {
                next.entries[index].deletedAt = now
            }
        }
        try next.validate()
        ledger = next
    }

    static func goesToReserve(_ receipt: Entry, original: Entry, cycleStart: @autoclosure () -> Date) -> Bool {
        receipt.recoveryIntoReserve ?? (original.pendingRecovery != nil && original.date < cycleStart())
    }

    /// Classify at the receipt's cycle so an already-settled receipt does not
    /// move into savings simply because another cycle has now begun.
    static func reserveReceipts(in ledger: Ledger, now: Date) -> [Entry] {
        let candidates = ledger.entries.filter { $0.deletedAt == nil && $0.nature == .refund && $0.date <= now && $0.relatedEntryID != nil }
        guard !candidates.isEmpty else { return [] }
        let originalIDs = Set(candidates.compactMap(\.relatedEntryID))
        let originals = Dictionary(uniqueKeysWithValues: ledger.entries.lazy
            .filter { $0.deletedAt == nil && !$0.fromReserve && originalIDs.contains($0.id) }.map { ($0.id, $0) })
        var starts: [Date: Date] = [:]
        return candidates.filter { receipt in
            guard let id = receipt.relatedEntryID, let original = originals[id] else { return false }
            if let booked = receipt.recoveryIntoReserve { return booked }
            guard original.pendingRecovery != nil else { return false }
            let day = Dates.day(receipt.date)
            let start = starts[day] ?? Finance.cycle(in: ledger, now: receipt.date).start
            starts[day] = start
            return goesToReserve(receipt, original: original, cycleStart: start)
        }
    }

    static func spendableAmount(_ entry: Entry, original: Entry, in ledger: Ledger) -> Int64 {
        if original.pendingRecovery != nil {
            return entry.nature == .expense ? entry.amount : -entry.amount
        }
        return Finance.spendingAmount(entry, ledger: ledger)
    }
}
