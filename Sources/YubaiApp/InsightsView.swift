import SwiftUI
import Charts
import YubaiCore

/// Cloud task helpers. Amount / account / nature are never model-writable.
enum CloudIntelligence {
    @MainActor static func availabilityText(for preferences: Preferences) -> String { IntelligenceRuntime.availabilityText(for: preferences) }
    @MainActor static func canAssist(preferences: Preferences) -> Bool {
        IntelligenceRuntime.backend(for: preferences) != nil
    }

}

struct InsightsView: View {
    @Environment(AppStore.self) private var store
    @State private var days = 30
    @State private var insightPolish = ""
    @State private var insightBusy = false
    @State private var categoryChartAppeared = false; @State private var dailyChartAppeared = false
    private var from: Date { Dates.addDays(-days + 1, to: Dates.day(Date())) }
    private var through: Date { Dates.addDays(1, to: Dates.day(Date())) }
    var body: some View {
        let review = store.review(from: from, through: through)
        Page(hasTabBar: true) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) { Text("看懂花费，也看见自己。").yubaiFont(YubaiFont.lead); Text("从真实记录中找线索，不为每一笔小快乐打分。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            Picker("回顾范围", selection: $days) { Text("近 30 天").tag(30); Text("近 90 天").tag(90); Text("近一年").tag(365) }.pickerStyle(.segmented)
            if review.count == 0 { Card { EmptyState("chart.bar", "先有生活的记录，再有洞察", "导入一份账单或记下一笔收支，余白会把线索放在这里。", action: "导入账单") { store.sheet = .imports } } }
            else {
                stats(review)
                categories(review)
                DailySpendingChart(ledger: store.current, from: from, through: through, days: days, hideAmounts: store.current.preferences.hideAmounts, appeared: $dailyChartAppeared)
                observations(review)
            }
        }.navigationTitle("洞察").yubaiNavigation().toolbar { Button { store.sheet = .ask("") } label: { Label("问余白", systemImage: "sparkle") } }
            .onChange(of: store.current.profile) { _, _ in insightPolish = "" }
            .onChange(of: store.current.goals) { _, _ in insightPolish = "" }
            .onChange(of: store.current.id) { _, _ in insightPolish = "" }
    }
    private func stats(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space20) {
            Text("这段时间，我的消费").yubaiFont(YubaiFont.heroLabel)
            AmountLabel(cents: review.spending, hide: store.current.preferences.hideAmounts, role: .display, sign: .outflow)
            HStack {
                VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                    Text("真实收入").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    AmountLabel(cents: review.income, hide: store.current.preferences.hideAmounts, sign: .inflow)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: YubaiSpace.space6) {
                    Text("已减去退款").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    AmountLabel(cents: review.refunds, hide: store.current.preferences.hideAmounts)
                }
            }
            Divider()
            Text("\(review.count) 笔记录 · \(Dates.text(from)) — \(Dates.text(Date()))").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            InlineNote(text: "按实际发生日期汇总。排除内部转账、借还本金、投资申赎和分摊收款；房租只计本人承担的比例。")
        }
    }
    private func categories(_ review: Review) -> some View {
        Card { VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: "花在哪")
            ChartGrow(appeared: $categoryChartAppeared) { progress in if store.current.preferences.hideAmounts { Text("金额已隐藏，分类图也已收起。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            else if review.byCategory.contains(where: { $0.amount > 0 }) { BarList(items: review.byCategory, progress: progress) }
            else { Text("这一段还没有消费支出。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) } }
        } }
    }
    private func observations(_ review: Review) -> some View {
        Card { VStack(alignment: .leading, spacing: YubaiSpace.space16) {
            SectionHeading(title: "值得看一眼的线索")
            if let top = review.byCategory.first, top.amount > 0 { Label("\(top.category)是这段时间最大的消费去向，共 \(Money.text(top.amount))。它是否符合你最近的重心？", systemImage: "circle.dotted").yubaiFont(YubaiFont.callout) }
            if review.previousSpending > 0 { let difference = review.spending - review.previousSpending; Label("比前一段同样长的时间\(difference >= 0 ? "多" : "少") \(Money.text(abs(difference)))。先确认两个区间的账单都完整，再判断变化。", systemImage: "arrow.left.arrow.right").yubaiFont(YubaiFont.callout) }
            let subscriptions = store.current.plans.filter { $0.active && !$0.inflow && $0.frequency != .once && $0.nature != .repayment }
            if !subscriptions.isEmpty { Label("你有 \(subscriptions.count) 项持续付款约定。可以在安排中核对仍然需要的服务。", systemImage: "repeat").yubaiFont(YubaiFont.callout) }
            if !insightPolish.isEmpty { Text(insightPolish).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            Text("这些线索来自本地计算，不是 AI 推断，也不代表必须削减消费。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            if CloudIntelligence.canAssist(preferences: store.current.preferences) {
                Button(insightBusy ? "智能润色中…" : "用智能说说") { polishInsights(review) }
                    .disabled(insightBusy)
                    .yubaiFont(YubaiFont.caption)
            }
        } }
    }
    private func polishInsights(_ review: Review) {
        insightBusy = true
        let facts = insightFactPack(review)
        let ledger = store.current
        Task {
            defer { insightBusy = false }
            do {
                guard let backend = IntelligenceRuntime.backend(for: ledger) else { return }
                let profile = try ReadOnlyTool.getProfile.run(.object([:]), ToolContext(ledger: ledger))
                let text = try await backend.narrateInsights(facts: facts, profile: profile)
                guard store.current == ledger else { return }
                if let ok = InsightNarrationGuard.accept(text, protecting: facts.protectedAmountTexts) {
                    // Keep template facts on screen; show only the model polish delta when possible.
                    insightPolish = ok
                }
            } catch {
                insightPolish = ""
            }
        }
    }
    private func insightFactPack(_ review: Review) -> InsightFactPack {
        var lines: [String] = []
        var amounts: [String] = []
        if let top = review.byCategory.first, top.amount > 0 {
            let amount = Money.text(top.amount)
            amounts.append(amount)
            lines.append("\(top.category)是这段时间最大的消费去向，共 \(amount)。")
        }
        if review.previousSpending > 0 {
            let difference = review.spending - review.previousSpending
            let amount = Money.text(abs(difference))
            amounts.append(amount)
            lines.append("比前一段同样长的时间\(difference >= 0 ? "多" : "少") \(amount)。")
        }
        let subscriptions = store.current.plans.filter { $0.active && !$0.inflow && $0.frequency != .once && $0.nature != .repayment }
        if !subscriptions.isEmpty {
            lines.append("你有 \(subscriptions.count) 项持续付款约定。")
        }
        return InsightFactPack(factLines: lines, protectedAmountTexts: amounts)
    }
}

private struct DailySpendingChart: View {
    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let amount: Int64
        let value: Double
    }
    @Binding private var appeared: Bool
    private let days: Int
    private let hideAmounts: Bool
    private let points: [Point]
    private let peak: Date?
    private let domain: ClosedRange<Double>
    private let accessibilityText: String

    init(ledger: Ledger, from: Date, through: Date, days: Int, hideAmounts: Bool, appeared: Binding<Bool>) {
        self.days = days
        self.hideAmounts = hideAmounts
        self._appeared = appeared
        let entries = ledger.activeEntries.filter {
            $0.date >= from && $0.date < through && ($0.nature == .expense || $0.nature == .refund)
        }
        let grouped = Dictionary(grouping: entries, by: { Dates.day($0.date) })
        let points: [Point] = grouped.map { date, entries in
            let amount = entries.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ledger) }
            return Point(date: date, amount: amount, value: Double(amount) / 100)
        }.sorted { $0.date < $1.date }
        self.points = points
        self.peak = points.max { $0.amount < $1.amount }?.date
        let values = points.map(\.value)
        let lower: Double = min(0, values.min() ?? 0)
        let upper: Double = max(1, values.max() ?? 0)
        self.domain = lower...upper
        let descriptions: [String] = points.map { Dates.text($0.date) + "，" + Money.text($0.amount) }
        self.accessibilityText = "每天花了多少。" + descriptions.joined(separator: "；")
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                SectionHeading(title: "每天花了多少", subtitle: "金额单位：元，退款按到账日冲减")
                ChartGrow(appeared: $appeared) { progress in
                    if hideAmounts {
                        Text("金额已隐藏，花费图也已收起。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    } else {
                        GeometryReader { geometry in
                            let dayWidth: CGFloat = geometry.size.width / CGFloat(max(1, days))
                            let barWidth: CGFloat = min(YubaiSpace.space16, dayWidth * 0.7)
                            chart(progress: progress, barWidth: barWidth)
                        }.frame(height: 180)
                    }
                }
            }
        }
    }

    private func chart(progress: Double, barWidth: CGFloat) -> some View {
        Chart {
            RuleMark(y: .value("基线", 0)).foregroundStyle(YubaiColor.neutralSoft).lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(points) { point in
                BarMark(x: .value("日期", point.date, unit: .day), y: .value("消费", point.value * progress), width: .fixed(barWidth))
                    .foregroundStyle(point.date == peak ? YubaiColor.brand : YubaiColor.seriesSoft)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.bar, topTrailingRadius: YubaiRadius.bar))
                    .annotation(position: .top) { if point.date == peak { AmountLabel(cents: point.amount, role: .chart) } }
            }
        }.chartYScale(domain: domain).chartLegend(.hidden).chartYAxis(.hidden)
            .chartPlotStyle { $0.padding(.top, YubaiSpace.space20) }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                        .foregroundStyle(YubaiColor.labelSecondary).font(.system(size: YubaiFont.chartLabel.size))
                }
            }
            .frame(height: 180).accessibilityLabel(accessibilityText)
    }
}

