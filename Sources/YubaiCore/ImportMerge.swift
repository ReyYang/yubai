import Foundation

extension BillImporter {
    /// Unknown refers to the source account before the App assigned a fallback.
    /// Ambiguous matches are deliberately left for review.
    public static func manualMergeCandidate(for imported: Entry, accountIsUnknown: Bool = false, in ledger: Ledger) -> Entry? {
        let matches = ledger.entries.filter { manualMatches($0, imported: imported, accountIsUnknown: accountIsUnknown) }
        return matches.count == 1 ? matches[0] : nil
    }
    static func manualMatches(_ manual: Entry, imported: Entry, accountIsUnknown: Bool) -> Bool {
        guard (1...Money.limit).contains(imported.amount), manual.deletedAt == nil, manual.recordedAt != nil, manual.batchID == nil, manual.id != imported.id,
              manual.amount == imported.amount, manual.nature.inflow == imported.nature.inflow,
              !manual.nature.paired, !imported.nature.paired, manual.relatedEntryID == nil, imported.relatedEntryID == nil,
              manual.otherAccountID == nil, imported.otherAccountID == nil, !manual.isUnitemized,
              manual.accountID == imported.accountID || accountIsUnknown else { return false }
        return abs(Dates.calendar.dateComponents([.day], from: Dates.day(manual.date), to: Dates.day(imported.date)).day ?? Int.max) <= 1
    }
    static func mergedImport(_ imported: Entry, preserving manual: Entry, accountIsUnknown: Bool) -> Entry {
        var entry = imported
        // Keep the user's identity, so refunds, wishes and plan links stay valid.
        entry.id = manual.id; entry.recordedAt = manual.recordedAt
        entry.purpose = manual.purpose ?? manual.title
        entry.category = manual.category; entry.subcategory = manual.subcategory
        entry.subcategoryUserEdited = manual.subcategoryUserEdited
        entry.nature = manual.nature; entry.partID = manual.partID
        entry.fromReserve = manual.fromReserve; entry.intoFixedSavings = manual.intoFixedSavings
        entry.planID = manual.planID; entry.occurrence = manual.occurrence
        entry.rentID = manual.rentID; entry.rentPeriod = manual.rentPeriod; entry.personalExpense = manual.personalExpense
        entry.userEdited = true; entry.classificationReason = manual.classificationReason
        entry.note = [manual.note, imported.note].filter { !$0.isEmpty }.joined(separator: "\n")
        if accountIsUnknown { entry.accountID = manual.accountID }
        return entry
    }
    /// Also covers callers that add an imported row before invoking autoLink.
    static func mergeAddedManualEntries(_ ids: Set<UUID>, in ledger: inout Ledger, now: Date) -> Set<UUID> {
        let imported = ledger.entries.filter { ids.contains($0.id) && $0.batchID != nil && $0.deletedAt == nil }
        let proposals = imported.compactMap { entry -> (Entry, Entry)? in
            manualMergeCandidate(for: entry, in: ledger).map { (entry, $0) }
        }
        let counts = Dictionary(grouping: proposals, by: { $0.1.id }).mapValues(\.count)
        var result = ids
        for (entry, manual) in proposals where counts[manual.id] == 1 {
            let before = ledger
            var next = ledger
            guard let index = next.entries.firstIndex(where: { $0.id == manual.id }) else { continue }
            next.entries[index] = mergedImport(entry, preserving: manual, accountIsUnknown: false)
            next.entries.removeAll { $0.id == entry.id }
            if let batch = entry.batchID { ImportOrganization.recordUndo(batchID: batch, before: before, in: &next) }
            guard (try? next.validate()) != nil else { continue }
            ledger = next; result.remove(entry.id); result.insert(manual.id)
        }
        return result
    }
}
