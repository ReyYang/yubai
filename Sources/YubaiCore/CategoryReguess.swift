import Foundation

/// One target path and its rows, ready for a counted preview. Proposals are
/// snapshots: apply rechecks both the entry and its current local evidence.
public struct ReguessProposal: Identifiable, Equatable, Sendable {
    public let target: CategoryAssignment
    public let entryIDs: [UUID]
    public var id: String { target.path }
    public var count: Int { entryIDs.count }
    fileprivate let ledgerID: UUID
    fileprivate let originals: [Entry]
}

/// An in-memory, one-step change/undo delta. Later edits and unrelated checkpoints
/// survive undo, using the same before-value recovery as manual group sorting.
public struct CategoryReguessChangeSet: Sendable {
    public let source = "本机重新归类"
    public let entryIDs: [UUID]
    public var count: Int { entryIDs.count }
    private let recovery: UnsortedGroupsUndo
    fileprivate init(before: Ledger, after: Ledger, entryIDs: [UUID], recoveryIDs: Set<UUID>) {
        self.entryIDs = entryIDs
        recovery = UnsortedGroupsUndo(before: before, after: after, entryIDs: recoveryIDs)
    }
    public func undo(in ledger: inout Ledger) { recovery.restore(in: &ledger) }
}

public enum CategoryReguess {
    /// No network or learned-memory writes. Only ordinary income/expense rows
    /// participate; linked refund categories follow their originals on apply.
    public static func proposals(in ledger: Ledger) -> [ReguessProposal] {
        var paths: [String] = []
        var grouped: [String: [Entry]] = [:]
        for entry in ledger.entries {
            guard let target = target(for: entry, in: ledger) else { continue }
            if grouped[target.path] == nil { paths.append(target.path) }
            grouped[target.path, default: []].append(entry)
        }
        return paths.map { path in
            let entries = grouped[path]!
            return ReguessProposal(target: .init(path: path), entryIDs: entries.map(\.id), ledgerID: ledger.id, originals: entries)
        }
    }

    /// Atomically applies a selected set of proposal groups. Stale rows, changed
    /// evidence or targets that were hidden/renamed since preview are skipped.
    @discardableResult public static func apply(_ proposals: [ReguessProposal], in ledger: inout Ledger) throws -> CategoryReguessChangeSet {
        try ledger.validate()
        let before = ledger
        var next = ledger
        let positions = Dictionary(uniqueKeysWithValues: next.entries.enumerated().map { ($0.element.id, $0.offset) })
        var applied: [UUID] = []
        var seen = Set<UUID>()
        for proposal in proposals where proposal.ledgerID == ledger.id {
            for original in proposal.originals {
                guard seen.insert(original.id).inserted, let i = positions[original.id], next.entries[i] == original,
                      target(for: original, in: ledger) == proposal.target else { continue }
                next.entries[i].category = proposal.target.category
                if !original.subcategoryUserEdited { next.entries[i].subcategory = proposal.target.subcategory }
                next.entries[i].classificationReason = "本机重新归类"
                applied.append(original.id)
            }
        }
        // Refunds keep their linkage and follow their original's category. Include
        // them in the undo delta, without counting them as separate proposals.
        let appliedIDs = Set(applied)
        var recoveryIDs = appliedIDs
        for i in next.entries.indices where next.entries[i].nature == .refund && next.entries[i].deletedAt == nil {
            guard let originalID = next.entries[i].relatedEntryID, appliedIDs.contains(originalID), let originalIndex = positions[originalID] else { continue }
            next.entries[i].category = next.entries[originalIndex].category
            if !next.entries[i].subcategoryUserEdited { next.entries[i].subcategory = next.entries[originalIndex].subcategory }
            recoveryIDs.insert(next.entries[i].id)
        }
        try next.validate()
        let recovery = CategoryReguessChangeSet(before: before, after: next, entryIDs: applied, recoveryIDs: recoveryIDs)
        ledger = next
        return recovery
    }

    private static func target(for entry: Entry, in ledger: Ledger) -> CategoryAssignment? {
        guard entry.deletedAt == nil, entry.mergedIntoID == nil, [.expense, .income].contains(entry.nature), entry.otherAccountID == nil else { return nil }
        let current = ledger.categoryAssignment(category: entry.category, subcategory: entry.subcategory, income: entry.nature.categoryIncome)
        let pending = Classification.isPending(entry) || Classification.isPending(current.category)
        // userEdited is also set by ImportOrganizer, so it cannot identify an
        // explicit “other”. Require its recorded source; missing/legacy/other AI
        // reasons are deliberately ineligible. Manual corrections write memory,
        // which CategoryGuesser consults before keywords (including “other”).
        guard pending || (current.category == (entry.nature.inflow ? "其他收入" : "其他支出") && entry.classificationReason.hasPrefix("导入整理：")) else { return nil }
        var unclassified = entry
        unclassified.category = Classification.pendingCategory
        unclassified.subcategory = nil
        guard var target = CategoryGuesser.guess(unclassified, in: ledger),
              SubcategoryClassifier.valid(target, in: ledger, nature: entry.nature),
              target.category != (entry.nature.categoryIncome ? "其他收入" : "其他支出") else { return nil }
        if entry.subcategoryUserEdited {
            // Preserve explicit “no small item”. A selected small item belongs
            // to its old main, so do not relocate that row to a different main.
            if entry.subcategory != nil && current.category != target.category { return nil }
            target.subcategory = entry.subcategory
        }
        return target == current ? nil : target
    }
}
