import Foundation

public struct UnsortedPartyGroup: Identifiable, Equatable, Sendable {
    public var id: String { (inflow ? "in:" : "out:") + party }
    public let party: String
    public let inflow: Bool
    /// Newest first, with a stable tie-breaker. The UI only renders the first four.
    public let entries: [Entry]
    public var total: Int64 { entries.reduce(0) { $0 + $1.amount } }
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

/// Pure projections over the question's original coverage. No cached counts or
/// destructive removal: normal edits, deletions and undo are reflected immediately.
public enum UnsortedGroups {
    public static func needsSorting(_ entry: Entry) -> Bool {
        entry.deletedAt == nil && entry.mergedIntoID == nil && entry.otherAccountID == nil &&
        entry.planID == nil && entry.rentID == nil && entry.relatedEntryID == nil &&
        Classification.isPending(entry) && (entry.nature.uncertain || [Nature.expense, .income].contains(entry.nature))
    }
    public static func entries(for question: ImportQuestion, in ledger: Ledger) -> [Entry] {
        guard question.isFallback else { return [] }
        let ids = Set(question.entryIDs)
        let referenced = Set(ledger.activeEntries.compactMap(\.relatedEntryID))
        return ledger.entries.filter { ids.contains($0.id) && needsSorting($0) && !referenced.contains($0.id) }
    }
    public static func groups(for question: ImportQuestion, in ledger: Ledger) -> [UnsortedPartyGroup] {
        struct Key: Hashable { let party: String; let inflow: Bool }
        let grouped = Dictionary(grouping: entries(for: question, in: ledger)) {
            Key(party: $0.title.components(separatedBy: " · ")[0], inflow: $0.nature.inflow)
        }
        return grouped.map { key, entries in
            UnsortedPartyGroup(party: key.party, inflow: key.inflow, entries: entries.sorted {
                $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
            })
        }.sorted {
            if $0.entries.count != $1.entries.count { return $0.entries.count > $1.entries.count }
            return $0.id < $1.id
        }
    }
    public static func otherAccounts(for group: UnsortedPartyGroup, in ledger: Ledger) -> [Account] {
        let sourceIDs = Set(group.entries.map(\.accountID))
        return ledger.accounts.filter { !$0.archived && !sourceIDs.contains($0.id) }
    }
    public static func uses(for group: UnsortedPartyGroup, in ledger: Ledger) -> [UnsortedUse] {
        let uses: [UnsortedUse] = group.inflow ? [.income, .investSell, .transfer, .loanRecovery] : [.expense, .investBuy, .transfer, .repayment, .lend]
        return uses.filter { $0 != .transfer || !otherAccounts(for: group, in: ledger).isEmpty }
    }
    /// Re-read the live group at confirmation so stale selections cannot change
    /// rows that were classified elsewhere while this page was open.
    public static func changeSet(groupID: String, question: ImportQuestion, use: UnsortedUse,
                                 category: String? = nil, otherAccount: UUID? = nil, in ledger: Ledger) -> ChangeSet? {
        guard let group = groups(for: question, in: ledger).first(where: { $0.id == groupID }),
              uses(for: group, in: ledger).contains(use) else { return nil }
        if use.needsCategory {
            guard let category, ledger.selectableCategories.contains(where: { $0.name == category && $0.income == group.inflow }) else { return nil }
        }
        if use == .transfer {
            guard let otherAccount, otherAccounts(for: group, in: ledger).contains(where: { $0.id == otherAccount }) else { return nil }
        }
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
