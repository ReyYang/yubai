import SwiftUI
import YubaiCore

struct SavedView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var results: [ButlerSavingResult] = []
    private var hide: Bool { store.preferences.hideAmounts }
    private var year: Int { Dates.calendar.component(.year, from: store.financialNow) }
    private var years: [Int] { Set(results.map { Dates.calendar.component(.year, from: $0.record.date) }).sorted(by: >) }
    var body: some View {
        Page(spacing: YubaiSpace.gapGroup, topPadding: YubaiSpace.space8) {
            VStack(alignment: .leading, spacing: 4) {
                AmountLabel(cents: results.reduce(0) { $0 + $1.amount }, hide: hide, role: .display, currency: true)
                    .accessibilityIdentifier("butlerSavedTotal")
                if results.isEmpty { yearLabel(year) }
            }
            ForEach(years, id: \.self) { year in
                yearLabel(year)
                Card(style: .list) {
                    VStack(spacing: 0) {
                        let rows = results.filter { Dates.calendar.component(.year, from: $0.record.date) == year }
                        ForEach(rows) { result in
                            row(result)
                            if result.id != rows.last?.id { EntryFormDivider() }
                        }
                    }
                }
            }
        }.navigationTitle("余白帮你省下").yubaiNavigation().amountPrivacy(hide).accessibilityIdentifier("butlerSavedPage")
            .task(id: "\(store.ledgerRevision)-\(Dates.text(store.financialNow))") {
                let ledger = store.current, now = store.financialNow
                let value = await Task.detached(priority: .userInitiated) { ButlerSavings.results(ledger, now: now) }.value
                guard !Task.isCancelled else { return }; results = value
            }
    }
    private func yearLabel(_ value: Int) -> some View {
        Text("\(value.formatted(.number.grouping(.never))) 年").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func row(_ result: ButlerSavingResult) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.record.item).yubaiFont(YubaiFont.rowTitle, weight: .medium).lineLimit(1)
                Text(detail(result)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            AmountLabel(cents: result.amount, hide: hide, role: .summary, ink: YubaiColor.brandInk).fixedSize()
        }.padding(.vertical, 8).frame(minHeight: YubaiSize.rowDouble).accessibilityElement(children: .combine)
            .accessibilityIdentifier("butlerSaving_" + result.id)
    }
    private func detail(_ result: ButlerSavingResult) -> String {
        let record = result.record, month = Dates.calendar.component(.month, from: record.date)
        if record.plan != nil {
            let cadence = record.plan?.frequency.label ?? "每月"
            let unit: String
            switch record.cadence { case .yearly: unit = "年"; case .quarterly: unit = "季"; case .weekly: unit = "周"; default: unit = "个月" }
            return "\(month)月停掉 · " + cadence + amount2(record.amount, hide: hide) + "，已 \(result.periods) \(unit)"
        }
        if record.wishID != nil { return "\(month)月 · 等了 \(record.waitedHours ?? 0) 小时，没买" }
        return "\(month)月 · 重复扣的一笔要回来了"
    }
}