private struct BarList: View {
    struct Row: Identifiable {
        var id: String { title }; let title: String; let amount: Int64; let count: Int
    }
    @Environment(\.dynamicTypeSize) private var textSize
    let items: [Breakdown]
    let progress: Double
    private var rows: [Row] {
        let sorted = items.sorted { $0.amount > $1.amount }
        if sorted.count <= 6 { return sorted.map { Row(title: $0.category, amount: $0.amount, count: $0.count) } }
        let leading = Array(sorted.filter { $0.category != "其他" }.prefix(5))
        let tail = sorted.filter { item in !leading.contains { $0.id == item.id } }
        return leading.map { Row(title: $0.category, amount: $0.amount, count: $0.count) } + [Row(title: "其他", amount: tail.reduce(0) { $0 + $1.amount }, count: tail.reduce(0) { $0 + $1.count })]
    }
    var body: some View {
        let rows = self.rows
        let maxAmount: Double = Double(max(1, rows.map(\.amount).max() ?? 1))
        VStack(spacing: YubaiSpace.space12) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let ratio: Double = max(0, Double(row.amount)) / maxAmount
                    let animatedRatio: Double = ratio * progress
                    let accessibilityText = "\(row.title)，\(row.count) 笔，\(Money.text(row.amount))"
                    let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space10))
                    layout {
                        VStack(alignment: .leading, spacing: YubaiSpace.space2) { Text(row.title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted); Text("\(row.count) 笔").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }.frame(minWidth: YubaiSize.iconButton, alignment: .leading)
                        GeometryReader { geometry in
                            UnevenRoundedRectangle(bottomTrailingRadius: YubaiRadius.bar, topTrailingRadius: YubaiRadius.bar)
                                .fill(index == 0 ? YubaiColor.brand : YubaiColor.seriesSoft)
                                .frame(width: geometry.size.width * CGFloat(animatedRatio))
                        }.frame(height: YubaiSpace.space12)
                        AmountLabel(cents: row.amount, role: .chart).frame(minWidth: YubaiSize.buttonHeight, alignment: .trailing)
                    }.frame(minHeight: YubaiSize.buttonHeight).accessibilityElement(children: .ignore).accessibilityLabel(accessibilityText)
                }
        }.accessibilityElement(children: .contain).accessibilityLabel("分类消费分布")
    }
}
