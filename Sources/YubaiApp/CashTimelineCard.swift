import SwiftUI
import Charts
import YubaiCore

struct CashTimelineCard: View {
    @Environment(AppStore.self) private var store
    let timeline: CashTimeline
    @State private var selectedDate: Date?
    private var window: CashTimelineWindow {
        var value = timeline.window()
        value.previous = []; value.floor = nil
        return value
    }
    private var selected: CashTimelinePoint? { selectedDate.flatMap { window.point(on: $0) } }
    var body: some View {
        let visible = window
        let scale = CashTimelineScale(window: visible)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header(visible)
                if !store.preferences.hideAmounts {
                    Chart {
                        ForEach(visible.history) { point in
                            LineMark(x: .value("日期", point.date), y: .value("现金", Double(point.balance) / 100), series: .value("阶段", "实际"))
                                .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: 2.4))
                        }
                        ForEach(visible.forecastLine) { point in
                            LineMark(x: .value("日期", point.date), y: .value("现金", Double(point.balance) / 100), series: .value("阶段", "预测"))
                                .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: 2.4, dash: [4, 4]))
                        }
                        if let today = visible.history.last {
                            PointMark(x: .value("日期", today.date), y: .value("现金", Double(today.balance) / 100))
                                .foregroundStyle(YubaiColor.brand).symbolSize(32)
                        }
                        ForEach(visible.annotations) { event in
                            if let point = visible.point(on: event.date) {
                                PointMark(x: .value("日期", event.date), y: .value("现金", Double(point.balance) / 100))
                                    .symbolSize(0).annotation(position: .top, alignment: .leading) {
                                        Text(event.title + " " + AmountLabel.text(event.amount, currency: false))
                                            .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.brandInk).lineLimit(1)
                                    }
                            }
                        }
                        if let selected {
                            RuleMark(x: .value("日期", selected.date)).foregroundStyle(YubaiColor.separator)
                            PointMark(x: .value("日期", selected.date), y: .value("现金", Double(selected.balance) / 100)).foregroundStyle(YubaiColor.brand)
                        }
                    }.frame(height: 168).padding(.top, 12)
                        .chartLegend(.hidden).chartXScale(domain: visible.start...visible.end).chartYScale(domain: scale.domain)
                        .chartXAxis {
                            AxisMarks(values: Array(Set([visible.start, timeline.today, visible.end])).sorted()) { axis in
                                AxisValueLabel { if let day = axis.as(Date.self) { Text(day == timeline.today ? "今天" : short(day)).foregroundStyle(YubaiColor.labelSecondary) } }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing, values: scale.ticks) { axis in
                                AxisGridLine().foregroundStyle(YubaiColor.separator)
                                AxisValueLabel { if let value = axis.as(Double.self) { Text(value.formatted(.number.notation(.compactName))).foregroundStyle(YubaiColor.labelSecondary) } }
                            }
                        }.chartXSelection(value: $selectedDate)
                        .accessibilityIdentifier("cashTimelineChart").accessibilityLabel("手上的钱")
                        .accessibilityHint("长按后拖动查看一天")
                }
            }
        }.accessibilityIdentifier("cashTimelineCard")
            .onChange(of: timeline.cycles) { _, _ in selectedDate = nil }
            .onChange(of: store.preferences.hideAmounts) { _, _ in selectedDate = nil }
    }
    private func header(_ visible: CashTimelineWindow) -> some View {
        let balance = selected?.balance ?? visible.history.last?.balance ?? store.funds.cash
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("手上的钱").yubaiFont(YubaiFont.heroLabel)
                Spacer(minLength: YubaiSpace.space8)
                readout(balance)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text("手上的钱").yubaiFont(YubaiFont.heroLabel)
                readout(balance)
            }
        }
    }
    private func readout(_ balance: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            if let selected { Text(ManualBookkeeping.dayLabel(selected.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            AmountLabel(cents: balance, hide: store.preferences.hideAmounts, role: .summary, sign: .none).fixedSize()
        }.accessibilityIdentifier("cashTimelineReadout")
    }
    private func short(_ day: Date) -> String { "\(Dates.calendar.component(.month, from: day))/\(Dates.calendar.component(.day, from: day))" }
}
