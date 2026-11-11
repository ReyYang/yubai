import Foundation

public enum PartsMode: String, Codable, Sendable { case amount, share }
public enum PartLeftover: String, Codable, Sendable { case mergeIntoFixedSavings, rollOver }

public struct SpendingPart: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var amount: Int64?
    public var share: Int?
    public var categories: [String]
    /// An explicit unassigned override must differ from nil (automatic category).
    public static let unassignedID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public init(id: UUID = UUID(), name: String, amount: Int64? = nil, share: Int? = nil, categories: [String] = []) {
        self.id = id; self.name = name; self.amount = amount; self.share = share; self.categories = categories
    }
}

public struct SpendingPartBalance: Equatable, Identifiable, Sendable {
    public var id: UUID { part.id }
    public let part: SpendingPart
    public let baseAllowance: Int64
    public let allowance: Int64
    public let spent: Int64
    public var remaining: Int64 { max(0, allowance - spent) }
    public var overflow: Int64 { max(0, spent - allowance) }
}
public struct SpendingPartsSummary: Equatable, Sendable {
    public let available: Int64
    public let base: Int64
    public let parts: [SpendingPartBalance]
    /// Overspending draws from this pool; a negative part cannot inflate it.
    public var unassigned: Int64 { available - parts.reduce(0) { $0 + $1.remaining } }
}
public struct SpendingPartHint: Equatable, Sendable {
    public let id: UUID?
    public let name: String
    public let after: Int64
    public let overBy: Int64
}
public struct SpendingPartSuggestion: Equatable, Sendable {
    public let partID: UUID
    public let amount: Int64
    public let share: Int?
}

public enum SpendingParts {
    public static func part(for entry: Entry, in ledger: Ledger, entriesByID: [UUID: Entry]? = nil) -> SpendingPart? {
        var source = entry
        if entry.nature == .refund, let id = entry.relatedEntryID,
           let original = entriesByID.map({ $0[id] }) ?? ledger.entries.first(where: { $0.id == id }), original.nature == .expense { source = original }
        if let id = source.partID { return ledger.spendingParts.first { $0.id == id } }
        let main = ledger.normalizedCategory(for: source, entriesByID: entriesByID).category
        return ledger.spendingParts.first { $0.categories.contains(main) }
    }

    /// Bills are already reserved by Finance. All other spending uses its shared
    /// net expense/refund amounts, including personal shares and linked refunds.
    public static func flexibleAmount(_ entry: Entry, in ledger: Ledger, entriesByID: [UUID: Entry]? = nil) -> Int64 {
        var source = entry
        if entry.nature == .refund, let id = entry.relatedEntryID,
           let original = entriesByID.map({ $0[id] }) ?? ledger.entries.first(where: { $0.id == id }) { source = original }
        guard source.planID == nil, source.rentID == nil, !source.fromReserve else { return 0 }
        return Finance.spendingAmount(entry, ledger: ledger)
    }

