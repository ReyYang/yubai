import Foundation

/// A local summary of batches awaiting the user's explicit organization action.
public struct PendingImportOrganization: Equatable, Sendable {
    public let batchIDs: [UUID]
    public let entryIDs: [UUID]
    public let accountIDs: [UUID]
    public let dates: [Date]
    public var count: Int { entryIDs.count }

    public init(in ledger: Ledger) {
        batchIDs = ledger.imports.filter { $0.needsOrganization == true && $0.undoneAt == nil }.map(\.id)
        let batches = Set(batchIDs)
        let entries = ledger.activeEntries.filter { entry in entry.batchID.map { batches.contains($0) } ?? false }
        // Match the organizer's editable rows; an explicitly edited pending row
        // still belongs in the count until the user gives it a classification.
        entryIDs = entries.filter { !$0.userEdited || Classification.isPending($0) }.map(\.id)
        var seen: Set<UUID> = []
        let grouped = Dictionary(grouping: entries, by: \.batchID)
        accountIDs = batchIDs.flatMap { id in (grouped[id] ?? []).map(\.accountID) }.filter { seen.insert($0).inserted }
        dates = entries.map(\.date)
    }
}
