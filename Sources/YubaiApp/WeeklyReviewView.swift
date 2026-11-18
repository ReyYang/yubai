import SwiftUI
import YubaiCore

/// A weekly conclusion and two facts, followed by recent weeks, category breakdown, and subscriptions.
struct WeeklyReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var snapshot: WeeklyReviewSnapshot?
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            if let snapshot {
                summaryCard(snapshot)
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.space12)) : AnyLayout(HStackLayout(alignment: .top, spacing: YubaiSpace.space12))
                layout {
                    fact("花得最多" + (snapshot.review.largestCategory.map { " · " + Classification.displayCategory($0) } ?? ""), amount: snapshot.review.largestAmount)
                    fact("没买，省下", amount: snapshot.review.droppedWishes)
                }.accessibilityIdentifier("weeklyNumbers")
                recentWeeksCard(snapshot.recentWeeks)
                categorySection(snapshot)
            }
            if !store.subscriptionCandidates.isEmpty {
                LetterSubscriptionCard(candidates: store.subscriptionCandidates, letterDate: store.financialNow)
            }
        }.amountPrivacy(hide).navigationTitle("每周来信").yubaiNavigation().accessibilityIdentifier("weeklyReviewPage")
            .task(id: store.ledgerRevision) {
                let ledger = store.current; let now = store.financialNow
                let value = await Task.detached { WeeklyReviewSnapshot.make(ledger: ledger, now: now) }.value
                guard !Task.isCancelled else { return }; snapshot = value
            }
    }
    private func summaryCard(_ snapshot: WeeklyReviewSnapshot) -> some View {
        let review = snapshot.review
        return Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(NowFormat.range(review.interval.start, Dates.addDays(-1, to: review.interval.end)))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Text(conclusion(review)).yubaiFont(YubaiFont.lead).accessibilityIdentifier("letterBody")
                if snapshot.lastWeekCount > 0 || snapshot.lastWeekIncome > 0 {
                    EntryFormDivider()
                    HStack(spacing: YubaiSpace.space12) {
                        if snapshot.lastWeekCount > 0 {
                            Text("\(snapshot.lastWeekCount) 笔支出").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        }
                        if snapshot.lastWeekIncome > 0 {
                            Text("收入 " + amount2(snapshot.lastWeekIncome, hide: hide)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func conclusion(_ value: WeeklyReview) -> String {
        let delta = value.spending - value.previousSpending
        return "这一周花了 " + amount2(value.spending, hide: hide) + "，比上周" + (delta > 0 ? "多 " : "少 ") + amount2(abs(delta), hide: hide) + "。"
    }
    private func fact(_ title: String, amount: Int64) -> some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: amount, hide: hide, role: .summary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func recentWeeksCard(_ weeks: [WeeklyReviewSnapshot.WeekBar]) -> some View {
        let maximum = max(Int64(1), weeks.map(\.amount).max() ?? 0)
        return Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Text("近四周").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        ForEach(weeks) { week in
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                HStack {
                                    Text(week.label).yubaiFont(YubaiFont.row)
                                    Spacer()
                                    AmountLabel(cents: week.amount, hide: hide, role: .small)
                                }
                                ProportionalBar(fraction: Double(max(0, week.amount)) / Double(maximum))
                            }.accessibilityElement(children: .ignore)
                                .accessibilityLabel(week.accessibilityRange + "，" + amount2(week.amount, hide: hide))
                        }
                    }
                } else {
                    HStack(alignment: .bottom, spacing: YubaiSpace.space8) {
                        ForEach(weeks) { week in
                            VStack(spacing: YubaiSpace.space4) {
                                Text(amount2(week.amount, hide: hide)).yubaiFont(YubaiFont.chartValue).lineLimit(1).minimumScaleFactor(0.8)
                                RoundedRectangle(cornerRadius: YubaiRadius.bar)
                                    .fill(weekBarColor(week.role))
                                    .frame(height: max(YubaiSpace.space2, CGFloat(max(0, week.amount)) / CGFloat(maximum) * YubaiSize.rowDouble))
                                Text(week.label).yubaiFont(YubaiFont.caption)
                                    .foregroundStyle(week.role == .lastWeek ? YubaiColor.brandInk : YubaiColor.labelSecondary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                                .accessibilityLabel(week.accessibilityRange + "，" + amount2(week.amount, hide: hide))
                        }
                    }
                }
            }
        }.accessibilityIdentifier("weeklyRecentWeeks")
    }
    private func weekBarColor(_ role: WeeklyReviewSnapshot.WeekBar.Role) -> Color {
        switch role {
        case .lastWeek: YubaiColor.brand
        case .currentWeek: YubaiColor.seriesSoft
        case .earlier: YubaiColor.series3
        }
    }
    @ViewBuilder private func categorySection(_ snapshot: WeeklyReviewSnapshot) -> some View {
        let rows = snapshot.lastWeekCategories.isEmpty ? snapshot.currentWeekCategories : snapshot.lastWeekCategories
        if !rows.isEmpty {
            let title = snapshot.lastWeekCategories.isEmpty ? "本周去向" : "去向"
            let shown = Array(rows.prefix(6))
            let maximum = max(Int64(1), shown.map(\.amount).max() ?? 0)
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                SectionHeading(title: title).padding(.horizontal, YubaiSpace.space4)
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(shown) { row in
                            VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                                    Text(Classification.displayCategory(row.category)).yubaiFont(YubaiFont.row)
                                    Text("\(row.count) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                    Spacer(minLength: YubaiSpace.space8)
                                    AmountLabel(cents: row.amount, hide: hide, role: .small)
                                }
                                ProportionalBar(fraction: Double(max(0, row.amount)) / Double(maximum))
                            }.padding(.vertical, YubaiSpace.space12)
                            if row.id != shown.last?.id { EntryFormDivider() }
                        }
                    }
                }
            }.accessibilityIdentifier("weeklyCategories")
        }
    }
}

