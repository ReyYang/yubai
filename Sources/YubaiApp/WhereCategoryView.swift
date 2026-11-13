import SwiftUI
import YubaiCore

/// 同一类花销：各周期到同一天、最常去的、筛好的明细。
struct WhereCategoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let category: String
    let interval: DateInterval
    @State private var detail: CategoryDetail?
    private var hide: Bool { store.preferences.hideAmounts }
    private var queryKey: String { "\(store.ledgerRevision)-\(store.formula.cycleStart)-\(category)-\(interval.start)-\(interval.end)" }

    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            if let detail {
                summary(detail)
                comparison(detail.cycles)
                places(detail.frequentPlaces)
                recordsButton(detail)
            } else { ProgressView() }
        }.navigationTitle(Classification.displayCategory(category)).yubaiNavigation()
            .amountPrivacy(hide).accessibilityIdentifier("whereCategoryPage")
            .task(id: queryKey) { await refresh() }
    }

    private func summary(_ detail: CategoryDetail) -> some View {
        let amount = detail.cycles.first?.amount ?? 0
        let previous = detail.cycles.dropFirst().first?.amount
        return VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("这个周期").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    AmountLabel(cents: amount, hide: hide, role: .input).fixedSize(horizontal: false, vertical: true)
                    if let previous { comparisonText(amount - previous) }
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    AmountLabel(cents: amount, hide: hide, role: .input)
                    if let previous { comparisonText(amount - previous) }
                }
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("whereCategorySummary")
    }
    @ViewBuilder private func comparisonText(_ delta: Int64) -> some View {
        let label = "比上个周期同一天" + (delta > 0 ? "多" : "少")
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(label).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: abs(delta), hide: hide, role: .account, ink: delta > 0 ? YubaiColor.amberInk : YubaiColor.label)
            }
        } else {
            Text(label + " " + amount2(abs(delta), hide: hide)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
        }
    }

    private func comparison(_ cycles: [CategoryCycleSpending]) -> some View {
        let rows = Array(cycles.reversed())
        let maximum = max(1, rows.map(\.amount).max() ?? 0)
        return Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Text("每个周期到同一天").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        ForEach(rows) { row in accessibleCycle(row, maximum: maximum, current: row.id == cycles.first?.id) }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: YubaiSpace.space8) {
                            ForEach(rows) { row in cycleBar(row, maximum: maximum, current: row.id == cycles.first?.id) }
                        }
                    }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("whereCategoryCycles")
    }
    private func cycleBar(_ row: CategoryCycleSpending, maximum: Int64, current: Bool) -> some View {
        VStack(spacing: YubaiSpace.space4) {
            Text(amount2(row.amount, hide: hide)).yubaiFont(YubaiFont.chartValue).fixedSize()
            RoundedRectangle(cornerRadius: YubaiRadius.bar)
                .fill(current ? YubaiColor.brand : YubaiColor.series3)
                .frame(height: max(YubaiSpace.space2, CGFloat(max(0, row.amount)) / CGFloat(maximum) * YubaiSize.rowDouble))
            Text(monthTitle(row)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.frame(minWidth: YubaiSize.tapMin + YubaiSpace.space24).accessibilityElement(children: .ignore)
            .accessibilityLabel(cycleLabel(row)).accessibilityIdentifier("whereCategoryCycle_" + Dates.text(row.cycleStart))
    }
    private func accessibleCycle(_ row: CategoryCycleSpending, maximum: Int64, current: Bool) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(monthTitle(row)).yubaiFont(YubaiFont.row)
            AmountLabel(cents: row.amount, hide: hide, role: .summary)
            ProgressLine(value: Double(max(0, row.amount)) / Double(maximum), tint: current ? YubaiColor.brand : YubaiColor.series3)
        }.accessibilityElement(children: .ignore).accessibilityLabel(cycleLabel(row))
            .accessibilityIdentifier("whereCategoryCycle_" + Dates.text(row.cycleStart))
    }
    private func monthTitle(_ row: CategoryCycleSpending) -> String { "\(Dates.calendar.component(.month, from: row.cycleStart))月" }
    private func cycleLabel(_ row: CategoryCycleSpending) -> String {
        NowFormat.range(row.cycleStart, row.through) + "，" + amount2(row.amount, hide: hide) + "，\(row.count) 笔"
    }

    @ViewBuilder private func places(_ rows: [CategoryPlace]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                Text("最常去的").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    .padding(.horizontal, YubaiSpace.space4)
                CardRows(Array(rows.prefix(3))) { row in placeRow(row) }
            }.accessibilityIdentifier("whereCategoryPlaces")
        }
    }
    private func placeRow(_ row: CategoryPlace) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) {
                placeTitle(row)
                Spacer(minLength: YubaiSpace.space8)
                AmountLabel(cents: row.amount, hide: hide, sign: row.amount >= 0 ? .outflow : .inflow).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                placeTitle(row)
                AmountLabel(cents: row.amount, hide: hide, sign: row.amount >= 0 ? .outflow : .inflow)
            }
        }.frame(minHeight: YubaiSize.rowSingle).accessibilityElement(children: .combine)
    }
    private func placeTitle(_ row: CategoryPlace) -> some View {
        (Text(row.title) + Text(" · \(row.count) 次").foregroundColor(YubaiColor.labelSecondary)).yubaiFont(YubaiFont.row).lineLimit(1).truncationMode(.tail)
    }
    private func recordsButton(_ detail: CategoryDetail) -> some View {
        Button {
            guard let cycle = detail.cycles.first else { return }
            store.resetRootNavigation()
            store.ledgerPreset = LedgerPreset(mode: .detail, interval: DateInterval(start: cycle.cycleStart, end: Dates.addDays(1, to: cycle.through)), category: category)
            store.destination = .ledger
        } label: {
            HStack(spacing: YubaiSpace.space4) {
                Text("看这 \(detail.entries.count) 笔")
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).accessibilityHidden(true)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("whereCategoryEntries")
    }
    @MainActor private func refresh() async {
        let ledger = store.current; let category = category
        let at = min(Date(), interval.end.addingTimeInterval(-0.001))
        let value = await Task.detached(priority: .userInitiated) { Finance.categoryDetail(ledger, category: category, now: at) }.value
        guard !Task.isCancelled else { return }
        detail = value
    }
}
