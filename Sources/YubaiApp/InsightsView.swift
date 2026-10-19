import SwiftUI
import Charts
import YubaiCore

/// Facade over `IntelligenceRuntime` backends. Amount / account / nature are never model-writable.
enum LocalIntelligence {
    @MainActor static func categorize(_ preview: ImportPreview, ledger: Ledger, progress: (Int, Int) -> Void) async -> ImportPreview {
        guard ledger.preferences.localAIEnabled else { return preview }
        let route = IntelligenceRuntime.routing(for: ledger.preferences)
        guard route.kind != .rulesOnly else { return preview }
        let backend = IntelligenceRuntime.backend(for: ledger.preferences)
        guard backend.capabilities.categorize else { return preview }
        let entries = preview.rows.filter { $0.status == .ready }.compactMap(\.entry).filter { [.expense, .income].contains($0.nature) && $0.classificationReason.hasPrefix("未命中规则") }
        guard !entries.isEmpty else { return preview }
        var result = preview; let started = Date()
        let allowed = ledger.categories.map(\.name)
        for start in stride(from: 0, to: entries.count, by: 24) {
            guard !Task.isCancelled else { return result }
            if Date().timeIntervalSince(started) >= 90 { result.warnings.append("智能辅助已完成一部分归类；余下记录保留本地规则结果或其他分类，可直接保存。"); break }
            let batch = Array(entries[start..<min(entries.count, start + 24)])
            progress(start, entries.count)
            let items = batch.enumerated().map { CategorizeItem(index: $0.offset, purpose: String($0.element.title.prefix(80)), direction: $0.element.nature.inflow ? "收入" : "支出") }
            do {
                let suggestions = try await backend.categorize(batch: items, allowedCategories: allowed)
                guard !Task.isCancelled else { return result }
                var mapped: [UUID: String] = [:]
                for item in suggestions where batch.indices.contains(item.index) { mapped[batch[item.index].id] = item.category }
                result.applyCategorySuggestions(mapped, categories: ledger.categories)
            } catch { result.warnings.append("这次智能归类未全部完成，本地规则结果已保留。可以直接保存，稍后按需纠正。"); break }
        }
        return result
    }
    @MainActor static var availabilityText: String { IntelligenceRuntime.availabilityText }
    @MainActor static func availabilityText(for preferences: Preferences) -> String { IntelligenceRuntime.availabilityText(for: preferences) }
    @MainActor static func canAssist(preferences: Preferences) -> Bool {
        guard preferences.localAIEnabled else { return false }
        let route = IntelligenceRuntime.routing(for: preferences)
        switch route.kind {
        case .rulesOnly: return false
        case .localDownloaded:
            return preferences.experimentalMockLocalAI
                || (IntelligenceRuntime.weights.hasReadyWeight && IntelligenceRuntime.localInferenceHealthy(for: preferences))
        case .cloudOptional:
            // UI may offer cloud assist when switch is on; missing key degrades inside CloudOptionalBackend.
            return preferences.cloudAIEnabled
        case .appleFMOptional: return IntelligenceRuntime.appleFMAvailable
        }
    }
    /// Legacy alias: any non-rules assist path may be available.
    @MainActor static var available: Bool {
        IntelligenceRuntime.appleFMAvailable
            || (IntelligenceRuntime.weights.hasReadyWeight && IntelligenceRuntime.localGateHealthy)
            || DeepSeekConfiguration.fromEnvironment() != nil
    }
    @MainActor static func reflect(title: String, purpose: String, values: String, assessment: PurchaseAssessment, preferences: Preferences) async throws -> String {
        guard preferences.localAIEnabled else { throw YubaiError.invalid(availabilityText(for: preferences)) }
        let backend = IntelligenceRuntime.backend(for: preferences)
        guard backend.capabilities.reflectPurchase else { throw YubaiError.invalid(availabilityText(for: preferences)) }
        return try await backend.reflectPurchase(title: title, purpose: purpose, values: values, assessmentTitle: assessment.title)
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
            Button { store.sheet = .advice } label: { Card { HStack(spacing: YubaiSpace.space16) { VStack(alignment: .leading, spacing: YubaiSpace.space6) { Text("有一笔购买正在犹豫？").yubaiFont(YubaiFont.rowTitle); Text("把它放进你的真实资金安排里看一看。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }; Spacer(); Image(systemName: "arrow.up.right") } } }.buttonStyle(PressButtonStyle())
            if !store.current.advice.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.space16) {
                        SectionHeading(title: "之前想过的事")
                        ForEach(Array(store.current.advice.reversed().prefix(8))) { item in
                            VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                                HStack { Text(item.title).yubaiFont(YubaiFont.rowTitle); Spacer(); AmountLabel(cents: item.amount, hide: store.current.preferences.hideAmounts) }
                                Text(item.result).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                                Text("当时的判断 · \(Dates.text(item.createdAt))").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                            }
                        }
                        InlineNote(text: "历史判断反映当时的账本；资金变化后请重新计算。")
                    }
                }
            }
        }.navigationTitle("洞察").yubaiNavigation().toolbar { Button { store.sheet = .advice } label: { Label("购买前咨询", systemImage: "sparkle") } }
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
            if LocalIntelligence.canAssist(preferences: store.current.preferences) {
                Button(insightBusy ? "智能润色中…" : "用智能说说") { polishInsights(review) }
                    .disabled(insightBusy)
                    .yubaiFont(YubaiFont.caption)
            }
        } }
    }
    private func polishInsights(_ review: Review) {
        insightBusy = true
        let facts = insightFactPack(review)
        let preferences = store.current.preferences
        Task {
            defer { insightBusy = false }
            do {
                let backend = IntelligenceRuntime.backend(for: preferences)
                guard backend.capabilities.narrateInsights else { return }
                let text = try await backend.narrateInsights(facts: facts)
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
        return InsightFactPack(factLines: lines, protectedAmountTexts: amounts, valuesHint: store.current.preferences.purchaseValues)
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

struct AdviceView: View {
    @Environment(AppStore.self) private var store
    @State private var title = ""; @State private var amount = ""; @State private var purpose = ""
    @State private var assessment: PurchaseAssessment?; @State private var assessedAmount: Int64 = 0
    @State private var reflection = ""; @State private var aiError: String?; @State private var busy = false; @State private var saved = false
    @State private var task: Task<Void, Never>?
    private enum Field { case title, amount, purpose }
    @FocusState private var focusedField: Field?
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: YubaiSpace.space10) { Text("它值得，占用这份余白吗？").yubaiFont(YubaiFont.lead); Text("先算资金承受能力，再想使用价值。最终决定始终由你做。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
            purchaseFields
            if let assessment { assessmentCard(assessment) }
        }.navigationTitle("购买前想一想").yubaiNavigation().toolbar { CloseButton() }
            .onChange(of: amount) { _, _ in invalidate() }.onChange(of: title) { _, _ in invalidate() }
            .onChange(of: store.current.updatedAt) { _, _ in if !saved { invalidate() } }
            .onDisappear { task?.cancel() }
    }
    private var purchaseFields: some View {
        Card { VStack(spacing: YubaiSpace.space16) {
            TextField("想买什么", text: $title).yubaiFont(YubaiFont.rowTitle).focused($focusedField, equals: .title)
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("¥").yubaiFont(YubaiFont.lead).foregroundStyle(YubaiColor.labelSecondary)
                TextField("金额", text: $amount).numericInput().yubaiFont(YubaiFont.amountInput).focused($focusedField, equals: .amount)
            }
            TextField("它能解决什么问题？（可选）", text: $purpose, axis: .vertical).lineLimit(3...6).yubaiFont(YubaiFont.body).focused($focusedField, equals: .purpose)
            Button("看看对资金的影响", action: assess).buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity)
        } }
    }
    func assessmentCard(_ a: PurchaseAssessment) -> some View {
        let beforePurchase: Double = Double(a.afterPurchase) + Double(assessedAmount)
        let usedRatio: Double = min(1, max(0, 1 - Double(a.afterPurchase) / max(1, beforePurchase)))
        // 买前余量被占用的比例映射到六道水位；放得下时最多五道。
        let bandCount = Int((usedRatio * 6).rounded(.up))
        let filledBands = min(5, bandCount)
        return VStack(spacing: YubaiSpace.space12) {
            Card { VStack(alignment: .leading, spacing: YubaiSpace.space16) {
                Text(a.title).yubaiFont(YubaiFont.lead).foregroundStyle(a.severity == 2 ? YubaiColor.amberInk : YubaiColor.label)
                if a.afterPurchase >= 0 { WaterLevelView(filledBands: filledBands).frame(maxWidth: .infinity) }
                Text(a.explanation).yubaiFont(YubaiFont.body)
                Rectangle().fill(YubaiColor.separator).frame(height: 1)
                Text("购买后的保守余量").yubaiFont(YubaiFont.heroLabel)
                AmountLabel(cents: a.afterPurchase, hide: store.current.preferences.hideAmounts, role: .large)
                DisclosureGroup("查看计算与完整度依据") { VStack(alignment: .leading, spacing: YubaiSpace.space10) { ForEach(a.facts, id: \.self) { Text("· " + $0).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) } }.padding(.top, YubaiSpace.space10) }.yubaiFont(YubaiFont.callout)
            } }
            Card { VStack(alignment: .leading, spacing: YubaiSpace.space16) { SectionHeading(title: "除了金额，还可以想想"); ForEach(a.questions, id: \.self) { Text("· " + $0).yubaiFont(YubaiFont.body) }; Text("你重视：" + store.current.preferences.purchaseValues).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted) } }
            reflectionCard(a)
            Button(saved ? "已经记下这次思考" : "保存这次思考") { saved = true; if !store.update("保存购买思考", { $0.advice.append(AdviceRecord(title: title, amount: assessedAmount, result: a.title + "。" + a.explanation, note: purpose)) }) { saved = false } }.buttonStyle(SecondaryButtonStyle()).disabled(saved)
        }
    }
    private func reflectionCard(_ a: PurchaseAssessment) -> some View {
        Card(style: .compact, background: YubaiColor.brandTint) { VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            HStack(spacing: YubaiSpace.space8) { AssistantMark(thinking: busy); Text("智能辅助 · 补充使用价值思考").yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.brandInk) }
            Text(LocalIntelligence.availabilityText(for: store.current.preferences)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk)
            if busy { HStack(spacing: YubaiSpace.space8) { Text("正在思考…").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk) } }
            else if !reflection.isEmpty { Text(reflection).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.brandInk).textSelection(.enabled); InlineNote(text: "AI 补充可能不准确；上方金额始终来自确定性计算。") }
            if let aiError { InlineNote(text: aiError, style: .attention) }
            Button("让智能补充想法") { reflect(a) }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin).disabled(!LocalIntelligence.canAssist(preferences: store.current.preferences) || busy)
            if !store.current.preferences.localAIEnabled { Text("智能辅助已在设置中关闭。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk) }
            else if !LocalIntelligence.canAssist(preferences: store.current.preferences) { Text("当前为规则路径：可在设置中开启「增强智能（云端）」。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk) }
        } }
    }
    func assess() { do { let cents = try Money.parse(amount); guard cents > 0, !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw YubaiError.invalid("请填写想买的东西和金额。") }; focusedField = nil; assessedAmount = cents; assessment = Finance.assessPurchase(store.current, amount: cents); reflection = ""; saved = false } catch { store.error = error.localizedDescription } }
    func reflect(_ a: PurchaseAssessment) {
        task?.cancel(); busy = true; aiError = nil
        let preferences = store.current.preferences
        task = Task { do { let text = try await LocalIntelligence.reflect(title: title, purpose: purpose, values: preferences.purchaseValues, assessment: a, preferences: preferences); guard !Task.isCancelled else { return }; reflection = text; busy = false } catch { guard !Task.isCancelled else { return }; aiError = "这次智能补充没有完成。资金计算已保留，你可以稍后重试或改用规则路径。"; busy = false } }
    }
    func invalidate() { task?.cancel(); assessment = nil; reflection = ""; busy = false; saved = false }
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
        }.accessibilityLabel("分类消费分布，具体金额见下方列表")
    }
}
