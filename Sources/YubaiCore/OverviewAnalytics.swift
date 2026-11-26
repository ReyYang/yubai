import Foundation

public enum OverviewPeriodSelection: Hashable, Sendable {
    case current, previous, custom(start: Date, end: Date)
}

public enum OverviewQuickRange: CaseIterable, Sendable {
    case lastThreeCycles, thisYear, samePeriodLastYear

    public func selection(in ledger: Ledger, now: Date) -> OverviewPeriodSelection {
        let cycle = Finance.cycle(in: ledger, now: now)
        let today = Dates.day(now)
        switch self {
        case .lastThreeCycles:
            let cycles = OverviewAnalytics.comparisonCycles(in: ledger, now: now, currentStart: cycle.start)
            return .custom(start: Dates.day(cycles.earlier.start), end: today)
        case .thisYear:
            return .custom(start: Dates.calendar.dateInterval(of: .year, for: today)!.start, end: today)
        case .samePeriodLastYear:
            return .custom(start: Dates.addMonths(-12, to: Dates.day(cycle.start)), end: Dates.addMonths(-12, to: today))
        }
    }
}

public struct OverviewPeriodWindow: Equatable, Sendable {
    public let interval: DateInterval
    public let comparison: DateInterval
    public let displayedRange: ClosedRange<Date>
}

public struct OverviewCategorySlice: Equatable, Sendable, Identifiable {
    public var id: String { category }
    public let category: String
    public let categories: [String]
    public let amount: Int64
    public let previous: Int64
    public let isOther: Bool
    public let isAnomaly: Bool
    public var changePercent: Double? {
        guard let percent = OverviewAnalytics.changePercent(amount, previous: previous), abs(percent) >= 20 else { return nil }
        return percent
    }
}

public struct OverviewReviewSnapshot: Equatable, Sendable {
    public let spent: Int64
    public let previousSpent: Int64
    public let saved: Int64
    public let previousSaved: Int64
    public var savedDelta: Int64 { saved - previousSaved }
    public let window: OverviewPeriodWindow
    public let anomaly: OverviewCategorySlice?
    public let slices: [OverviewCategorySlice]
}

public struct OverviewCategoryDrill: Equatable, Sendable {
    public let title: String
    public let amount: Int64
    public let previous: Int64
    public var changePercent: Double? { OverviewAnalytics.changePercent(amount, previous: previous) }
    public let isAnomaly: Bool
    public let slices: [OverviewCategorySlice]
    public let entries: [Entry]
    public let entryGroups: [UUID: String]
    public var totalCount: Int { entries.count }
    public let budget: HomeBudget?
    public let window: OverviewPeriodWindow
}

public extension Account {
    var lastReconciledAt: Date? {
        reconciled && anchorDate.timeIntervalSince1970 != -2_208_988_800 ? anchorDate : nil
    }
}

public struct OverviewAssetsSnapshot: Equatable, Sendable {
    public struct Balance: Equatable, Sendable, Identifiable {
        public var id: UUID { account.id }
        public let account: Account
        public let amount: Int64
        public var updatedAt: Date { account.anchorDate }
        public var lastReconciledAt: Date? { account.lastReconciledAt }
    }
    public let floorAmount: Int64
    public let reserveAmount: Int64
    public var liquidCash: Int64 { floorAmount + reserveAmount }
    public let accounts: [Balance]
    public let investments: [Balance]
}

public struct OverviewBalanceSeries: Equatable, Sendable {
    public let points: [Int64]
    public let highlightIndex: Int?
    public let highlightLabel: String?
    public let startLabel: String
    public let endLabel: String
    public let recentEntries: [Entry]
}

