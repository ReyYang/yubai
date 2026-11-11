import Foundation

public struct UnitemizedSplit: Equatable, Sendable {
    public var original: Entry
    public var remainder: Entry
    public var entries: [Entry]
}
extension Reconciliation {
    /// Part dates must stay within the original spread interval, on its account.
    /// Anchored balances remain unchanged, including after a later reconciliation.
    @discardableResult public static func split(entryID: UUID, into drafts: [EntryDraft], in ledger: inout Ledger, now: Date) throws -> UnitemizedSplit {
        guard let index = ledger.entries.firstIndex(where: { $0.id == entryID && $0.deletedAt == nil }),
              ledger.entries[index].isUnitemized, ledger.entries[index].nature == .expense, !drafts.isEmpty else {
            throw YubaiError.invalid("找不到原记录。")
        }
        let original = ledger.entries[index]
        guard original.planID == nil, original.rentID == nil, original.otherAccountID == nil, !original.fromReserve,
              !ledger.entries.contains(where: { $0.deletedAt == nil && $0.relatedEntryID == original.id }),
              Set(drafts.map(\.id)).count == drafts.count else { throw YubaiError.invalid("记录信息无效。") }
        let account = ledger.accounts.first { $0.id == original.accountID }!
        var next = ledger, added: [Entry] = [], total: Int64 = 0
        var change = ChangeSet(source: "手动", reason: unitemizedTitle, items: []); change.createdAt = now
        for draft in drafts {
            guard draft.amount > 0, draft.amount <= original.amount - total,
                  draft.accountID == original.accountID, draft.nature == .expense, !draft.fromReserve,
                  draft.otherAccountID == nil, draft.planID == nil, draft.occurrence == nil,
                  draft.date >= Dates.day(original.spreadFrom!), draft.date <= original.date,
                  !ledger.entries.contains(where: { $0.id == draft.id }) else { throw YubaiError.invalid("请核对金额和日期。") }
            var entry = try change.addedEntry(draft, in: next)
            guard account.includes(entry, posting: entry.date) == account.includes(original, posting: original.date) else {
                throw YubaiError.invalid("请核对金额和日期。")
            }
            entry.recordedAt = now; entry.source = original.source; total += entry.amount
            next.entries.append(entry); added.append(entry)
        }
        if total == original.amount { next.entries[index].deletedAt = now }
        else {
            next.entries[index].amount = original.amount - total
            next.entries[index].title = unitemizedTitle; next.entries[index].purpose = nil
            next.entries[index].category = Classification.pendingCategory; next.entries[index].subcategory = nil
            next.entries[index].subcategoryUserEdited = false
        }
        let result = UnitemizedSplit(original: original, remainder: next.entries[index], entries: added)
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next; return result
    }
    public static func undoSplit(_ split: UnitemizedSplit, in ledger: inout Ledger, now: Date) throws {
        guard let index = ledger.entries.firstIndex(where: { $0.id == split.original.id }), ledger.entries[index] == split.remainder,
              split.entries.allSatisfy({ entry in ledger.entries.contains(entry) }) else { throw YubaiError.invalid("记录信息无效。") }
        var next = ledger
        let ids = Set(split.entries.map(\.id))
        next.entries.removeAll { ids.contains($0.id) }
        // Removal can change the index when another caller reordered the ledger.
        next.entries[next.entries.firstIndex { $0.id == split.original.id }!] = split.original
        next.updatedAt = max(next.updatedAt, now)
        try next.validate(); ledger = next
    }
}