    public static func summary(_ ledger: Ledger, now: Date = Date()) -> SpendingPartsSummary {
        let funds = Finance.funds(ledger, now: now)
        let rows = ledger.entries.filter { $0.deletedAt == nil && $0.date >= funds.cycleStart && $0.date <= now }
        let entriesByID = rows.contains(where: { $0.nature == .refund }) ? Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) }) : nil
        var spent: [UUID: Int64] = [:]; var total: Int64 = 0
        for entry in rows {
            let value = flexibleAmount(entry, in: ledger, entriesByID: entriesByID); total += value
            if value != 0, let part = part(for: entry, in: ledger, entriesByID: entriesByID) { spent[part.id, default: 0] += value }
        }
        let base = max(0, funds.available + total)
        let carryApplies = ledger.partLeftover == .rollOver && ledger.partCarryCycleStart.map {
            abs($0.timeIntervalSince(funds.cycleStart)) <= 36 * 3600
        } == true
        let parts = ledger.spendingParts.map { part in
            let allowance = ledger.partsMode == .amount ? max(0, part.amount ?? 0) : fraction(base, share: part.share ?? 0)
            return SpendingPartBalance(part: part, baseAllowance: allowance,
                allowance: allowance + (carryApplies ? ledger.partCarry[part.id, default: 0] : 0), spent: spent[part.id, default: 0])
        }
        return SpendingPartsSummary(available: funds.available, base: base, parts: parts)
    }

    static func fraction(_ base: Int64, share: Int) -> Int64 {
        var value = Decimal(base) * Decimal(share) / 10
        var rounded = Decimal(); NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Moving a category is atomic: each main category belongs to at most one part.
    public static func assign(category: String, to partID: UUID?, in ledger: inout Ledger) {
        let main = ledger.resolveCategory(category, income: false)
        for i in ledger.spendingParts.indices {
            ledger.spendingParts[i].categories.removeAll { $0 == main }
            if ledger.spendingParts[i].id == partID { ledger.spendingParts[i].categories.append(main) }
        }
    }

    /// Ranked net spending in the three completed calendar months. Refunds use
    /// the original expense category and personal shares follow Finance.
    public static func topCategories(ledger: Ledger, now: Date = Date()) -> [String] {
        let end = Dates.calendar.dateInterval(of: .month, for: now)!.start
        let start = Dates.addMonths(-3, to: end)
        let rows = Finance.cashFlow(ledger, during: DateInterval(start: start, end: end)).spendingByCategory
            .filter { $0.amount > 0 && $0.category != Classification.pendingCategory }
            .sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount }
        return rows.isEmpty ? ["餐饮", "购物", "交通", "娱乐"] : Array(rows.prefix(4).map(\.category))
    }

    /// Pure suggestion over up to three completed Finance cycles. A cycle before
    /// the earliest recorded row is unavailable; zero-spend categories still count.
    public static func suggestions(ledger: Ledger, now: Date = Date()) -> [SpendingPartSuggestion] {
        let start = Finance.cycle(in: ledger, now: now).start
        let entries = ledger.activeEntries.filter { $0.date < start }
        let entriesByID = entries.contains(where: { $0.nature == .refund }) ? Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) }) : nil
        let earliest = entries.map(\.date).min()
        var cursor = start
        var totals: [UUID: Int64] = [:]; var count: Int64 = 0
        for _ in 0..<3 {
            let cycle = Finance.cycle(in: ledger, now: cursor.addingTimeInterval(-0.001))
            guard let earliest, earliest < cursor else { break }
            count += 1
            for entry in entries where entry.date >= cycle.start && entry.date < cursor {
                // Suggestions follow the categories attached to a part, not a
                // one-off manual choice made on an old entry.
                let category = ledger.normalizedCategory(for: entry, entriesByID: entriesByID).category
                if let part = ledger.spendingParts.first(where: { $0.categories.contains(category) }) {
                    totals[part.id, default: 0] += flexibleAmount(entry, in: ledger, entriesByID: entriesByID)
                }
            }
            cursor = cycle.start
        }
        let amounts = ledger.spendingParts.map { part -> Int64 in
            guard count > 0 else { return 0 }
            return (max(0, totals[part.id, default: 0]) / count + 500) / 1000 * 1000
        }
        let base = summary(ledger, now: now).base
        let denominator = max(base, amounts.reduce(0, +))
        var shares = amounts.map { amount in denominator > 0 ? Int((Double(amount) * 10 / Double(denominator)).rounded()) : 0 }
        while shares.reduce(0, +) > 10 {
            let index = shares.indices.max { shares[$0] < shares[$1] }!
            shares[index] -= 1
        }
        return ledger.spendingParts.indices.map { i in
            SpendingPartSuggestion(partID: ledger.spendingParts[i].id, amount: amounts[i], share: shares[i] == 0 ? nil : shares[i])
        }
    }

    /// Replace the previous carry with the closing balance, once per period.
    /// The saved cycle marker prevents adding that same balance on every launch.
    static func closeCycle(_ ledger: inout Ledger, snapshot: Ledger, close: Date, nextStart: Date) {
        guard ledger.partLeftover == .rollOver else {
            ledger.partCarry = [:]; ledger.partCarryCycleStart = nil; return
        }
        let previous = summary(snapshot, now: close)
        ledger.partCarry = Dictionary(uniqueKeysWithValues: previous.parts.map { ($0.id, $0.remaining) })
        ledger.partCarryCycleStart = nextStart
    }
}

extension SpendingParts {
    public static func proposal(ledger: Ledger, now: Date) -> [SpendingPart] {
        let cycles = Finance.completedCycles(ledger, now: now, limit: 3)
        guard !cycles.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let from = cycles.last!.start, to = cycles.first!.end
        var totals: [String: Int64] = [:]
        for entry in ledger.entries where entry.deletedAt == nil && entry.date >= from && entry.date < to {
            let amount = flexibleAmount(entry, in: ledger, entriesByID: lookup)
            let source = entry.nature == .refund ? entry.relatedEntryID.flatMap { lookup[$0] } ?? entry : entry
            guard amount != 0, !Classification.isPending(source) else { continue }
            totals[ledger.normalizedCategory(for: entry, entriesByID: lookup).category, default: 0] += amount
        }
        let ranked = totals.filter { $0.value > 0 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return ranked.prefix(3).map { item -> SpendingPart in
            let category = item.key, amount = item.value
            let average = amount / Int64(cycles.count)
            // Stable ids keep repeated previews equal without persisting them.
            let hex = LedgerCodec.checksum(Data(category.utf8)).padding(toLength: 32, withPad: "0", startingAt: 0)
            let pieces = [String(hex.prefix(8)), String(hex.dropFirst(8).prefix(4)), String(hex.dropFirst(12).prefix(4)), String(hex.dropFirst(16).prefix(4)), String(hex.dropFirst(20).prefix(12))]
            let uuid = pieces.joined(separator: "-")
            return SpendingPart(id: UUID(uuidString: uuid) ?? SpendingPart.unassignedID, name: category,
                                amount: (average + 2500) / 5000 * 5000, categories: [category])
        }
    }
}