public enum OverviewAnalytics {
    public static func periodWindow(selection: OverviewPeriodSelection, in ledger: Ledger, now: Date) -> OverviewPeriodWindow {
        let current = Finance.cycle(in: ledger, now: now)
        switch selection {
        case .current:
            let previous = comparisonCycles(in: ledger, now: now, currentStart: current.start).previous
            let end = min(now, Dates.addDays(1, to: Dates.day(current.end)))
            let elapsed = Dates.calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: current.start, to: end)
            let comparisonEnd = min(previous.end, Dates.calendar.date(byAdding: elapsed, to: previous.start) ?? previous.start)
            // An exclusive endpoint immediately after now includes the posting at now.
            let inclusiveNow = Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.nextUp)
            return OverviewPeriodWindow(interval: DateInterval(start: current.start, end: end == now ? inclusiveNow : end),
                                        comparison: DateInterval(start: previous.start, end: comparisonEnd),
                                        displayedRange: Dates.day(current.start)...Dates.day(current.end))
        case .previous:
            let (previous, earlier) = comparisonCycles(in: ledger, now: now, currentStart: current.start)
            let days = dayCount(from: previous.start, to: previous.end)
            let comparisonEnd = min(Dates.addDays(days, to: earlier.start), earlier.end)
            return OverviewPeriodWindow(interval: previous,
                                        comparison: DateInterval(start: earlier.start, end: comparisonEnd),
                                        displayedRange: Dates.day(previous.start)...Dates.day(previous.end.addingTimeInterval(-1)))
        case let .custom(first, last):
            let start = Dates.day(min(first, last))
            let lastDay = Dates.day(max(first, last))
            let end = Dates.addDays(1, to: lastDay)
            let comparisonStart = Dates.addDays(-dayCount(from: start, to: end), to: start)
            return OverviewPeriodWindow(interval: DateInterval(start: start, end: end),
                                        comparison: DateInterval(start: comparisonStart, end: start),
                                        displayedRange: start...lastDay)
        }
    }

    fileprivate static func comparisonCycles(in ledger: Ledger, now: Date, currentStart: Date)
        -> (previous: DateInterval, earlier: DateInterval) {
        let closed = Finance.pastCycles(ledger, now: now, limit: 2)
        let previous = closed.first ?? completedCycle(in: ledger, before: currentStart)
        let earlier = closed.dropFirst().first { $0.end <= previous.start } ?? completedCycle(in: ledger, before: previous.start)
        return (previous, earlier)
    }

    private static func completedCycle(in ledger: Ledger, before start: Date) -> DateInterval {
        let cycle = Finance.cycle(in: ledger, now: start.addingTimeInterval(-1))
        return DateInterval(start: cycle.start, end: min(start, Dates.addDays(1, to: Dates.day(cycle.end))))
    }

    public static func review(in ledger: Ledger, selection: OverviewPeriodSelection, now: Date) -> OverviewReviewSnapshot {
        let data = spending(in: ledger, selection: selection, now: now)
        let byCategory = totals(data.current) { $0.assignment.category }
        let comparison = totals(data.previous) { $0.assignment.category }
        let anomaly = anomalyCategory(byCategory, comparison)
        let ordered = orderedTotals(byCategory)
        var slices = ordered.prefix(5).map { category, amount in
            slice(category, amount: amount, previous: comparison[category, default: 0], anomaly: category == anomaly)
        }
        let rest = ordered.dropFirst(5)
        if !rest.isEmpty {
            let members = rest.map(\.key)
            slices.append(OverviewCategorySlice(category: "其他 \(members.count) 类", categories: members,
                                                amount: rest.reduce(0) { $0 + $1.value },
                                                previous: members.reduce(0) { $0 + comparison[$1, default: 0] },
                                                isOther: true, isAnomaly: false))
        }
        let savingsCycles = historicalSavingCycles(in: ledger, since: data.window.comparison.start, now: now)
        return OverviewReviewSnapshot(spent: data.current.reduce(0) { $0 + $1.amount },
                                      previousSpent: data.previous.reduce(0) { $0 + $1.amount },
                                      saved: saving(in: ledger, during: data.window.interval, closedCycles: savingsCycles, now: now),
                                      previousSaved: saving(in: ledger, during: data.window.comparison, closedCycles: savingsCycles, now: now),
                                      window: data.window,
                                      anomaly: anomaly.map { slice($0, amount: byCategory[$0, default: 0], previous: comparison[$0, default: 0], anomaly: true) },
                                      slices: slices.sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount })
    }

    public static func categoryDrill(in ledger: Ledger, title: String, categories: [String], isOther: Bool,
                                     selection: OverviewPeriodSelection, now: Date) -> OverviewCategoryDrill {
        let data = spending(in: ledger, selection: selection, now: now)
        let members = Set(categories)
        let current = data.current.filter { members.contains($0.assignment.category) }
        let previous = data.previous.filter { members.contains($0.assignment.category) }
        let anomaly = !isOther && categories.count == 1 && categories.first == anomalyCategory(
            totals(data.current) { $0.assignment.category }, totals(data.previous) { $0.assignment.category })
        func group(_ row: Spending) -> String {
            isOther ? row.assignment.category : row.assignment.subcategory ?? "未分类"
        }
        let earlier = totals(previous, by: group)
        let ordered = orderedTotals(totals(current, by: group))
        let slices = ordered.enumerated().map { index, pair in
            slice(pair.key, amount: pair.value, previous: earlier[pair.key, default: 0], anomaly: anomaly && index == 0)
        }
        let budget = !isOther && categories.count == 1 ? HomeBudgets(in: ledger, now: now).ordered.first {
            $0.categories.contains(categories[0])
        } : nil
        return OverviewCategoryDrill(title: title, amount: current.reduce(0) { $0 + $1.amount },
                                     previous: previous.reduce(0) { $0 + $1.amount },
                                     isAnomaly: anomaly, slices: slices, entries: sortedEntries(current.map(\.entry)),
                                     entryGroups: Dictionary(uniqueKeysWithValues: current.map { ($0.entry.id, group($0)) }),
                                     budget: budget, window: data.window)
    }

    public static func assets(in ledger: Ledger, now: Date) -> OverviewAssetsSnapshot {
        let balances = ledger.accounts.filter { !$0.archived }.map {
            OverviewAssetsSnapshot.Balance(account: $0, amount: Finance.balance($0, in: ledger, at: now))
        }
        let totalSaved = max(0, ledger.fixedSavingsTotal(now: now))
        let floorAmount = min(totalSaved, max(0, ledger.profile.floorAmount ?? 0))
        return OverviewAssetsSnapshot(floorAmount: floorAmount,
                                      reserveAmount: totalSaved - floorAmount,
                                      accounts: balances.filter { $0.account.kind != .investment },
                                      investments: balances.filter { $0.account.kind == .investment })
    }

    public static func balanceSeries(for account: Account, in ledger: Ledger, now: Date, days: Int = 30) -> OverviewBalanceSeries {
        let today = Dates.day(now)
        let start = Dates.addDays(-max(0, days), to: today)
        let postings = ledger.entries.compactMap { entry -> Posting? in
            guard entry.deletedAt == nil, entry.accountID == account.id || (entry.nature.paired && entry.otherAccountID == account.id) else { return nil }
            let date = entry.postingDate(for: account.id)
            return Posting(entry: entry, date: date, delta: entry.delta(for: account.id), afterAnchor: account.includes(entry, posting: date))
        }.sorted {
            ($0.date, $0.entry.recordedAt ?? $0.date, $0.entry.id.uuidString)
                < ($1.date, $1.entry.recordedAt ?? $1.date, $1.entry.id.uuidString)
        }
        // Begin just before the first posting, then move forward once through the index.
        var balance = account.anchorBalance - postings.filter { !$0.afterAnchor }.reduce(0) { $0 + $1.delta }
        var index = 0
        var points: [Int64] = []
        var day = start
        while day <= today {
            let nextDay = Dates.addDays(1, to: day)
            while index < postings.count && postings[index].date < nextDay && postings[index].date <= now {
                balance += postings[index].delta
                index += 1
            }
            points.append(balance)
            day = nextDay
        }
        let positive = postings.filter { $0.date >= start && $0.date <= now && $0.delta > 0 && $0.entry.kind != .adjustment }
        let incomes = positive.filter { $0.entry.nature == .income }
        let daily = Dictionary(grouping: incomes.isEmpty ? positive : incomes) { Dates.day($0.date) }
        let highlight = daily.keys.sorted().max { first, second in
            daily[first, default: []].reduce(0) { $0 + $1.delta } < daily[second, default: []].reduce(0) { $0 + $1.delta }
        }
        let title = highlight.flatMap { daily[$0]?.max { $0.delta < $1.delta }?.entry.displayTitle }
        return OverviewBalanceSeries(points: points,
                                     highlightIndex: highlight.map { dayCount(from: start, to: $0) },
                                     highlightLabel: highlight.flatMap { date in title.map { monthDay(date) + " " + $0 } },
                                     startLabel: monthDay(start), endLabel: "今天",
                                     recentEntries: postings.reversed().filter { $0.date <= now }.map(\.entry))
    }

    public static func changePercent(_ amount: Int64, previous: Int64) -> Double? {
        previous > 0 ? (Double(amount) - Double(previous)) / Double(previous) * 100 : nil
    }

    private struct Posting {
        let entry: Entry
        let date: Date
        let delta: Int64
        let afterAnchor: Bool
    }

    private struct Spending {
        let entry: Entry
        let amount: Int64
        let assignment: CategoryAssignment
    }

    private static func spending(in ledger: Ledger, selection: OverviewPeriodSelection, now: Date)
        -> (window: OverviewPeriodWindow, current: [Spending], previous: [Spending]) {
        let window = periodWindow(selection: selection, in: ledger, now: now)
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        var current: [Spending] = [], previous: [Spending] = []
        for entry in ledger.entries where entry.date <= now {
            let inCurrent = contains(window.interval, entry.date)
            guard inCurrent || contains(window.comparison, entry.date),
                  let amount = Finance.periodSpending(for: entry, in: ledger, entriesByID: lookup) else { continue }
            let row = Spending(entry: entry, amount: amount, assignment: ledger.normalizedCategory(for: entry, entriesByID: lookup))
            if inCurrent { current.append(row) } else { previous.append(row) }
        }
        return (window, current, previous)
    }

    private static func historicalSavingCycles(in ledger: Ledger, since: Date, now: Date) -> [DateInterval] {
        let months = Dates.calendar.dateComponents([.month], from: since, to: now).month ?? 0
        return Finance.pastCycles(ledger, now: now, limit: max(2, months + 3))
    }

    private static func saving(in ledger: Ledger, during interval: DateInterval,
                               closedCycles: [DateInterval], now: Date) -> Int64 {
        let start = Finance.cycle(in: ledger, now: now).start
        // Set-aside is a cycle fact. Include each overlapping cycle once, even for a partial range.
        let active = interval.start <= now && interval.end > start
            ? Finance.spendableBreakdown(ledger, now: now).effectiveSaving : 0
        var matched = Set<Date>()
        var closed: Int64 = 0
        for cycle in closedCycles where interval.start < cycle.end && cycle.start < interval.end {
            let history = ledger.savingHistory
                .filter { abs($0.cycleStart.timeIntervalSince(cycle.start)) <= 36 * 3600 }
                .min { abs($0.cycleStart.timeIntervalSince(cycle.start)) < abs($1.cycleStart.timeIntervalSince(cycle.start)) }
            if let history {
                if matched.insert(history.cycleStart).inserted { closed += history.saved }
            } else {
                closed += Finance.closedFormula(ledger, cycleStart: cycle.start).saving
            }
        }
        let accountsByID = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
        let deposits = ledger.entries.reduce(Int64(0)) { total, entry in
            guard entry.deletedAt == nil else { return total }
            let posting = entry.nature == .investBuy ? entry.date
                : ledger.fixedSavingsPosting(for: entry, accountsByID: accountsByID, now: now)?.date
            guard let posting, posting <= now, contains(interval, posting) else { return total }
            return total + entry.amount
        }
        return active + closed + deposits
    }

    private static func anomalyCategory(_ current: [String: Int64], _ previous: [String: Int64]) -> String? {
        orderedTotals(current).first {
            !Classification.isPending($0.key) && (changePercent($0.value, previous: previous[$0.key, default: 0]) ?? 0) > 30
        }?.key
    }

    private static func totals(_ entries: [Spending], by key: (Spending) -> String) -> [String: Int64] {
        entries.reduce(into: [:]) { $0[key($1), default: 0] += $1.amount }
    }

    private static func orderedTotals(_ values: [String: Int64]) -> [(key: String, value: Int64)] {
        values.filter { $0.value > 0 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }

    private static func slice(_ title: String, amount: Int64, previous: Int64, anomaly: Bool) -> OverviewCategorySlice {
        OverviewCategorySlice(category: title, categories: [title], amount: amount, previous: previous, isOther: false, isAnomaly: anomaly)
    }

    private static func sortedEntries(_ entries: [Entry]) -> [Entry] {
        entries.sorted {
            ($0.date, $0.recordedAt ?? $0.date, $0.id.uuidString) > ($1.date, $1.recordedAt ?? $1.date, $1.id.uuidString)
        }
    }

    private static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        interval.start <= date && date < interval.end
    }

    private static func dayCount(from start: Date, to end: Date) -> Int {
        Dates.calendar.dateComponents([.day], from: Dates.day(start), to: Dates.day(end)).day ?? 0
    }

    public static func monthDay(_ date: Date) -> String {
        let components = Dates.calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d", components.month ?? 0, components.day ?? 0)
    }
}
