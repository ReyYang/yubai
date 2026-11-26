import Foundation

public struct HomeBudget: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let categories: [String]
    public let amount: Int64
    public let baseAmount: Int64
    public let spent: Int64
    public var remaining: Int64 { max(0, amount - spent) }
    public var over: Int64 { max(0, spent - amount) }
    public var fraction: Double { amount > 0 ? max(0, Double(spent) / Double(amount)) : 0 }
}

public struct HomeBudgets: Equatable, Sendable {
    public static let homeCount = 3
    public let ordered: [HomeBudget]
    public let unbudgeted: [String]
    public var home: ArraySlice<HomeBudget> { ordered.prefix(Self.homeCount) }
    public var other: ArraySlice<HomeBudget> { ordered.dropFirst(Self.homeCount) }

    public init(in ledger: Ledger, now: Date) {
        if ledger.spendingParts.isEmpty {
            let matches = Dictionary(uniqueKeysWithValues: ledger.profile.restrain.map {
                ($0.id, Self.isCategoryWatch($0) ? $0.match.categories : [])
            })
            ordered = SoftLines.usage(ledger, now: now).filter { $0.mode == .amount }.map {
                HomeBudget(id: $0.areaID, name: $0.title, categories: matches[$0.areaID] ?? [], amount: $0.limit, baseAmount: $0.limit, spent: $0.used)
            }
        } else {
            ordered = SpendingParts.summary(ledger, now: now).parts.map {
                HomeBudget(id: $0.id, name: $0.part.name, categories: $0.part.categories, amount: $0.allowance, baseAmount: $0.baseAllowance, spent: $0.spent)
            }
        }
        let assigned = Set(ordered.flatMap(\.categories))
        unbudgeted = ledger.orderedCategories(income: false).map(\.name).filter { !assigned.contains($0) }
    }

    public static func move(_ id: UUID, to destination: UUID, in ledger: inout Ledger) {
        guard id != destination else { return }
        if ledger.spendingParts.isEmpty {
            let ids = ledger.profile.restrain.filter { $0.softLimit?.periodAmount != nil }.prefix(homeCount).map(\.id)
            guard ids.contains(id), ids.contains(destination),
                  let from = ledger.profile.restrain.firstIndex(where: { $0.id == id }),
                  let to = ledger.profile.restrain.firstIndex(where: { $0.id == destination }) else { return }
            let row = ledger.profile.restrain.remove(at: from)
            ledger.profile.restrain.insert(row, at: to)
        } else {
            let ids = ledger.spendingParts.prefix(homeCount).map(\.id)
            guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: destination) else { return }
            let row = ledger.spendingParts.remove(at: from)
            ledger.spendingParts.insert(row, at: to)
        }
    }

    private static func isCategoryWatch(_ watch: ProfileArea) -> Bool {
        watch.match.categories.count == 1 && watch.match.subcategories.isEmpty && watch.match.keywords.isEmpty
    }

    private static func clearAmount(at index: Int, in ledger: inout Ledger) {
        guard var limit = ledger.profile.restrain[index].softLimit else { return }
        limit.perPeriodAmount = nil
        limit.perMonthAmount = nil
        ledger.profile.restrain[index].softLimit = limit.periodCount == nil ? nil : limit
    }

    public static func set(_ amount: Int64?, id: UUID? = nil, category: String? = nil, in ledger: inout Ledger, now: Date) throws {
        guard amount.map({ (1...Money.limit).contains($0) }) ?? true else { throw YubaiError.invalid("预算金额无效。") }
        var next = ledger
        if let id, !next.spendingParts.contains(where: { $0.id == id }),
           let index = next.profile.restrain.firstIndex(where: { $0.id == id }),
           var watch = next.profile.restrain[index].softLimit {
            watch.perPeriodAmount = amount
            watch.perMonthAmount = nil
            next.profile.restrain[index].softLimit = amount == nil && watch.periodCount == nil ? nil : watch
        } else {
            if let id, !next.spendingParts.contains(where: { $0.id == id }) { throw YubaiError.invalid("预算已删除。") }
            if let id, let index = next.spendingParts.firstIndex(where: { $0.id == id }) {
                if let amount {
                    next.spendingParts[index].amount = amount
                    if next.partsMode == .share { next.spendingParts[index].fixedAmountOverride = amount }
                } else {
                    let categories = Set(next.spendingParts.remove(at: index).categories)
                    next.partCarry[id] = nil
                    for watchIndex in next.profile.restrain.indices {
                        let watch = next.profile.restrain[watchIndex]
                        if isCategoryWatch(watch), watch.id == id || watch.match.categories.contains(where: categories.contains) {
                            clearAmount(at: watchIndex, in: &next)
                        }
                    }
                    for index in next.entries.indices where next.entries[index].partID == id { next.entries[index].partID = nil }
                }
            } else if let amount, let category {
                guard next.selectableCategories.contains(where: { !$0.income && $0.name == category }) else {
                    throw YubaiError.invalid("分类已删除。")
                }
                if next.spendingParts.isEmpty {
                    var claimed = Set<String>()
                    for index in next.profile.restrain.indices {
                        let watch = next.profile.restrain[index]
                        guard isCategoryWatch(watch), let limit = watch.softLimit?.periodAmount,
                              let category = watch.match.categories.first, claimed.insert(category).inserted else { continue }
                        var part = SpendingPart(id: watch.id, name: watch.title, amount: limit, categories: [category])
                        if next.partsMode == .share, limit > 0 { part.fixedAmountOverride = limit }
                        next.spendingParts.append(part)
                        clearAmount(at: index, in: &next)
                    }
                }
                if let index = next.spendingParts.firstIndex(where: { $0.categories.contains(category) }) {
                    next.spendingParts[index].amount = amount
                    if next.partsMode == .share { next.spendingParts[index].fixedAmountOverride = amount }
                } else {
                    var part = SpendingPart(name: Classification.displayCategory(category), amount: amount, categories: [category])
                    if next.partsMode == .share { part.fixedAmountOverride = amount }
                    next.spendingParts.append(part)
                }
            } else { return }
        }
        try next.validate()
        ledger = next
    }
}

