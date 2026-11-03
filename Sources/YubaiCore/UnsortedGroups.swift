import Foundation

public struct UnsortedPartyGroup: Identifiable, Equatable, Sendable {
    public var id: String { (inflow ? "in:" : "out:") + party }
    public let party: String
    public let inflow: Bool
    /// Newest first, with a stable tie-breaker. The UI only renders the first four.
    public let entries: [Entry]
    public let total: Int64
    fileprivate let sourceAccountIDs: Set<UUID>

    init(party: String, inflow: Bool, entries: [Entry]) {
        self.party = party; self.inflow = inflow; self.entries = entries
        total = entries.reduce(0) { $0 + $1.amount }
        sourceAccountIDs = Set(entries.map(\.accountID))
    }
}

public enum UnsortedUse: String, CaseIterable, Sendable {
    case expense, income, investBuy, investSell, transfer, repayment, lend, loanRecovery
    public var title: String {
        switch self {
        case .expense: "日常支出"; case .income: "日常收入"
        case .investBuy: "买基金"; case .investSell: "卖基金"
        case .transfer: "转给自己"; case .repayment: "还款"
        case .lend: "借给别人"; case .loanRecovery: "收回借款"
        }
    }
    public var needsCategory: Bool { self == .expense || self == .income }
    public var nature: Nature { Nature(rawValue: rawValue)! }
}

/// Pure projections over the question's original coverage. Cache these only for
/// one ledger revision so edits, deletions, checkpoints and undo remain live.
public enum UnsortedGroups {
    public static func party(for entry: Entry) -> String {
        entry.title.components(separatedBy: " · ")[0]
    }
    public static func needsSorting(_ entry: Entry) -> Bool {
        entry.deletedAt == nil && entry.mergedIntoID == nil && entry.otherAccountID == nil &&
        entry.planID == nil && entry.rentID == nil && entry.relatedEntryID == nil &&
        Classification.isPending(entry) && (entry.nature.uncertain || [Nature.expense, .income].contains(entry.nature))
    }
    public static func entries(for question: ImportQuestion, in ledger: Ledger) -> [Entry] {
        guard question.isFallback else { return [] }
        let ids = Set(question.entryIDs)
        let referenced = Set(ledger.entries.lazy.filter { $0.deletedAt == nil }.compactMap(\.relatedEntryID))
        return ledger.entries.filter { ids.contains($0.id) && needsSorting($0) && !referenced.contains($0.id) }
    }
    public static func groups(for question: ImportQuestion, in ledger: Ledger) -> [UnsortedPartyGroup] {
        groups(entries: entries(for: question, in: ledger))
    }
    /// Shared party/direction projection for the remaining-record UI and AI input.
    public static func groups(entries: [Entry]) -> [UnsortedPartyGroup] {
        struct Key: Hashable { let party: String; let inflow: Bool }
        let grouped = Dictionary(grouping: entries) {
            Key(party: party(for: $0), inflow: $0.nature.inflow)
        }
        let groups: [UnsortedPartyGroup] = grouped.map { key, entries in
            // Convert each UUID once instead of allocating strings in every comparison.
            let keyed: [(entry: Entry, id: String)] = entries.map { (entry: $0, id: $0.id.uuidString) }
            let sorted = keyed.sorted {
                $0.entry.date == $1.entry.date ? $0.id < $1.id : $0.entry.date > $1.entry.date
            }
            return UnsortedPartyGroup(party: key.party, inflow: key.inflow, entries: sorted.map { $0.entry })
        }
        return groups.sorted {
            if $0.entries.count != $1.entries.count { return $0.entries.count > $1.entries.count }
            return $0.id < $1.id
        }
    }
    public static func otherAccounts(for group: UnsortedPartyGroup, in ledger: Ledger) -> [Account] {
        ledger.accounts.filter { !$0.archived && !group.sourceAccountIDs.contains($0.id) }
    }
    public static func uses(for group: UnsortedPartyGroup, in ledger: Ledger) -> [UnsortedUse] {
        let uses: [UnsortedUse] = group.inflow ? [.income, .investSell, .transfer, .loanRecovery] : [.expense, .investBuy, .transfer, .repayment, .lend]
        let canTransfer = ledger.accounts.contains { !$0.archived && !group.sourceAccountIDs.contains($0.id) }
        return uses.filter { $0 != .transfer || canTransfer }
    }
    /// Selection validation only: no ledger scan, regrouping or ChangeItem allocation.
    public static func canApply(to group: UnsortedPartyGroup, use: UnsortedUse?,
                                category: String? = nil, otherAccount: UUID? = nil, in ledger: Ledger) -> Bool {
        guard let use, !group.entries.isEmpty, uses(for: group, in: ledger).contains(use) else { return false }
        if use.needsCategory {
            guard let category, ledger.categories.contains(where: {
                !$0.system && !$0.hidden && $0.name == category && $0.income == group.inflow
            }) else { return false }
        }
        if use == .transfer {
            guard let otherAccount, !group.sourceAccountIDs.contains(otherAccount),
                  ledger.accounts.contains(where: { $0.id == otherAccount && !$0.archived }) else { return false }
        }
        return true
    }
    /// Re-read the live group at confirmation so stale selections cannot change
    /// rows that were classified elsewhere while this page was open.
    public static func changeSet(groupID: String, question: ImportQuestion, use: UnsortedUse,
                                 category: String? = nil, otherAccount: UUID? = nil, in ledger: Ledger) -> ChangeSet? {
        guard let group = groups(for: question, in: ledger).first(where: { $0.id == groupID }) else { return nil }
        return changeSet(group: group, use: use, category: category, otherAccount: otherAccount, in: ledger)
    }
    fileprivate static func changeSet(group: UnsortedPartyGroup, use: UnsortedUse,
                                      category: String?, otherAccount: UUID?, in ledger: Ledger) -> ChangeSet? {
        guard canApply(to: group, use: use, category: category, otherAccount: otherAccount, in: ledger) else { return nil }
        let items: [ChangeItem] = group.entries.flatMap { entry in
            var items: [ChangeItem] = []
            if entry.nature != use.nature || use == .transfer {
                items.append(.setNature(entry: entry.id, nature: use.nature, otherAccount: use == .transfer ? otherAccount : nil))
            }
            if use.needsCategory, let category { items.append(.setCategory(entry: entry.id, category: category)) }
            return items
        }
        guard !items.isEmpty else { return nil }
        return ChangeSet(source: "按对方分", reason: "这 \(group.entries.count) 笔都这样记", items: items)
    }
}

