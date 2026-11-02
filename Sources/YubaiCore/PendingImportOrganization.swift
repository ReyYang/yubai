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
        let completed = ledger.imports.reduce(into: Set<UUID>()) { $0.formUnion($1.organizedEntryIDs ?? []) }
        entryIDs = entries.filter { !completed.contains($0.id) && (!$0.userEdited || Classification.isPending($0)) }.map(\.id)
        var seen: Set<UUID> = []
        let grouped = Dictionary(grouping: entries, by: \.batchID)
        accountIDs = batchIDs.flatMap { id in (grouped[id] ?? []).map(\.accountID) }.filter { seen.insert($0).inserted }
        dates = entries.map(\.date)
    }
}

/// Shared by the in-app card and the system's continued-processing activity.
public struct ImportOrganizationProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public init(completed: Int, total: Int) {
        self.total = max(0, total)
        self.completed = min(max(0, completed), self.total)
    }
    public var countText: String {
        let style = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "en_US"))
        return completed.formatted(style) + " / " + total.formatted(style)
    }
    public var subtitle: String { "已整理 " + countText }
}
