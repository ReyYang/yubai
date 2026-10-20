import SwiftUI
import Charts
import YubaiCore

struct ButlerSection: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let letter = freshLetter { WeeklyLetterCard(card: letter) }
        ForEach(ButlerCards.visible(store.current)) { card in ButlerCardView(card: card) }
        if store.current.cards.contains(where: { $0.kind == .weeklyLetter }) {
            Button("来信") { store.sheet = .letters }.yubaiFont(YubaiFont.callout).frame(minHeight: YubaiSize.tapMin)
        }
    }
    private var freshLetter: ButlerCard? {
        store.current.cards.first { WeeklyLetter.isFresh($0, now: Date()) && !ButlerCards.isMuted($0.dedupeKey, in: store.current) }
    }
}

struct ButlerCardView: View {
    @Environment(AppStore.self) private var store
    let card: ButlerCard
    private var hidden: Bool { store.current.preferences.hideAmounts }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                HStack(alignment: .top) {
                    Text(store.current.preferences.hideAmounts ? "管家的观察" : card.title).yubaiFont(YubaiFont.cardTitle)
                    Spacer(minLength: YubaiSpace.space8)
                    Menu {
                        Button("知道了") { store.dismissCard(card.id) }
                        Button("以后别提") { store.muteCard(card.id) }
                    } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("卡片选项")
                }
                Text(hidden ? "金额已隐藏。" : card.body).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelMuted)
                Text(Dates.text(card.createdAt) + " · 按当时记录").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                HStack {
                    Button("依据") { store.sheet = .cardEvidence(card.id) }
                    Spacer()
                    Button("知道了") { store.dismissCard(card.id) }
                }.yubaiFont(YubaiFont.callout).buttonStyle(PressButtonStyle()).frame(minHeight: YubaiSize.tapMin)
                Button(actionTitle) { store.performCardAction(card) }.buttonStyle(PrimaryButtonStyle())
                if [.restrain, .offCharacter].contains(card.kind) {
                    HStack(spacing: YubaiSpace.space20) {
                        Button(card.feedback == .worth ? "已记下：值得" : "值得") { store.cardFeedback(.worth, id: card.id) }
                        Button(card.feedback == .regret ? "已记下：有点后悔" : "有点后悔") { store.cardFeedback(.regret, id: card.id) }
                    }.yubaiFont(YubaiFont.caption).frame(minHeight: YubaiSize.tapMin).disabled(card.feedback != nil)
                }
            }
        }.swipeActions { Button("知道了") { store.dismissCard(card.id) } }
    }
    private var actionTitle: String {
        switch card.action ?? .openEvidence {
        case .openEvidence: return card.kind == .shortfall ? "看看付款缺口" : "看看这几笔"
        case .reconcileAccount: return "核对余额"
        case .confirmChangeSet: return "看看提案"
        case .answerQuestion: return "回答这个问题"
        case .openWish: return "看看心愿"
        }
    }
}

struct ButlerEvidenceView: View {
    @Environment(AppStore.self) private var store
    let cardID: UUID
    var body: some View {
        Page {
            if let card = store.current.cards.first(where: { $0.id == cardID }) {
                Text(store.current.preferences.hideAmounts ? "卡片依据" : card.title).yubaiFont(YubaiFont.lead)
                Text("依据生成于 " + Dates.text(card.createdAt, time: true)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                        ForEach(Array((card.facts ?? []).enumerated()), id: \.offset) { _, fact in
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                Text(fact.label).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                Text(store.current.preferences.hideAmounts && fact.cents != nil ? "••••" : fact.value).yubaiFont(YubaiFont.body)
                            }
                        }
                        if card.kind == .shortfall {
                            Text("保守路径已扣信用负债、目标、应急底线和待明确流入，再按日期扣付款与日常预留；未计预计收入。同一天的付款一起计算。").yubaiFont(YubaiFont.caption)
                            Button("查看付款与预留") { store.sheet = nil; store.destination = .plans }
                        }
                    }
                }
                let ids = Set(card.evidence)
                let rows = store.sortedEntries.filter { ids.contains($0.id) }
                CardRows(rows) { entry in
                    NavigationLink { EntryDetailView(entryID: entry.id) } label: { EntryRow(entry: entry, hideAmount: store.current.preferences.hideAmounts) }
                        .buttonStyle(PressButtonStyle())
                }
                if card.evidence.count > rows.count { Text("部分原始记录已移除，以上数值保留生成时的依据。").yubaiFont(YubaiFont.caption) }
            } else { Text("这张卡片已移除。") }
        }.navigationTitle("依据").yubaiNavigation().toolbar { CloseButton() }
    }
}

