import SwiftUI
import YubaiCore

struct AllCategoriesView: View {
    @Environment(AppStore.self) private var store
    let interval: DateInterval
    @State private var rows: [CashFlowSlice] = []
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            if rows.isEmpty { EmptyState("square.grid.2x2", "还没有支出", action: "记一笔", onAction: { store.requestCaptureSheet(.addEntry) }) }
            else {
                CardRows(Array(rows.enumerated()).map { CategorySpendingRow(index: $0.offset, value: $0.element) }) { row in
                    TabNavigationLink(.whereCategory(category: row.value.title, interval: interval)) {
                        WhereCategoryView(category: row.value.title, interval: interval)
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.space8) { categoryTitle(row.value); Spacer(minLength: YubaiSpace.space8); AmountLabel(cents: row.value.amount, hide: store.preferences.hideAmounts); Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta) }
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) { categoryTitle(row.value); AmountLabel(cents: row.value.amount, hide: store.preferences.hideAmounts) }
                        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("insightCategory_\(row.index)")
                }
            }
        }.navigationTitle("全部分类").yubaiNavigation().accessibilityIdentifier("allCategoriesPage")
            .task(id: store.ledgerRevision) {
                let ledger = store.current; let interval = interval
                let value = await Task.detached { SavingInsights.categoryShares(ledger, during: interval) }.value
                guard !Task.isCancelled else { return }; rows = value
            }
    }
    private func categoryTitle(_ row: CashFlowSlice) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(Classification.displayCategory(row.title)).yubaiFont(YubaiFont.row).lineLimit(1)
            if !store.preferences.hideAmounts { Text(String(format: "%.0f%%", row.share * 100)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
        }
    }
    private struct CategorySpendingRow: Identifiable { var index: Int; var value: CashFlowSlice; var id: String { value.title } }
}
