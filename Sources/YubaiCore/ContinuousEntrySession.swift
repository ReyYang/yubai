import Foundation

/// Ephemeral receipt state. The ledger remains the source for edits, deletion and undo.
public struct ContinuousEntrySession: Equatable, Sendable {
    public static let linger: TimeInterval = 2
    public private(set) var entryIDs: [UUID] = []
    public private(set) var receiptVisible = false
    public private(set) var deadline: Date?
    public init() {}

    public mutating func saved(_ ids: [UUID], at now: Date, explicitFinish: Bool) {
        guard !ids.isEmpty else { return }
        for id in ids where !entryIDs.contains(id) { entryIDs.append(id) }
        receiptVisible = true
        deadline = explicitFinish ? nil : now.addingTimeInterval(Self.linger)
    }
    /// Called on touch, even when the input (for example a zero digit) does not change.
    public mutating func interact() { deadline = nil; receiptVisible = false }
    public mutating func requireExplicitFinish() { deadline = nil }
    public func shouldDismiss(at now: Date) -> Bool { deadline.map { now >= $0 } ?? false }
    public static func receiptFraction(deadline: Date?, at now: Date) -> Double {
        deadline.map { min(1, max(0, $0.timeIntervalSince(now) / linger)) } ?? 1
    }
    public func entries(in ledger: Ledger) -> [Entry] {
        let ids = Set(entryIDs)
        let rows = Dictionary(uniqueKeysWithValues: ledger.entries.filter { ids.contains($0.id) && $0.deletedAt == nil }.map { ($0.id, $0) })
        return entryIDs.compactMap { rows[$0] }
    }
    public func total(in ledger: Ledger) -> Int64 { entries(in: ledger).reduce(0) { $0 + $1.amount } }
}

extension EntryKeypad {
    /// Paste follows the same integer-cent validation as individual keys.
    public mutating func paste(_ text: String) throws {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "¥", with: "").replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "＋", with: "+").replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "")
        if input.contains(",") {
            for operand in input.split(whereSeparator: { $0 == "+" || $0 == "-" }) { _ = try Money.parse(String(operand)) }
        }
        let clean = input.replacingOccurrences(of: ",", with: "")
        let value = try Self.evaluate(clean)
        guard value >= 0 else { throw YubaiError.invalid("请输入有效金额。") }
        self = EntryKeypad(amount: value)
    }
    public var groupedResultText: String {
        let text = resultText.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(text[0]), negative = integer.hasPrefix("-")
        let digits = negative ? String(integer.dropFirst()) : integer
        let grouped = digits.reversed().enumerated().map { index, char in
            (index > 0 && index % 3 == 0 ? "," : "") + String(char)
        }.joined().reversed()
        return (negative ? "-" : "") + String(grouped) + "." + String(text[1])
    }
}

extension EntryHistory {
    /// Empty-purpose chips favor this category and this time of day; typing uses `recalls`.
    public static func purposeSuggestions(nature: Nature, category: String?, in ledger: Ledger, now: Date, limit: Int = 3) -> [Recall] {
        let minute = Dates.calendar.component(.hour, from: now) * 60 + Dates.calendar.component(.minute, from: now)
        return Array(recentPurposes(in: ledger, nature: nature, now: now, limit: ledger.entries.count)
            .filter { category == nil || $0.entry.category == category }
            .sorted { a, b in
                func distance(_ entry: Entry) -> Int {
                    let value = Dates.calendar.component(.hour, from: entry.date) * 60 + Dates.calendar.component(.minute, from: entry.date)
                    let delta = abs(value - minute)
                    return min(delta, 1440 - delta)
                }
                let aNear = distance(a.entry) <= 120, bNear = distance(b.entry) <= 120
                if aNear != bNear { return aNear }
                if a.count != b.count { return a.count > b.count }
                if a.entry.date != b.entry.date { return a.entry.date > b.entry.date }
                return a.purpose < b.purpose
            }.prefix(max(0, limit)))
    }
}