struct ButlerQuestionView: View {
    @Environment(AppStore.self) private var store
    let cardID: UUID
    @State private var text = ""
    @State private var describing = false
    var body: some View {
        Page {
            if let card = store.current.cards.first(where: { $0.id == cardID }), let question = card.importQuestion,
               let batch = store.current.imports.first(where: { $0.undoneAt == nil && $0.organization?.questions.contains(where: { $0.id == question.id }) == true }) {
                Text(store.current.preferences.hideAmounts ? "这几笔是什么用途？" : question.text).yubaiFont(YubaiFont.lead)
                ForEach(question.options.indices, id: \.self) { index in
                    Button(question.options[index].title) {
                        store.answerImportQuestion(question, batchID: batch.id, option: index); store.sheet = nil
                    }.buttonStyle(SecondaryButtonStyle())
                }
                Button("都不是") { describing = true }.buttonStyle(SecondaryButtonStyle())
                if describing {
                    TextField("用自己的话补充用途", text: $text, axis: .vertical)
                    Button("记下用途") {
                        store.describeImportQuestion(question, batchID: batch.id, text: text); store.sheet = nil
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 80)
                    Text("先记下用途，资金性质继续保守计算。").yubaiFont(YubaiFont.caption)
                }
                let rows = store.sortedEntries.filter { question.entryIDs.contains($0.id) }
                CardRows(rows) { entry in EntryRow(entry: entry, hideAmount: store.current.preferences.hideAmounts) }
            } else { Text("这个问题已经处理过了。") }
        }.navigationTitle("补充用途").yubaiNavigation().toolbar { CloseButton() }
    }
}

struct ButlerProposalView: View {
    @Environment(AppStore.self) private var store
    let changeID: UUID
    var body: some View {
        Page {
            if let change = store.current.pendingChanges.first(where: { $0.id == changeID }) {
                Text(change.reason).yubaiFont(YubaiFont.lead)
                ForEach(Array(change.preview(in: store.current).enumerated()), id: \.offset) { _, line in Text(line).yubaiFont(YubaiFont.body) }
                Button("确认修改") { if store.apply(change, label: "确认管家提案") { store.sheet = nil } }.buttonStyle(PrimaryButtonStyle())
            } else { Text("这份提案已经处理过了。") }
        }.navigationTitle("等你确认").yubaiNavigation().toolbar { CloseButton() }
    }
}

struct WeeklyLetterCard: View {
    @Environment(AppStore.self) private var store
    let card: ButlerCard
    @State private var appeared = false
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space16) {
                HStack {
                    Text(store.current.preferences.hideAmounts ? "这周的来信" : card.title).yubaiFont(YubaiFont.cardTitle)
                    Spacer()
                    Menu {
                        Button("知道了") { store.dismissCard(card.id) }
                        Button("以后别提") { store.muteCard(card.id) }
                    } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("来信选项")
                }
                Text(store.current.preferences.hideAmounts ? "金额已隐藏。" : card.body).yubaiFont(YubaiFont.body)
                if let facts = card.letter {
                    Text(Dates.text(Dates.addDays(-6, to: facts.weekEnding)) + " 至 " + Dates.text(facts.weekEnding)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    if !store.current.preferences.hideAmounts {
                        ChartGrow(appeared: $appeared) { progress in LetterChart(points: facts.series, progress: progress) }
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: YubaiSpace.space16) { smallNumbers(facts) }
                            VStack(alignment: .leading, spacing: YubaiSpace.space12) { smallNumbers(facts) }
                        }
                    }
                    Text("按当前安排与已记录流水回看，历史设置和遗漏流水可能影响曲线。金额单位：元。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
                Button("依据") { store.sheet = .cardEvidence(card.id) }.yubaiFont(YubaiFont.callout).frame(minHeight: YubaiSize.tapMin)
            }
        }
    }
    private func smallNumbers(_ facts: LetterFacts) -> some View {
        ForEach(Array(facts.numbers.enumerated()), id: \.offset) { _, fact in
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(fact.label).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Text(fact.value).yubaiFont(YubaiFont.amountSmall)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LetterChart: View {
    let points: [LetterPoint]
    let progress: Double
    private var domain: ClosedRange<Double> {
        let values = points.map { Double($0.available) / 100 }
        return min(0, values.min() ?? 0)...max(1, values.max() ?? 0)
    }
    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("日期", point.date), y: .value("余白", Double(point.available) / 100 * progress))
                .foregroundStyle(YubaiColor.brand.opacity(0.12))
            LineMark(x: .value("日期", point.date), y: .value("余白", Double(point.available) / 100 * progress))
                .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: YubaiSize.lineWidth))
        }.chartYScale(domain: domain).chartYAxis(.hidden)
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.month().day()).foregroundStyle(YubaiColor.labelSecondary).font(.system(size: YubaiFont.chartLabel.size))
            } }.frame(height: 140)
            .accessibilityLabel("一周余白变化")
    }
}

struct LettersView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Page {
            ForEach(store.current.cards.filter { $0.kind == .weeklyLetter }.sorted { $0.createdAt > $1.createdAt }) { card in
                NavigationLink {
                    Page { WeeklyLetterCard(card: card) }.navigationTitle("来信").yubaiNavigation()
                } label: {
                    HStack { Text(card.title); Spacer(); Text(Dates.text(card.createdAt)).foregroundStyle(YubaiColor.labelSecondary) }
                        .yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("来信").yubaiNavigation().toolbar { CloseButton() }
    }
}