private struct WeeklyReviewSnapshot: Sendable {
    struct WeekBar: Identifiable, Sendable {
        enum Role: Sendable { case earlier, lastWeek, currentWeek }
        let id: Date
        let label: String
        let accessibilityRange: String
        let amount: Int64
        let role: Role
    }
    let review: WeeklyReview
    let lastWeekIncome: Int64
    let lastWeekCount: Int
    let lastWeekCategories: [Breakdown]
    let currentWeekCategories: [Breakdown]
    let recentWeeks: [WeekBar]

    nonisolated static func make(ledger: Ledger, now: Date) -> WeeklyReviewSnapshot {
        let review = SavingInsights.weekly(ledger, now: now)
        let lastFlow = Finance.cashFlow(ledger, during: review.interval)
        let lastWeekCount = lastFlow.spendingByCategory.reduce(0) { $0 + $1.count }
        let currentStart = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? Dates.day(now)
        let currentInterval = DateInterval(start: currentStart, end: max(currentStart, now.addingTimeInterval(0.001)))
        let currentFlow = Finance.cashFlow(ledger, during: currentInterval)
        let weekMinus2 = DateInterval(start: Dates.addDays(-14, to: review.interval.start), end: Dates.addDays(-7, to: review.interval.start))
        let weekMinus1 = DateInterval(start: Dates.addDays(-7, to: review.interval.start), end: review.interval.start)
        let weeks: [WeekBar] = [
            WeekBar(id: weekMinus2.start, label: Dates.monthDay(weekMinus2.start),
                    accessibilityRange: Dates.monthDay(weekMinus2.start) + " – " + Dates.monthDay(Dates.addDays(-1, to: weekMinus2.end)),
                    amount: Finance.cashFlow(ledger, during: weekMinus2).spending, role: .earlier),
            WeekBar(id: weekMinus1.start, label: Dates.monthDay(weekMinus1.start),
                    accessibilityRange: Dates.monthDay(weekMinus1.start) + " – " + Dates.monthDay(Dates.addDays(-1, to: weekMinus1.end)),
                    amount: review.previousSpending, role: .earlier),
            WeekBar(id: review.interval.start, label: "上周",
                    accessibilityRange: Dates.monthDay(review.interval.start) + " – " + Dates.monthDay(Dates.addDays(-1, to: review.interval.end)),
                    amount: review.spending, role: .lastWeek),
            WeekBar(id: currentInterval.start, label: "本周",
                    accessibilityRange: Dates.monthDay(currentInterval.start) + " 至今",
                    amount: currentFlow.spending, role: .currentWeek)
        ]
        return WeeklyReviewSnapshot(
            review: review,
            lastWeekIncome: lastFlow.income,
            lastWeekCount: lastWeekCount,
            lastWeekCategories: lastFlow.spendingByCategory.filter { $0.amount > 0 },
            currentWeekCategories: currentFlow.spendingByCategory.filter { $0.amount > 0 },
            recentWeeks: weeks
        )
    }
}