/// Immutable, shared by the fallback card, search results and group destination.
public final class UnsortedGroupsSnapshot: Sendable {
    public let revision: UInt64
    public let batchID: UUID
    public let groups: [UnsortedPartyGroup]
    public let groupsByID: [String: UnsortedPartyGroup]
    public let entryCount: Int

    fileprivate init(revision: UInt64, batchID: UUID, entries: [Entry]) {
        self.revision = revision; self.batchID = batchID; entryCount = entries.count
        groups = UnsortedGroups.groups(entries: entries)
        groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
    }

    public func matching(_ search: String) -> [UnsortedPartyGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? groups : groups.filter { $0.party.localizedCaseInsensitiveContains(query) }
    }
}

/// The owner must advance revision on EVERY ledger assignment, including undo,
/// restore and updates preserving updatedAt. Timestamps alone are not a version.
/// Kept outside observation: cache fills during rendering must not publish changes.
public struct UnsortedGroupsCache {
    private var revision: UInt64?
    private var ledgerID: UUID?
    private var questions: [UUID: (batchID: UUID, question: ImportQuestion)] = [:]
    private var eligibleEntries: [UUID: Entry] = [:]
    private var snapshots: [UUID: UnsortedGroupsSnapshot] = [:]

    public init() {}

    public mutating func snapshot(for questionID: UUID, revision: UInt64, in ledger: Ledger) -> UnsortedGroupsSnapshot? {
        if self.revision != revision || ledgerID != ledger.id {
            self.revision = revision; ledgerID = ledger.id
            questions.removeAll(keepingCapacity: true); snapshots.removeAll(keepingCapacity: true)
            for batch in ledger.imports where batch.undoneAt == nil {
                for question in batch.organization?.questions ?? [] where question.isFallback {
                    if questions[question.id] == nil { questions[question.id] = (batch.id, question) }
                }
            }
            let referenced = Set(ledger.entries.lazy.filter { $0.deletedAt == nil }.compactMap(\.relatedEntryID))
            eligibleEntries = Dictionary(uniqueKeysWithValues: ledger.entries.lazy.filter {
                UnsortedGroups.needsSorting($0) && !referenced.contains($0.id)
            }.map { ($0.id, $0) })
        }
        if let cached = snapshots[questionID] { return cached }
        guard let context = questions[questionID] else { return nil }
        // Coverage is a set, including old archives containing duplicate IDs.
        // Each covered row is a dictionary lookup, never a linear ledger search.
        let entries = Set(context.question.entryIDs).compactMap { eligibleEntries[$0] }
        let value = UnsortedGroupsSnapshot(revision: revision, batchID: context.batchID, entries: entries)
        snapshots[questionID] = value
        return value
    }

    /// Resolve against the current revision at the moment of confirmation.
    public mutating func changeSet(groupID: String, questionID: UUID, use: UnsortedUse,
                                  category: String? = nil, otherAccount: UUID? = nil,
                                  revision: UInt64, in ledger: Ledger) -> ChangeSet? {
        guard let group = snapshot(for: questionID, revision: revision, in: ledger)?.groupsByID[groupID] else { return nil }
        return UnsortedGroups.changeSet(group: group, use: use, category: category, otherAccount: otherAccount, in: ledger)
    }
}
