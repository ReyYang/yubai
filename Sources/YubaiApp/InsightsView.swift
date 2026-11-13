import SwiftUI
import YubaiCore

/// 去向先给能动手省下的几项；完整分类收在末行。
struct WhereView: View {
    @Environment(AppStore.self) private var store
    @Binding var mode: LedgerMode
    @Binding var request: LedgerPreset?
    @State private var insights: SavingOpportunities?
    init(mode: Binding<LedgerMode> = .constant(.whereTo), request: Binding<LedgerPreset?> = .constant(nil)) {
        _mode = mode; _request = request
    }
    private var hide: Bool { store.preferences.hideAmounts }
    private var range: DateInterval {
        DateInterval(start: store.funds.cycleStart, end: store.financialNow.addingTimeInterval(0.001))
    }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space4) {
            Segmented(choices: LedgerMode.allCases.map { ($0, $0 == .detail ? "明细" : "去向") }, selection: $mode,
                          identifier: { "ledgerMode_" + $0.rawValue })
            if let insights {
                if !insights.charges.isEmpty { charges(insights) }
                if insights.previousCycleCount == 0 { insufficient(insights) }
                else {
                    comparisons(insights.comparisons.filter { $0.difference > 0 }, title: "比平时多", more: true)
                    comparisons(insights.comparisons.filter { $0.difference < 0 }, title: "比平时少", more: false)
                    destinations(insights)
                }
            } else { ProgressView() }
        }.amountPrivacy(hide).rootScrollContentMargins(for: .ledger).rootTabScroll(.ledger).accessibilityIdentifier("insightsScroll")
            .task(id: "\(store.ledgerRevision)-\(store.financialNow)") {
                let ledger = store.current; let now = store.financialNow
                let value = await Task.detached(priority: .userInitiated) { SavingInsights.opportunities(ledger, now: now) }.value
                guard !Task.isCancelled else { return }; insights = value
            }
            .onChange(of: request, initial: true) { _, value in
                if value?.mode == .whereTo { request = nil }
            }
    }
    private func heading(_ title: String) -> some View {
        Text(title).yubaiFont(YubaiFont.cardTitle).padding(.horizontal, YubaiSpace.space4)
    }
    private func charges(_ value: SavingOpportunities) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            HStack {
                heading("每月都在扣")
                Spacer(minLength: YubaiSpace.space8)
                AmountLabel(cents: value.chargesTotal, hide: hide, role: .summary, ink: YubaiColor.labelSecondary)
            }
            CardRows(value.charges) { charge in
                TabNavigationLink(.billDetail(charge.id)) { BillDetailView(planID: charge.id) } label: {
                    chargeRow(charge)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("monthlyCharge_" + charge.id.uuidString)
            }
        }.accessibilityIdentifier("whereMonthlyCharges")
    }
    private func chargeRow(_ charge: MonthlyCharge) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { chargeTitle(charge); Spacer(minLength: YubaiSpace.space8); AmountLabel(cents: charge.amount, hide: hide); chevron }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { chargeTitle(charge); HStack { AmountLabel(cents: charge.amount, hide: hide); chevron } }
        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
    }
    private func chargeTitle(_ charge: MonthlyCharge) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(charge.plan.title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).lineLimit(1).truncationMode(.tail)
            Text(charge.lastUsed.map { "上次去是 " + FixedFlowPresentation.monthDay($0) } ?? "在用")
                .yubaiFont(YubaiFont.caption).foregroundStyle(charge.lastUsed == nil ? YubaiColor.labelSecondary : YubaiColor.amberInk)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func comparisons(_ rows: [UsualSpending], title: String, more: Bool) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                heading(title)
                CardRows(Array(rows.prefix(3))) { row in
                    TabNavigationLink(.whereCategory(category: row.category, interval: range)) { WhereCategoryView(category: row.category, interval: range) } label: {
                        comparisonRow(row, more: more)
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("usualSpending_" + row.id)
                }
            }
        }
    }
    private func comparisonRow(_ row: UsualSpending, more: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { comparisonTitle(row); comparisonAmount(row, more: more) }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { comparisonTitle(row); comparisonAmount(row, more: more) }
        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
    }
    private func comparisonTitle(_ row: UsualSpending) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(row.title).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
            Text("平时到这天 " + amount2(row.usual, hide: hide)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func comparisonAmount(_ row: UsualSpending, more: Bool) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Text((more ? "多 " : "少 ") + amount2(abs(row.difference), hide: hide))
                .yubaiFont(YubaiFont.caption, weight: .semibold).lineLimit(1).minimumScaleFactor(0.5)
                .padding(.horizontal, YubaiSpace.space8).padding(.vertical, YubaiSpace.space2)
                .foregroundStyle(more ? YubaiColor.amberInk : YubaiColor.brandInk)
                .background(more ? YubaiColor.amberTint : YubaiColor.brandTint, in: Capsule())
            AmountLabel(cents: row.amount, hide: hide)
        }
    }
    private func insufficient(_ value: SavingOpportunities) -> some View {
        EmptyState("square.grid.2x2", "现在是第 1 个周期 · 已记 \(value.entryCount) 笔", action: "看全部分类", actionIdentifier: "whereAllCategories", onAction: { store.tabRouteRequest = .allCategories(range) })
            .accessibilityIdentifier("whereInsufficientData")
    }
    private func destinations(_ value: SavingOpportunities) -> some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                TabNavigationLink(.allCategories(range)) { AllCategoriesView(interval: range) } label: { destinationRow("全部分类", amount: value.spent) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("whereAllCategories")
                EntryFormDivider()
                TabNavigationLink(.weekly(nil)) { WeeklyReviewView() } label: {
                    destinationRow("上周回顾", amount: SavingInsights.weekly(store.current, now: store.financialNow).spending)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openWeekly")
            }
        }
    }
    private func destinationRow(_ title: String, amount: Int64) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { Text(title).yubaiFont(YubaiFont.row); Spacer(minLength: YubaiSpace.space8); Text("花了 " + amount2(amount, hide: hide)).yubaiFont(YubaiFont.caption); chevron }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text(title).yubaiFont(YubaiFont.row); HStack { Text("花了 " + amount2(amount, hide: hide)).yubaiFont(YubaiFont.caption); chevron } }
        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
    }
    private var chevron: some View { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true) }
}

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
