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
            if Date().timeIntervalSince(started) >= 90 { result.warnings.append("本机智能已完成一部分归类；余下记录保留本地规则结果或其他分类，可直接保存。"); break }
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
        case .localDownloaded: return IntelligenceRuntime.weights.hasReadyWeight || preferences.experimentalMockLocalAI
        case .cloudOptional: return preferences.cloudAIEnabled
        case .appleFMOptional: return IntelligenceRuntime.appleFMAvailable
        }
    }
    /// Legacy alias: Apple FM or downloaded / mock path may assist.
    @MainActor static var available: Bool {
        IntelligenceRuntime.appleFMAvailable || IntelligenceRuntime.weights.hasReadyWeight
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
    private var from: Date { Dates.addDays(-days + 1, to: Dates.day(Date())) }
    private var through: Date { Dates.addDays(1, to: Dates.day(Date())) }
    private var review: Review { Finance.review(store.current, from: from, through: through) }
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 8) { Text("看懂花费，也看见自己。").font(.system(.title, design: .serif).weight(.medium)); Text("从真实记录中找线索，不为每一笔小快乐打分。").font(.callout).foregroundStyle(.secondary) }
            Picker("回顾范围", selection: $days) { Text("近 30 天").tag(30); Text("近 90 天").tag(90); Text("近一年").tag(365) }.pickerStyle(.segmented)
            if review.count == 0 { Card { EmptyState("chart.bar", "先有生活的记录，再有洞察", "导入一份账单或记下一笔收支，余白会把线索放在这里。", action: "导入账单") { store.sheet = .imports } } }
            else {
                stats
                categories
                dailyTrend
                observations
            }
            Button { store.sheet = .advice } label: { Card { HStack(spacing: 16) { IconTile(symbol: "sparkle"); VStack(alignment: .leading, spacing: 7) { Text("有一笔购买正在犹豫？").font(.headline); Text("把它放进你的真实资金安排里看一看。").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right") } } }.buttonStyle(.plain)
            if !store.current.advice.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading(title: "之前想过的事")
                        ForEach(Array(store.current.advice.reversed().prefix(8))) { item in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(item.title).font(.headline); Spacer(); AmountLabel(cents: item.amount) }
                                Text(item.result).font(.callout).foregroundStyle(.secondary)
                                Text("当时的判断 · \(Dates.text(item.createdAt))").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        InlineNote(text: "历史判断反映当时的账本；资金变化后请重新计算。")
                    }
                }
            }
        }.navigationTitle("洞察").toolbar { Button { store.sheet = .advice } label: { Label("购买前咨询", systemImage: "sparkle") } }
    }
    var stats: some View {
        Card { VStack(alignment: .leading, spacing: 20) { Text("这段时间，我的消费").font(.callout).foregroundStyle(.secondary); AmountLabel(cents: review.spending, large: true); HStack { VStack(alignment: .leading, spacing: 6) { Text("真实收入").font(.caption).foregroundStyle(.secondary); AmountLabel(cents: review.income) }; Spacer(); VStack(alignment: .trailing, spacing: 6) { Text("已减去退款").font(.caption).foregroundStyle(.secondary); AmountLabel(cents: review.refunds) } }; Divider(); Text("\(review.count) 笔记录 · \(Dates.text(from)) — \(Dates.text(Date()))").font(.caption).foregroundStyle(.secondary); InlineNote(text: "按实际发生日期汇总。排除内部转账、借还本金、投资申赎和分摊收款；房租只计本人承担的比例。") } }
    }
    var categories: some View {
        Card { VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "钱花在了哪里")
            let positive = review.byCategory.filter { $0.amount > 0 }
            if !positive.isEmpty {
                Chart(Array(positive.enumerated()), id: \.element.id) { index, item in SectorMark(angle: .value("消费", Double(item.amount) / 100), innerRadius: .ratio(0.72), angularInset: 2).cornerRadius(4).foregroundStyle(YubaiTheme.palette[index % YubaiTheme.palette.count]) }.frame(height: 180).chartLegend(.hidden).accessibilityLabel("分类消费分布，具体金额见下方列表")
                ForEach(Array(review.byCategory.enumerated()), id: \.element.id) { index, item in HStack(spacing: 12) { Circle().fill(YubaiTheme.palette[index % YubaiTheme.palette.count]).frame(width: 8, height: 8); Text(item.category).font(.callout); Text("\(item.count) 笔").font(.caption).foregroundStyle(.secondary); Spacer(); AmountLabel(cents: item.amount) } }
            } else { Text("这一段还没有消费支出。").foregroundStyle(.secondary) }
        } }
    }
    var dailyTrend: some View {
        let grouped = Dictionary(grouping: store.current.activeEntries.filter { $0.date >= from && $0.date < through && ($0.nature == .expense || $0.nature == .refund) }, by: { Dates.day($0.date) })
        let points = grouped.map { date, entries in (date: date, amount: entries.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: store.current) }) }.sorted { $0.date < $1.date }
        return Card { VStack(alignment: .leading, spacing: 18) { SectionHeading(title: "花费的节奏", subtitle: "金额单位：元，退款按到账日冲减")
            Chart(points, id: \.date) { point in BarMark(x: .value("日期", point.date, unit: .day), y: .value("消费", Double(point.amount) / 100)).foregroundStyle(YubaiTheme.jade.opacity(0.8)).cornerRadius(3) }.frame(height: 180).chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        } }
    }
    var observations: some View {
        Card { VStack(alignment: .leading, spacing: 15) {
            SectionHeading(title: "值得看一眼的线索")
            if let top = review.byCategory.first, top.amount > 0 { Label("\(top.category)是这段时间最大的消费去向，共 \(Money.text(top.amount))。它是否符合你最近的重心？", systemImage: "circle.dotted").font(.callout) }
            if review.previousSpending > 0 { let difference = review.spending - review.previousSpending; Label("比前一段同样长的时间\(difference >= 0 ? "多" : "少") \(Money.text(abs(difference)))。先确认两个区间的账单都完整，再判断变化。", systemImage: "arrow.left.arrow.right").font(.callout) }
            let subscriptions = store.current.plans.filter { $0.active && !$0.inflow && $0.frequency != .once && $0.nature != .repayment }
            if !subscriptions.isEmpty { Label("你有 \(subscriptions.count) 项持续付款约定。可以在安排中核对仍然需要的服务。", systemImage: "repeat").font(.callout) }
            if !insightPolish.isEmpty { Text(insightPolish).font(.callout).foregroundStyle(.secondary) }
            Text("这些线索来自本地计算，不是 AI 推断，也不代表必须削减消费。").font(.caption).foregroundStyle(.secondary)
            if LocalIntelligence.canAssist(preferences: store.current.preferences) {
                Button(insightBusy ? "本机润色中…" : "用本机模型说说") { polishInsights() }
                    .disabled(insightBusy)
                    .font(.caption)
            }
        } }
    }
    func polishInsights() {
        insightBusy = true
        let facts = insightFactPack()
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
    func insightFactPack() -> InsightFactPack {
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
            VStack(alignment: .leading, spacing: 10) { Text("它值得，占用这份余白吗？").font(.system(.title2, design: .serif).weight(.medium)); Text("先算资金承受能力，再想使用价值。最终决定始终由你做。").font(.callout).foregroundStyle(.secondary) }
            Card { VStack(spacing: 16) { TextField("想买什么", text: $title).textFieldStyle(.roundedBorder).focused($focusedField, equals: .title); HStack { Text("¥").foregroundStyle(.secondary); TextField("金额", text: $amount).numericInput().textFieldStyle(.roundedBorder).focused($focusedField, equals: .amount) }; TextField("它能解决什么问题？（可选）", text: $purpose, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder).focused($focusedField, equals: .purpose); Button("看看对资金的影响", action: assess).buttonStyle(PrimaryButtonStyle()).frame(maxWidth: .infinity) } }
            if let assessment { assessmentCard(assessment) }
        }.navigationTitle("购买前想一想").toolbar { CloseButton() }
            .onChange(of: amount) { _, _ in invalidate() }.onChange(of: title) { _, _ in invalidate() }
            .onChange(of: store.current.updatedAt) { _, _ in if !saved { invalidate() } }
            .onDisappear { task?.cancel() }
    }
    func assessmentCard(_ a: PurchaseAssessment) -> some View {
        VStack(spacing: 18) {
            Card { VStack(alignment: .leading, spacing: 18) { Label(a.title, systemImage: a.severity == 2 ? "exclamationmark.circle" : "checkmark.circle").font(.headline).foregroundStyle(a.severity == 2 ? YubaiTheme.amber : YubaiTheme.jade); Text(a.explanation).font(.callout).lineSpacing(4); Divider(); Text("购买后的保守余量").font(.caption).foregroundStyle(.secondary); AmountLabel(cents: a.afterPurchase, large: true); DisclosureGroup("查看计算与完整度依据") { VStack(alignment: .leading, spacing: 10) { ForEach(a.facts, id: \.self) { Text("· " + $0).font(.caption).foregroundStyle(.secondary) } }.padding(.top, 10) } } }
            Card { VStack(alignment: .leading, spacing: 16) { SectionHeading(title: "除了金额，还可以想想"); ForEach(a.questions, id: \.self) { Text("· " + $0).font(.callout) }; Text("你重视：" + store.current.preferences.purchaseValues).font(.caption).foregroundStyle(.secondary) } }
            Card { VStack(alignment: .leading, spacing: 14) {
                Label("本机 AI · 补充使用价值思考", systemImage: "sparkles").font(.headline)
                Text(LocalIntelligence.availabilityText(for: store.current.preferences)).font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView("正在本机思考…") }
                else if !reflection.isEmpty { Text(reflection).font(.callout).lineSpacing(5).textSelection(.enabled); InlineNote(text: "AI 补充可能不准确；上方金额始终来自确定性计算。") }
                if let aiError { Text(aiError).font(.caption).foregroundStyle(YubaiTheme.amber) }
                Button("让本机 AI 补充想法") { reflect(a) }.disabled(!LocalIntelligence.canAssist(preferences: store.current.preferences) || busy)
                if !store.current.preferences.localAIEnabled { Text("本机 AI 已在设置中关闭。").font(.caption).foregroundStyle(.secondary) }
                else if !LocalIntelligence.canAssist(preferences: store.current.preferences) { Text("当前为规则路径：可下载本机模型，或在设置中开启可选云端 / 系统模型。").font(.caption).foregroundStyle(.secondary) }
            } }
            Button(saved ? "已经记下这次思考" : "保存这次思考") { saved = true; if !store.update("保存购买思考", { $0.advice.append(AdviceRecord(title: title, amount: assessedAmount, result: a.title + "。" + a.explanation, note: purpose)) }) { saved = false } }.disabled(saved)
        }
    }
    func assess() { do { let cents = try Money.parse(amount); guard cents > 0, !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw YubaiError.invalid("请填写想买的东西和金额。") }; focusedField = nil; assessedAmount = cents; assessment = Finance.assessPurchase(store.current, amount: cents); reflection = ""; saved = false } catch { store.error = error.localizedDescription } }
    func reflect(_ a: PurchaseAssessment) {
        task?.cancel(); busy = true; aiError = nil
        let preferences = store.current.preferences
        task = Task { do { let text = try await LocalIntelligence.reflect(title: title, purpose: purpose, values: preferences.purchaseValues, assessment: a, preferences: preferences); guard !Task.isCancelled else { return }; reflection = text; busy = false } catch { guard !Task.isCancelled else { return }; aiError = "这次本机思考没有完成。资金计算已保留，你可以稍后重试。"; busy = false } }
    }
    func invalidate() { task?.cancel(); assessment = nil; reflection = ""; busy = false; saved = false }
}
