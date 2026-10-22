import Foundation

public struct HabitLine: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable { case category, merchant }
    public let kind: Kind
    public let title: String
    public let total: Int64
    public let count: Int
    public var id: String { kind.rawValue + ":" + title }
    public var countPerWeek: Double { Double(count) * 7 / 90 }
    /// Integer cents, discarding fractions of a cent, as in compare_to_habit.
    public var average: Int64 { count == 0 ? 0 : total / Int64(count) }
}

public enum ProfileHabits {
    /// Last 90 calendar days through now. Categories and exact raw titles (merchant
    /// proxies) overlap; these five lines must not be added together.
    public static func summary(_ ledger: Ledger, now: Date = Date()) -> [HabitLine] {
        let start = Dates.addDays(-89, to: Dates.day(now))
        let byID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        var totals: [String: (kind: HabitLine.Kind, title: String, total: Int64, count: Int)] = [:]
        for entry in ledger.activeEntries where entry.date >= start && entry.date <= now {
            guard entry.nature == .expense || entry.nature == .refund else { continue }
            let original = entry.nature == .refund ? entry.relatedEntryID.flatMap { byID[$0] } : nil
            let category = ledger.resolveCategory(Finance.spendingCategory(entry, entriesByID: byID))
            let merchant = (original ?? entry).title.trimmingCharacters(in: .whitespacesAndNewlines)
            for (kind, title) in [(HabitLine.Kind.category, category), (.merchant, merchant)] where !title.isEmpty {
                let key = kind.rawValue + ":" + title
                var line = totals[key] ?? (kind, title, 0, 0)
                line.total += Finance.spendingAmount(entry, ledger: ledger)
                if entry.nature == .expense { line.count += 1 }
                totals[key] = line
            }
        }
        return Array(totals.values.filter { $0.total > 0 && $0.count > 0 }.map {
            HabitLine(kind: $0.kind, title: $0.title, total: $0.total, count: $0.count)
        }.sorted {
            if $0.total != $1.total { return $0.total > $1.total }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.id < $1.id
        }.prefix(5))
    }
}

public extension SoftLimit {
    var text: String {
        var parts: [String] = []
        if let count = perWeekCount { parts.append("每周最多 \(count) 次") }
        if let amount = perMonthAmount { parts.append("每月最多 " + Money.text(amount)) }
        return parts.joined(separator: " · ")
    }
}

public extension ProfileArea {
    /// Monday-based current week and current calendar month through now. A category
    /// OR any keyword matches; empty selectors match nothing. Refunds follow the
    /// original expense for matching and reduce amount, never the purchase count.
    func usage(in ledger: Ledger, now: Date = Date()) -> (weekCount: Int, monthAmount: Int64) {
        var calendar = Dates.calendar; calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
        let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? Dates.day(now)
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? Dates.day(now)
        let totals = usageTotals(in: ledger, from: min(week, month), through: now, countFrom: week, amountFrom: month)
        return (totals.count, totals.amount)
    }
    /// Inclusive interval, sharing category/keyword and refund semantics with the
    /// current-week/month usage above and the four-week profile review.
    func usage(in ledger: Ledger, from start: Date, through end: Date) -> (count: Int, amount: Int64) {
        usageTotals(in: ledger, from: start, through: end, countFrom: start, amountFrom: start)
    }
    private func usageTotals(in ledger: Ledger, from start: Date, through end: Date, countFrom: Date, amountFrom: Date) -> (count: Int, amount: Int64) {
        let categories = Set(match.categories.map { ledger.resolveCategory($0) })
        let keywords = match.keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let byID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        var count = 0; var amount: Int64 = 0
        for entry in ledger.activeEntries where entry.date >= start && entry.date <= end {
            guard entry.nature == .expense || entry.nature == .refund else { continue }
            let original = entry.nature == .refund ? entry.relatedEntryID.flatMap { byID[$0] } : nil
            let source = original ?? entry
            let category = ledger.resolveCategory(Finance.spendingCategory(entry, entriesByID: byID))
            let text = source.title + " " + (source.purpose ?? "") + " " + source.note
            guard categories.contains(category) || keywords.contains(where: { text.localizedCaseInsensitiveContains($0) }) else { continue }
            if entry.date >= countFrom && entry.nature == .expense { count += 1 }
            if entry.date >= amountFrom { amount += Finance.spendingAmount(entry, ledger: ledger) }
        }
        return (count, max(0, amount))
    }
}
