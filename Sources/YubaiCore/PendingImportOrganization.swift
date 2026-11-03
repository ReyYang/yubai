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

/// System-only subprogress. Saved-entry counts remain exact in the app. Each
/// in-flight request owns a bounded reservation; waiting can never complete it.
public struct ImportOrganizationHeartbeat: Sendable {
    private struct Work: Sendable { var entries: Int; var units: Int64 = 0; var finished = false }
    private var requests: [UUID: Work] = [:]
    private var saved: ImportOrganizationProgress
    private var highWater: Int64 = 0
    public init(progress: ImportOrganizationProgress) { saved = progress }
    // Reserve one final unit for optional wording/metadata after the last entry.
    public var totalUnits: Int64 { (Int64(max(1, saved.total)) + 1) * 10_000 }
    public var completedUnits: Int64 { highWater }
    public mutating func update(_ progress: ImportOrganizationProgress) {
        var remaining = max(0, progress.completed - saved.completed)
        // Saved units replace the matching response reservation. Do not count a
        // just-saved chunk twice between update() and checkpointed().
        for id in requests.keys where remaining > 0 {
            guard var work = requests[id], work.finished else { continue }
            let consumed = min(remaining, work.entries)
            work.entries -= consumed; remaining -= consumed
            work.units = min(work.units, Int64(work.entries) * 9_500)
            requests[id] = work
        }
        saved = progress; advance()
    }
    public mutating func receive(_ event: ImportOrganizer.RequestEvent) {
        switch event {
        case .started(let id, let entries): requests[id] = Work(entries: entries)
        case .finished(let id):
            if var work = requests[id] {
                work.units = Int64(work.entries) * 9_500; work.finished = true; requests[id] = work
            }
        case .checkpointed(let id): requests[id] = nil
        }
        advance()
    }
    public mutating func tick() {
        for id in requests.keys {
            guard var work = requests[id] else { continue }
            let ceiling = Int64(work.entries) * 9_000
            if work.units < ceiling { work.units += max(1, (ceiling - work.units) / 32) }
            requests[id] = work
        }
        advance()
    }
    private mutating func advance() {
        let candidate = Int64(saved.completed) * 10_000 + requests.values.reduce(0) { $0 + $1.units }
        // Even a completed response is provisional until its atomic checkpoint.
        highWater = max(highWater, min(totalUnits - 1, candidate))
    }
}
