import SwiftUI
import YubaiCore

/// A weekly conclusion and two facts, followed by subscriptions the user can act on.
struct WeeklyReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var review: WeeklyReview?
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            if let review {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text(NowFormat.range(review.interval.start, Dates.addDays(-1, to: review.interval.end)))
                        .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    Text(conclusion(review)).yubaiFont(YubaiFont.lead).accessibilityIdentifier("letterBody")
                }
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    fact("花得最多" + (review.largestCategory.map { " · " + Classification.displayCategory($0) } ?? ""), amount: review.largestAmount)
                    fact("没买，省下", amount: review.droppedWishes)
                }.accessibilityIdentifier("weeklyNumbers")
            }
            if !store.subscriptionCandidates.isEmpty {
                LetterSubscriptionCard(candidates: store.subscriptionCandidates, letterDate: store.financialNow)
            }
        }.amountPrivacy(hide).navigationTitle("周回顾").yubaiNavigation().accessibilityIdentifier("weeklyReviewPage")
            .task(id: store.ledgerRevision) {
                let ledger = store.current; let now = store.financialNow
                let value = await Task.detached { SavingInsights.weekly(ledger, now: now) }.value
                guard !Task.isCancelled else { return }; review = value
            }
    }
    private func conclusion(_ value: WeeklyReview) -> String {
        let delta = value.spending - value.previousSpending
        return "这一周花了 " + amount2(value.spending, hide: hide) + "，比上周" + (delta > 0 ? "多 " : "少 ") + amount2(abs(delta), hide: hide) + "。"
    }
    private func fact(_ title: String, amount: Int64) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: amount, hide: hide, role: .summary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
