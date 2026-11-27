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
    /// What the row is called: the refunds row is 退款.
    public var title: String { category == OverviewAnalytics.refundGroup ? OverviewAnalytics.refundTitle : category }
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
    /// 多花: `previous` is the average of the same span in up to 3 earlier periods.
    public let anomaly: OverviewCategorySlice?
    public let slices: [OverviewCategorySlice]
    /// How many earlier periods the anomaly baseline averages (2 or 3).
    public var anomalyBaselineCycles: Int = 0
    /// Spending still in the catch-all category, when it is over 30% of the period.
    public var unsorted: (count: Int, amount: Int64)? { unsortedCount > 0 ? (unsortedCount, unsortedAmount) : nil }
    var unsortedCount = 0
    var unsortedAmount: Int64 = 0
    /// The 待整理 expenses behind `unsorted`, for 去整理.
    public internal(set) var unsortedEntryIDs: [UUID] = []
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
    /// Set for the 多花 drill: `previous` is then the average of this many earlier periods.
    public var baselineCycles: Int? = nil
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
        let overspend = anomaly(in: ledger, selection: selection, window: data.window, current: data.current, now: now)
        let anomaly = overspend?.category
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
        let spent = data.current.reduce(Int64(0)) { $0 + $1.amount }
        let unsorted = data.current.filter { Classification.isPending($0.assignment.category) }
        let unsortedAmount = unsorted.reduce(Int64(0)) { $0 + $1.amount }
        var snapshot = OverviewReviewSnapshot(spent: spent,
                                      previousSpent: data.previous.reduce(0) { $0 + $1.amount },
                                      saved: saving(in: ledger, during: data.window.interval, closedCycles: savingsCycles, now: now),
                                      previousSaved: saving(in: ledger, during: data.window.comparison, closedCycles: savingsCycles, now: now),
                                      window: data.window,
                                      anomaly: overspend.map { slice($0.category, amount: $0.amount, previous: $0.baseline, anomaly: true) },
                                      slices: slices.sorted { $0.amount == $1.amount ? $0.category < $1.category : $0.amount > $1.amount })
        snapshot.anomalyBaselineCycles = overspend?.cycles ?? 0
        if spent > 0, Decimal(unsortedAmount) * 10 > Decimal(spent) * 3 {
            snapshot.unsortedCount = unsorted.filter { $0.entry.nature == .expense }.count
            snapshot.unsortedAmount = unsortedAmount
            snapshot.unsortedEntryIDs = unsorted.filter { $0.entry.nature == .expense }.map(\.entry.id)
        }
        return snapshot
    }

    public static func categoryDrill(in ledger: Ledger, title: String, categories: [String], isOther: Bool,
                                     selection: OverviewPeriodSelection, now: Date) -> OverviewCategoryDrill {
        let data = spending(in: ledger, selection: selection, now: now)
        let members = Set(categories)
        let current = data.current.filter { members.contains($0.assignment.category) }
        let previous = data.previous.filter { members.contains($0.assignment.category) }
        let anomaly = !isOther && categories.count == 1 && categories.first == self.anomaly(
            in: ledger, selection: selection, window: data.window, current: data.current, now: now)?.category
        func group(_ row: Spending) -> String {
            row.amount < 0 ? refundGroup : isOther ? row.assignment.category : row.assignment.subcategory ?? "未分类"
        }
        let earlier = totals(previous, by: group)
        let slices = drillSlices(totals(current, by: group), anomaly: anomaly) { earlier[$0, default: 0] }
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

    struct Spending {
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
            ? Finance.spendableBreakdown(ledger, now: now).savingCovered : 0
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

    /// The same span in up to 3 earlier periods, most recent first.
    static func baselineWindows(selection: OverviewPeriodSelection, window: OverviewPeriodWindow,
                                in ledger: Ledger, now: Date) -> [DateInterval] {
        let span = window.interval.duration
        // Calendar components, not seconds, so a DST change does not move the cutoff.
        let elapsed = Dates.calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond],
                                                    from: window.interval.start, to: window.interval.end)
        func clip(_ cycle: DateInterval) -> DateInterval {
            let end = Dates.calendar.date(byAdding: elapsed, to: cycle.start) ?? cycle.start.addingTimeInterval(span)
            return DateInterval(start: cycle.start, end: max(cycle.start, min(cycle.end, end)))
        }
        switch selection {
        case .current:
            return Finance.pastCycles(ledger, now: now, limit: 3).map(clip)
        case .previous:
            return Finance.pastCycles(ledger, now: now, limit: 4).dropFirst().map(clip)
        case .custom:
            let days = Dates.calendar.dateComponents([.day], from: window.interval.start, to: window.interval.end).day ?? 0
            return (1...3).map { k in
                let start = Dates.addDays(-days * k, to: window.interval.start)
                return DateInterval(start: start, end: Dates.addDays(days, to: start))
            }
        }
    }

    /// 多花 compares everyday spending with the average of the same span in up to
    /// 3 earlier periods. Fixed bills, rent, pending 报销/AA and the catch-all
    /// category never count. Needs 2 earlier periods with spending, a nonzero
    /// baseline, and an excess over 30% that is at least ¥100. The largest
    /// excess wins.
    /// Everyday spending, the only kind 多花 compares: no plan, rent, pending 报销/AA, 待整理 or 其他支出.
    static func isEveryday(_ row: Spending, lookup: [UUID: Entry]) -> Bool {
        let source = row.entry.relatedEntryID.flatMap { lookup[$0] } ?? row.entry
        return source.planID == nil && source.rentID == nil && source.pendingRecovery == nil
            && row.entry.planID == nil && row.entry.rentID == nil
            && !Classification.isPending(row.assignment.category)
            && row.assignment.category != "其他支出"
    }

    /// The page behind the 多花 card: the same everyday bills, amount and baseline as the card.
    /// Nil when the category is no longer the period's 多花.
    public static func anomalyDrill(in ledger: Ledger, category: String, selection: OverviewPeriodSelection, now: Date) -> OverviewCategoryDrill? {
        let data = spending(in: ledger, selection: selection, now: now)
        guard let found = anomaly(in: ledger, selection: selection, window: data.window, current: data.current, now: now),
              found.category == category else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        let rows = data.current.filter { $0.assignment.category == category && isEveryday($0, lookup: lookup) }
        func group(_ row: Spending) -> String { row.amount < 0 ? refundGroup : row.assignment.subcategory ?? "未分类" }
        let slices = drillSlices(totals(rows, by: group), anomaly: true) { _ in 0 }
        let budget = HomeBudgets(in: ledger, now: now).ordered.first { $0.categories.contains(category) }
        var drill = OverviewCategoryDrill(title: category, amount: found.amount, previous: found.baseline, isAnomaly: true,
                                          slices: slices, entries: sortedEntries(rows.map(\.entry)),
                                          entryGroups: Dictionary(uniqueKeysWithValues: rows.map { ($0.entry.id, group($0)) }),
                                          budget: budget, window: data.window)
        drill.baselineCycles = found.cycles
        return drill
    }

    static func anomaly(in ledger: Ledger, selection: OverviewPeriodSelection, window: OverviewPeriodWindow,
                        current: [Spending], now: Date) -> (category: String, amount: Int64, baseline: Int64, cycles: Int)? {
        let lookup = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        func everyday(_ row: Spending) -> Bool { isEveryday(row, lookup: lookup) }
        let windows = baselineWindows(selection: selection, window: window, in: ledger, now: now)
        var history: [[String: Int64]] = Array(repeating: [:], count: windows.count)
        var active = Array(repeating: false, count: windows.count)
        for entry in ledger.entries where entry.date <= now {
            guard let index = windows.firstIndex(where: { contains($0, entry.date) }),
                  let amount = Finance.periodSpending(for: entry, in: ledger, entriesByID: lookup) else { continue }
            let row = Spending(entry: entry, amount: amount, assignment: ledger.normalizedCategory(for: entry, entriesByID: lookup))
            // Only everyday spending makes a period count as history, so an
            // excluded bill landing inside a window cannot change the average.
            if everyday(row) { active[index] = true; history[index][row.assignment.category, default: 0] += amount }
        }
        let used = history.indices.filter { active[$0] }.map { history[$0] }
        guard used.count >= 2 else { return nil }
        let currentTotals = totals(current.filter(everyday)) { $0.assignment.category }
        var best: (category: String, amount: Int64, average: Decimal, excess: Decimal)?
        for (category, amount) in currentTotals {
            // Compare against the exact average (Decimal), round only for display.
            let sum = used.reduce(Decimal(0)) { $0 + Decimal($1[category, default: 0]) }
            let average = sum / Decimal(used.count), excess = Decimal(amount) - average
            guard average > 0, excess >= 10_000, excess * 10 > average * 3 else { continue }
            if best.map({ excess > $0.excess || (excess == $0.excess && category < $0.category) }) ?? true {
                best = (category, amount, average, excess)
            }
        }
        return best.map { value in
            var exact = value.average, rounded = Decimal()
            NSDecimalRound(&rounded, &exact, 0, .plain)
            return (value.category, value.amount, NSDecimalNumber(decimal: rounded).int64Value, used.count)
        }
    }

    private static func totals(_ entries: [Spending], by key: (Spending) -> String) -> [String: Int64] {
        entries.reduce(into: [:]) { $0[key($1), default: 0] += $1.amount }
    }

    /// A drill's own row for money that came back, so the rows add up to the page's amount. The key cannot
    /// be a category or subcategory name (a person may name one 退款); the row shows `refundTitle`.
    public static let refundGroup = "\u{1}refunds"
    public static let refundTitle = "退款"

    /// Spending groups largest first, then the refunds row, negative, last.
    private static func drillSlices(_ values: [String: Int64], anomaly: Bool, previous: (String) -> Int64) -> [OverviewCategorySlice] {
        var slices = orderedTotals(values.filter { $0.key != refundGroup }).enumerated().map { index, pair in
            slice(pair.key, amount: pair.value, previous: previous(pair.key), anomaly: anomaly && index == 0)
        }
        if let refunds = values[refundGroup], refunds < 0 {
            slices.append(slice(refundGroup, amount: refunds, previous: 0, anomaly: false))
        }
        return slices
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
