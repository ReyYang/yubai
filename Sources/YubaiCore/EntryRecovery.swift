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

    public static func pendingAmount(for entry: Entry) -> Int64 {
        switch entry.pendingRecovery {
        case .reimbursement: entry.amount
        case .split: entry.recoveryParticipants?.reduce(0) { $0 + $1.amount }
            ?? (entry.amount - (entry.personalExpense ?? entry.amount))
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
            amount = person.participant.amount
        } else {
            guard status.people.isEmpty else { throw YubaiError.invalid("请选择收到的分摊。") }
            amount = status.remaining
        }

        var receipt = Entry(date: now, amount: amount, nature: .refund, accountID: accountID,
                            title: original.displayTitle, category: original.category)
        receipt.recordedAt = now
        receipt.relatedEntryID = original.id
        receipt.recoveryParticipantID = participantID
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

    static func goesToReserve(original: Entry, cycleStart: Date) -> Bool {
        original.pendingRecovery != nil && original.date < cycleStart
    }

    /// Classify at the receipt's cycle so an already-settled receipt does not
    /// move into savings simply because another cycle has now begun.
    static func reserveReceipts(in ledger: Ledger, now: Date) -> [Entry] {
        let originals = Dictionary(uniqueKeysWithValues: ledger.entries.lazy
            .filter { $0.deletedAt == nil && $0.pendingRecovery != nil && !$0.fromReserve }.map { ($0.id, $0) })
        guard !originals.isEmpty else { return [] }
        var starts: [Date: Date] = [:]
        return ledger.entries.filter { receipt in
            guard receipt.deletedAt == nil, receipt.nature == .refund, receipt.date <= now,
                  let id = receipt.relatedEntryID, let original = originals[id] else { return false }
            let day = Dates.day(receipt.date)
            let start = starts[day] ?? Finance.cycle(in: ledger, now: receipt.date).start
            starts[day] = start
            return goesToReserve(original: original, cycleStart: start)
        }
    }

    static func spendableAmount(_ entry: Entry, original: Entry, in ledger: Ledger) -> Int64 {
        if original.pendingRecovery != nil {
            return entry.nature == .expense ? entry.amount : -entry.amount
        }
        return Finance.spendingAmount(entry, ledger: ledger)
    }
}
