import Foundation

public struct UnsortedPartyGroup: Identifiable, Equatable, Sendable {
    public var id: String { (inflow ? "in:" : "out:") + party }
    public let party: String
    public let inflow: Bool
    /// Newest first, with a stable tie-breaker. The UI renders these lazily.
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
    /// Local evidence from the newest row; never invent a category or cross directions.
    public static func suggestedCategory(for group: UnsortedPartyGroup, in ledger: Ledger) -> String? {
        guard let newest = group.entries.first,
              let choice = CategoryGuesser.guess(newest, in: ledger),
              ledger.selectableCategories.contains(where: { $0.name == choice.category && $0.income == group.inflow }) else { return nil }
        return choice.category
    }
    public static func otherAccounts(for groups: [UnsortedPartyGroup], in ledger: Ledger) -> [Account] {
        guard !groups.isEmpty else { return [] }
        return ledger.accounts.filter { account in
            !account.archived && groups.allSatisfy { !$0.sourceAccountIDs.contains(account.id) }
        }
    }
    public static func uses(for groups: [UnsortedPartyGroup], in ledger: Ledger) -> [UnsortedUse] {
        guard let first = groups.first else { return [] }
        return uses(for: first, in: ledger).filter { use in
            groups.allSatisfy { uses(for: $0, in: ledger).contains(use) } &&
            (use != .transfer || !otherAccounts(for: groups, in: ledger).isEmpty)
        }
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
        } else if category != nil { return false }
        if use == .transfer {
            guard let otherAccount, !group.sourceAccountIDs.contains(otherAccount),
                  ledger.accounts.contains(where: { $0.id == otherAccount && !$0.archived }) else { return false }
        }
        return true
    }
    /// Re-read the live group at confirmation so stale selections cannot change
    /// rows that were classified elsewhere while this page was open.
    public static func changeSet(groupID: String, question: ImportQuestion, use: UnsortedUse,
                                 category: String? = nil, otherAccount: UUID? = nil,
                                 entryIDs: Set<UUID>? = nil, purpose: String? = nil, in ledger: Ledger) -> ChangeSet? {
        guard let group = groups(for: question, in: ledger).first(where: { $0.id == groupID }) else { return nil }
        return changeSet(group: group, use: use, category: category, otherAccount: otherAccount,
                         entryIDs: entryIDs, purpose: purpose, in: ledger)
    }
    fileprivate static func changeSet(group: UnsortedPartyGroup, use: UnsortedUse,
                                      category: String?, otherAccount: UUID?, entryIDs: Set<UUID>?,
                                      purpose: String?, in ledger: Ledger) -> ChangeSet? {
        guard canApply(to: group, use: use, category: category, otherAccount: otherAccount, in: ledger) else { return nil }
        let entries = group.entries.filter { entryIDs?.contains($0.id) ?? true }
        let purpose = purpose?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entries.isEmpty, (purpose?.count ?? 0) <= 4000 else { return nil }
        let items: [ChangeItem] = entries.flatMap { entry in
            var items: [ChangeItem] = []
            if entry.nature != use.nature || use == .transfer {
                items.append(.setNature(entry: entry.id, nature: use.nature, otherAccount: use == .transfer ? otherAccount : nil))
            }
            if use.needsCategory, let category { items.append(.setCategory(entry: entry.id, category: category)) }
            if let purpose, !purpose.isEmpty { items.append(.setPurpose(entry: entry.id, text: purpose)) }
            return items
        }
        guard !items.isEmpty else { return nil }
        return ChangeSet(source: "按商户整理", reason: "\(entries.count) 笔记为 \(category ?? use.title)", items: items)
    }
    fileprivate static func changeSet(groups: [UnsortedPartyGroup], use: UnsortedUse,
                                      category: String?, otherAccount: UUID?, in ledger: Ledger) -> ChangeSet? {
        guard !groups.isEmpty else { return nil }
        var items: [ChangeItem] = []
        for group in groups {
            // Live but incompatible selections fail atomically. Missing groups were
            // already dropped by the confirmation-time snapshot lookup.
            guard let change = changeSet(group: group, use: use, category: category, otherAccount: otherAccount,
                                         entryIDs: nil, purpose: nil, in: ledger) else { return nil }
            items += change.items
        }
        let count = groups.reduce(0) { $0 + $1.entries.count }
        return ChangeSet(source: "按商户整理", reason: "\(groups.count) 组 · \(count) 笔记为\(category ?? use.title)", items: items)
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
                                  entryIDs: Set<UUID>? = nil, purpose: String? = nil,
                                  revision: UInt64, in ledger: Ledger) -> ChangeSet? {
        guard let group = snapshot(for: questionID, revision: revision, in: ledger)?.groupsByID[groupID] else { return nil }
        return UnsortedGroups.changeSet(group: group, use: use, category: category, otherAccount: otherAccount,
                                        entryIDs: entryIDs, purpose: purpose, in: ledger)
    }
    public mutating func changeSet(groupIDs: Set<String>, questionID: UUID, use: UnsortedUse,
                                  category: String? = nil, otherAccount: UUID? = nil,
                                  revision: UInt64, in ledger: Ledger) -> ChangeSet? {
        guard let snapshot = snapshot(for: questionID, revision: revision, in: ledger) else { return nil }
        return UnsortedGroups.changeSet(groups: snapshot.groups.filter { groupIDs.contains($0.id) }, use: use,
                                       category: category, otherAccount: otherAccount, in: ledger)
    }
}