public struct DailySpending: Equatable, Sendable {
    public static let columnCount = 30
    public let amounts: [Int64]
    public let today: Int
    public let evenPace: Int64?

    public init(in ledger: Ledger, period: SpendableBreakdown) {
        let periodStart = Dates.day(period.cycleStart)
        let elapsed = Dates.calendar.dateComponents([.day], from: periodStart, to: Dates.day(period.asOf)).day ?? 0
        // Keep today visible during a long or overdue payday cycle.
        let shift = max(0, elapsed - Self.columnCount + 1)
        today = max(0, elapsed - shift)
        let start = Dates.addDays(shift, to: periodStart)
        let spent = Set(period.rows.first(where: { $0.kind == .spent })?.entryIDs ?? [])
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        var totals = Array(repeating: Int64(0), count: Self.columnCount)
        for entry in ledger.entries where spent.contains(entry.id) && entry.date >= start {
            let index = Dates.calendar.dateComponents([.day], from: start, to: Dates.day(entry.date)).day ?? 0
            guard totals.indices.contains(index) else { continue }
            let original = entry.relatedEntryID.flatMap { lookup[$0] } ?? entry
            totals[index] += EntryRecovery.spendableAmount(entry, original: original, in: ledger)
        }
        amounts = totals
        evenPace = period.income > 0 ? max(0, period.budget) / Int64(period.daysTotal) : nil
    }
}

public extension Ledger {
    func searchBills(_ query: String, now: Date) -> [Entry] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return activeEntries.filter { entry in
            guard entry.date <= now else { return false }
            let assignment = normalizedCategory(for: entry, entriesByID: lookup)
            let fields = [entry.title, entry.purpose ?? "", entry.category, entry.subcategory ?? "", entry.note,
                          assignment.category, assignment.subcategory ?? "", Classification.displayCategory(assignment.category)]
            return terms.allSatisfy { term in fields.contains { $0.localizedStandardContains(term) } }
        }.sorted {
            ($0.date, $0.recordedAt ?? $0.date, $0.id.uuidString) > ($1.date, $1.recordedAt ?? $1.date, $1.id.uuidString)
        }
    }
}
