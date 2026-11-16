import Foundation

public struct SoftLineUsage: Equatable, Identifiable, Sendable {
    public enum Mode: Equatable, Sendable { case amount, count }
    public var areaID: UUID
    public var id: String { areaID.uuidString + (mode == .amount ? ":amount" : ":count") }
    public var title: String
    public var mode: Mode
    public var limit: Int64
    public var used: Int64
    public var entryIDs: [UUID]
    public var remaining: Int64 { max(0, limit - used) }
    public var exceeded: Int64 { max(0, used - limit) }
    public var isExceeded: Bool { used > limit }
}

public enum SoftLines {
    /// Legacy weekly/monthly limits remain decodable; their values now apply to
    /// the active Finance period, without converting the user's chosen numbers.
    public static func usage(_ ledger: Ledger, now: Date = Dates.now) -> [SoftLineUsage] {
        let cycle = Finance.cycle(in: ledger, now: now)
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        return ledger.profile.restrain.flatMap { area -> [SoftLineUsage] in
            guard let line = area.softLimit else { return [] }
            let entries = ledger.entries.filter { entry in
                guard entry.deletedAt == nil, entry.kind != .adjustment, entry.date >= cycle.start, entry.date <= now,
                      entry.nature == .expense || entry.nature == .refund else { return false }
                return ButlerCards.matches(area, entry: entry.nature == .refund ? entry.relatedEntryID.flatMap { lookup[$0] } ?? entry : entry, ledger: ledger)
            }
            var rows: [SoftLineUsage] = []
            if let limit = line.periodAmount {
                rows.append(SoftLineUsage(areaID: area.id, title: area.title, mode: .amount, limit: limit,
                    used: max(0, entries.reduce(0) { $0 + Finance.spendingAmount($1, ledger: ledger) }), entryIDs: entries.map(\.id)))
            }
            if let count = line.periodCount {
                rows.append(SoftLineUsage(areaID: area.id, title: area.title, mode: .count, limit: Int64(count),
                    used: Int64(entries.filter { $0.nature == .expense }.count), entryIDs: entries.filter { $0.nature == .expense }.map(\.id)))
            }
            return rows
        }
    }
    /// Preview a draft without saving. Sub-purpose matches precede whole-category
    /// matches; overlapping lines stay independent and never divide the total pot.
    public static func remainingAfterTyping(_ amount: Int64, category: String, subcategory: String? = nil, purpose: String = "",
                                           nature: Nature = .expense, in ledger: Ledger, now: Date = Dates.now) -> SoftLineUsage? {
        guard nature == .expense else { return nil }
        var sample = Entry(date: now, amount: max(0, amount), accountID: UUID(), title: purpose, category: category)
        sample.subcategory = subcategory
        let areas = ledger.profile.restrain.filter { ButlerCards.matches($0, entry: sample, ledger: ledger) }.sorted {
            let a = !$0.match.subcategories.isEmpty || !$0.match.keywords.isEmpty
            let b = !$1.match.subcategories.isEmpty || !$1.match.keywords.isEmpty
            return a != b ? a : $0.id.uuidString < $1.id.uuidString
        }
        let usages = usage(ledger, now: now)
        for area in areas {
            if var line = usages.first(where: { $0.areaID == area.id }) {
                if amount > 0 { line.used += line.mode == .count ? 1 : amount }
                return line
            }
        }
        return nil
    }
    public static func set(_ area: ProfileArea, in ledger: inout Ledger, now: Date) throws {
        var next = ledger, area = area
        guard area.softLimit != nil else { throw YubaiError.invalid("还没填想克制的数。") }
        let existing = next.profile.restrain.contains { $0.id == area.id && $0.softLimit != nil }
        guard existing || next.profile.restrain.filter({ $0.softLimit != nil }).count < 3 else { throw YubaiError.invalid("已经盯住 3 类。") }
        if let index = next.profile.restrain.firstIndex(where: { $0.id == area.id }) { next.profile.restrain[index] = area }
        else {
            area.confirmedAt = now; next.profile.restrain.append(area)
        }
        next.profile.updatedAt = now
        try next.validate(); ledger = next
    }
}