/// Page-local order only. Reconcile with every live snapshot, including checkpoints
/// and undo. Known identities stay in the denominator when sorted elsewhere.
public struct UnsortedQuickSession: Sendable {
    public private(set) var queue: [String] = []
    private var known: Set<String> = []
    private var recorded: Set<String> = []
    public var total: Int { known.count }
    public var done: Int { recorded.count }
    public init() {}
    public mutating func reconcile(_ groups: [UnsortedPartyGroup]) {
        let live = Set(groups.map(\.id))
        queue.removeAll { !live.contains($0) }
        let queued = Set(queue)
        queue += groups.map(\.id).filter { !queued.contains($0) }
        known.formUnion(live)
    }
    public mutating func skip(_ groupID: String) {
        queue.removeAll { $0 == groupID }; queue.append(groupID)
    }
    public mutating func record(_ groupID: String) {
        recorded.insert(groupID); queue.removeAll { $0 == groupID }
    }
    public mutating func restore(_ groupID: String) {
        recorded.remove(groupID); queue.removeAll { $0 == groupID }; queue.insert(groupID, at: 0)
    }
}

/// The same before-value recovery approach as ImportUndo, scoped to this action.
/// It survives unrelated checkpoints without restoring the whole ledger. A later
/// edit of an affected row/key takes precedence over this older undo.
public struct UnsortedGroupsUndo: Sendable {
    private let ledgerID: UUID
    private let originals: [Entry]
    private let applied: [UUID: Entry]
    private let memoryBefore: [String: String]
    private let memoryAfter: [String: String]
    public init(before: Ledger, after: Ledger, entryIDs: Set<UUID>) {
        ledgerID = before.id
        originals = before.entries.filter { entryIDs.contains($0.id) }
        applied = Dictionary(uniqueKeysWithValues: after.entries.filter { entryIDs.contains($0.id) }.map { ($0.id, $0) })
        let keys = Set(before.classificationMemory.keys).union(after.classificationMemory.keys).filter {
            before.classificationMemory[$0] != after.classificationMemory[$0]
        }
        memoryBefore = before.classificationMemory.filter { keys.contains($0.key) }
        memoryAfter = after.classificationMemory.filter { keys.contains($0.key) }
    }
    public func restore(in ledger: inout Ledger) {
        guard ledger.id == ledgerID else { return }
        let positions = Dictionary(uniqueKeysWithValues: ledger.entries.indices.map { (ledger.entries[$0].id, $0) })
        for entry in originals {
            if let i = positions[entry.id], ledger.entries[i] == applied[entry.id] { ledger.entries[i] = entry }
        }
        for key in Set(memoryBefore.keys).union(memoryAfter.keys) where ledger.classificationMemory[key] == memoryAfter[key] {
            ledger.classificationMemory[key] = memoryBefore[key]
        }
    }
}

public struct UnsortedEntryField: Equatable, Sendable {
    public let key: String
    public let value: String
}

/// Display projections only. Read and parse attachments on demand, off the UI thread.
public enum UnsortedEntryPresentation {
    public static func summary(_ entry: Entry) -> String {
        let parts = entry.title.components(separatedBy: " · ").filter { !$0.isEmpty }
        let note = entry.note.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let summary = parts.dropFirst().joined(separator: " · ")
        return [summary, parts.first ?? "", note].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public static func fallbackFields(_ entry: Entry, account: String, hideAmounts: Bool) -> [UnsortedEntryField] {
        [UnsortedEntryField(key: "时间", value: Dates.text(entry.date, time: true)),
         UnsortedEntryField(key: "金额", value: hideAmounts ? "••••" : Money.text(entry.nature.inflow ? entry.amount : -entry.amount)),
         UnsortedEntryField(key: "账户", value: account),
         UnsortedEntryField(key: "账目", value: entry.title),
         UnsortedEntryField(key: "备注", value: entry.note)]
    }

    /// sourceRow is the one-based parsed table row used by BillImporter, including
    /// preamble rows and quoted multiline cells. Preserve original column order.
    public static func sourceFields(data: Data, filename: String, sourceRow: Int) throws -> [UnsortedEntryField] {
        let table = filename.lowercased().hasSuffix(".xlsx") ? try XLSX.read(data)
            : try CSV.parse(CSV.decode(data), delimiter: filename.lowercased().hasSuffix(".tsv") ? "\t" : nil)
        guard sourceRow > 1, table.indices.contains(sourceRow - 1) else { return [] }
        let preceding = table.prefix(sourceRow - 1)
        let dates = Set(BillImporter.dateNames.map(BillImporter.normalized))
        let amounts = Set(BillImporter.amountNames.map(BillImporter.normalized))
        let header = preceding.firstIndex { row in
            let keys = Set(row.map(BillImporter.normalized))
            return !keys.isDisjoint(with: dates) && !keys.isDisjoint(with: amounts)
        } ?? preceding.firstIndex { row in row.contains { dates.contains(BillImporter.normalized($0)) } }
            ?? preceding.firstIndex { $0.count > 1 }
        guard let header else { return [] }
        let keys = table[header], values = table[sourceRow - 1]
        return (0..<max(keys.count, values.count)).map { index in
            let key = keys.indices.contains(index) ? keys[index] : ""
            return UnsortedEntryField(key: key.isEmpty ? String(index + 1) : key,
                                      value: values.indices.contains(index) ? values[index] : "")
        }
    }
}
