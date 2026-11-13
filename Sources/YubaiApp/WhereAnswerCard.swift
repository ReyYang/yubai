import SwiftUI
import YubaiCore

struct WhereAnswerCard: View {
    @Environment(AppStore.self) private var store
    @State private var answer: SpendingAnswer?
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("余白").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                if let answer {
                    Text(hide ? "金额已隐藏" : answer.conclusion).yubaiFont(YubaiFont.lead).accessibilityIdentifier("askAnswer")
                    ForEach(answer.comparisons) { row in
                        if answer.hasPreviousCycle { AnswerComparisonRow(title: row.title, before: row.usual, after: row.amount, hide: hide) }
                        else { EntryFormRow(title: row.title) { AmountLabel(cents: row.amount, hide: hide, role: .small) } }
                        EntryFormDivider()
                    }
                    if let place = answer.frequentPlace {
                        EntryFormRow(title: place.title) {
                            Text("\(place.count) 次 · " + amount2(place.amount, hide: hide)).yubaiFont(YubaiFont.amountSmall)
                        }
                    }
                    ChipFlow {
                        Button("看去向") {
                            store.sheet = nil; store.resetRootNavigation()
                            store.ledgerPreset = LedgerPreset(mode: .whereTo); store.destination = .ledger
                        }.buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityIdentifier("askShowWhere")
                        if let category = answer.comparisons.first?.category {
                            TabNavigationLink(.categoryBudget(category)) { BudgetView(initialCategory: category) } label: { Text("给" + Classification.displayCategory(category) + "定个预算") }
                                .buttonStyle(SecondaryButtonStyle(background: YubaiColor.card, compact: true)).accessibilityIdentifier("askCategoryBudget")
                        }
                    }.padding(.top, 8)
                } else { ProgressView() }
            }
        }.accessibilityIdentifier("whereAnswerCard")
            .task(id: store.ledgerRevision) {
                let ledger = store.current; let now = store.financialNow
                let value = await Task.detached { SavingInsights.spendingAnswer(ledger, now: now) }.value
                guard !Task.isCancelled else { return }; answer = value
            }
    }
}

/// Both answer types use the same wrapping rule for a label and a pair of amounts.
struct AnswerComparisonRow: View {
    let title: String
    let before: Int64
    let after: Int64
    let hide: Bool
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { label; Spacer(minLength: 8); values }
            VStack(alignment: .leading, spacing: 4) { label; values }
        }.frame(minHeight: YubaiSize.rowSingle).accessibilityElement(children: .combine)
    }
    private var label: some View { Text(title).yubaiFont(YubaiFont.row).lineLimit(1) }
    private var values: some View {
        HStack(spacing: 4) {
            AmountLabel(cents: before, hide: hide, role: .small, ink: YubaiColor.labelSecondary)
            Text("→").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: after, hide: hide, role: .small, ink: after < 0 ? YubaiColor.amberInk : YubaiColor.label)
        }
    }
}
