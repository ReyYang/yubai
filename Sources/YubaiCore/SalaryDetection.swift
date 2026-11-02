import Foundation

public struct SalaryCandidate: Equatable, Sendable {
    public let key: String
    public let payer: String
    public let amount: Int64
    public let dayOfMonth: Int
    public let recentDates: [Date]
    public let entryIDs: [UUID]
    public let accountID: UUID
}

/// Local evidence only. Recognition never changes entries or creates a plan.
public enum SalaryDetection {
    public static func payerKey(_ title: String) -> String {
        let display = payerTitle(title)
        return display.filter { !$0.isWhitespace }.lowercased()
    }

    private static func payerTitle(_ title: String) -> String {
        let clean = BillImporter.counterpartyTitle(title)
        let stripped = clean.replacingOccurrences(of: #"[\s（(]*(?:[0-9][0-9*xX]*|[xX*]{2,}[0-9]+)[）)]*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : stripped
    }

    public static func candidate(in ledger: Ledger, now: Date = Date()) -> SalaryCandidate? {
        guard !ledger.plans.contains(where: { $0.active && $0.inflow && $0.nature == .income && $0.frequency == .monthly }) else { return nil }
        let groups = Dictionary(grouping: ledger.activeEntries.filter { $0.nature == .income && $0.date <= now && $0.amount > 0 }, by: { payerKey($0.title) })
        return groups.compactMap { key, entries -> SalaryCandidate? in
            guard !key.isEmpty, !ledger.dismissedSalaryKeys.contains(key), entries.count >= 2 else { return nil }
            // One dominant payment per month excludes occasional small remittances.
            // Keep a sustained stable run, rather than cherry-picking two similar
            // amounts out of an otherwise volatile salary history.
            let months = Dictionary(grouping: entries, by: { Dates.calendar.dateInterval(of: .month, for: $0.date)!.start })
            let peaks = months.values.compactMap { rows in
                rows.max { $0.amount == $1.amount ? $0.date < $1.date : $0.amount < $1.amount }
            }
            let values = peaks.map { Double($0.amount) }.sorted()
            let center = values.count / 2
            let typical = values.count.isMultiple(of: 2) ? (values[center - 1] + values[center]) / 2 : values[center]
            let stable = peaks.filter { abs(Double($0.amount) - typical) <= typical * 0.1 }
                .sorted { $0.date < $1.date }
            var runs: [[Entry]] = []
            for entry in stable {
                if let previous = runs.last?.last,
                   (26...35).contains(Dates.calendar.dateComponents([.day], from: Dates.day(previous.date), to: Dates.day(entry.date)).day ?? 0) {
                    runs[runs.count - 1].append(entry)
                } else { runs.append([entry]) }
            }
            // A stable run must cover at least three quarters of the monthly
            // peaks; a few similar payments cannot rescue a volatile history.
            guard let run = runs.max(by: { $0.count == $1.count ? $0.last!.date < $1.last!.date : $0.count < $1.count }),
                  run.count >= 2, run.count * 4 >= peaks.count * 3 else { return nil }
            let sorted = run.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
            for (previous, next) in zip(sorted, sorted.dropFirst()) {
                let days = Dates.calendar.dateComponents([.day], from: Dates.day(previous.date), to: Dates.day(next.date)).day ?? 0
                guard (26...35).contains(days) else { return nil }
            }
            let counts = Dictionary(grouping: sorted, by: { Dates.calendar.component(.day, from: $0.date) }).mapValues(\.count)
            // Prefer the later day on a tie, so Jan 31 / Feb 28 / Mar 31
            // keeps its monthly anchor instead of drifting to February's end.
            let day = counts.keys.max { counts[$0] == counts[$1] ? $0 < $1 : counts[$0]! < counts[$1]! }!
            guard sorted.allSatisfy({ entry in
                let last = Dates.calendar.range(of: .day, in: .month, for: entry.date)!.count
                return abs(Dates.calendar.component(.day, from: entry.date) - min(day, last)) <= 3
            }) else { return nil }
            let amounts = sorted.map { Double($0.amount) }.sorted()
            let middle = amounts.count / 2
            let median = amounts.count.isMultiple(of: 2) ? (amounts[middle - 1] + amounts[middle]) / 2 : amounts[middle]
            guard amounts.allSatisfy({ abs($0 - median) <= median * 0.1 }) else { return nil }
            let latest = sorted.last!
            return SalaryCandidate(key: key, payer: payerTitle(latest.title), amount: latest.amount, dayOfMonth: day,
                                   recentDates: sorted.suffix(3).map(\.date), entryIDs: sorted.map(\.id), accountID: latest.accountID)
        }.sorted { $0.amount == $1.amount ? $0.key < $1.key : $0.amount > $1.amount }.first
    }

    /// The caller can snapshot the ledger to undo this entire change atomically.
    @discardableResult public static func confirm(_ candidate: SalaryCandidate, in ledger: inout Ledger, now: Date = Date()) -> Plan? {
        guard let fresh = self.candidate(in: ledger, now: now), fresh.key == candidate.key else { return nil }
        let salary = ledger.categories.first { $0.income && !$0.system && ($0.name.contains("工资") || $0.subcategories.contains("工资")) }
        let fallback = ledger.categories.first { $0.income && $0.name == "其他收入" }
            ?? ledger.categories.first { $0.income && !$0.system }
        let category = salary?.name ?? fallback?.name ?? Classification.pendingCategory
        var plan = Plan(title: "工资", amount: fresh.amount, dueDate: nextPayday(day: fresh.dayOfMonth, after: now),
                        frequency: .monthly, inflow: true, category: category, nature: .income)
        plan.accountID = fresh.accountID
        plan.monthlyDay = fresh.dayOfMonth
        ledger.plans.append(plan)
        return plan
    }

    public static func dismiss(_ candidate: SalaryCandidate, in ledger: inout Ledger) {
        ledger.dismissedSalaryKeys.insert(candidate.key)
    }

    public static func nextPayday(day: Int, after now: Date) -> Date {
        let calendar = Dates.calendar
        let start = calendar.dateInterval(of: .month, for: now)!.start
        for offset in 0...1 {
            let month = Dates.addMonths(offset, to: start)
            let last = calendar.range(of: .day, in: .month, for: month)!.count
            let date = Dates.addDays(min(max(1, day), last) - 1, to: month)
            if date > Dates.day(now) { return date }
        }
        preconditionFailure("The next monthly payday must exist")
    }
}
