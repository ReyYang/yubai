import SwiftUI
import Charts
import YubaiCore

struct ButlerSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let cards = ButlerCards.visible(store.current)
        VStack {
            if let first = cards.first {
                ButlerCardView(card: first, additionalCount: cards.count - 1).id(first.id)
                    .transition(YubaiMotion.cardTransition(reduceMotion: reduceMotion))
            } else {
                HStack(spacing: 8) { AssistantMark(size: 14).accessibilityHidden(true); Text("管家这会儿没有要说的。") }
                    .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).padding(.vertical, 4)
            }
        }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: cards.map(\.id))
    }
}

struct ButlerListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let cards = ButlerCards.visible(store.current)
        Page {
            ForEach(cards) { card in ButlerCardView(card: card).transition(YubaiMotion.cardTransition(reduceMotion: reduceMotion)) }
            if !store.current.mutedTopics.isEmpty {
                Text("说过「以后别提」的：\(store.current.mutedTopics.count) 类").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
        }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: cards.map(\.id)).navigationTitle("管家的话").yubaiNavigation()
    }
}

struct ButlerCardView: View {
    @Environment(AppStore.self) private var store
    let card: ButlerCard
    var additionalCount = 0
    private var hidden: Bool { store.current.preferences.hideAmounts }
    private var amber: Bool { [.shortfall, .unknownInflow, .answerQuestion, .duplicate].contains(card.kind) }
    private var ink: Color { amber ? YubaiColor.amberInk : YubaiColor.labelSecondary }
    var body: some View {
        Card(style: .compact, background: amber ? YubaiColor.amberTint : YubaiColor.card) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if amber { Circle().fill(YubaiColor.amberDot).frame(width: 6, height: 6).accessibilityHidden(true) }
                    Text(meta).yubaiFont(YubaiFont.meta).foregroundStyle(ink)
                    Spacer(minLength: 0)
                }.frame(minHeight: 28).padding(.trailing, 40)
                Text(hidden ? "管家的观察" : card.title).yubaiFont(YubaiFont.cardTitle).padding(.trailing, 32)
                    .foregroundStyle(amber ? YubaiColor.amberStrong : YubaiColor.label)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("butlerTitle_" + card.kind.rawValue)
                Button { store.present(.cardEvidence(card.id), from: "card-" + card.id.uuidString) } label: {
                    Text(evidenceText)
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).multilineTextAlignment(.leading)
                }.buttonStyle(PressButtonStyle()).frame(minHeight: 44, alignment: .leading)
                ViewThatFits(in: .horizontal) {
                    HStack { actions; Spacer(minLength: 0); more }
                    VStack(alignment: .leading, spacing: 4) { actions; more }
                }
            }.overlay(alignment: .topTrailing) {
                Menu {
                    Button("知道了") { store.dismissCard(card.id) }
                    Button("以后别提") { store.muteCard(card.id) }
                } label: {
                    Image(systemName: "ellipsis").yubaiFont(YubaiFont.callout)
                        .frame(width: 28, height: 28).background(YubaiColor.raised, in: Circle()).frame(width: 44, height: 44)
                }.accessibilityLabel("更多：知道了、以后别提").accessibilityIdentifier("butlerOptions_" + card.kind.rawValue)
            }
        }.yubaiZoomSource("card-" + card.id.uuidString)
            .onAppear { if card.kind == .shortfall, YubaiMotion.claim("floor-alert-" + card.id.uuidString) { store.floorWarningTrigger &+= 1 } }
    }
    @ViewBuilder private var actions: some View {
        if card.kind == .offCharacter {
            HStack(spacing: 8) {
                let worth = card.evidence.count > 1 ? "都值得" : "值得"
                Button(card.feedback == .worth ? "已记下：" + worth : worth) { store.cardFeedback(.worth, id: card.id) }
                Button(card.feedback == .regret ? "已记下：有点后悔" : "有点后悔") { store.cardFeedback(.regret, id: card.id) }
            }.disabled(card.feedback != nil).buttonStyle(ButlerActionStyle(amber: true))
        } else {
            Button(actionTitle) {
                if card.kind == .shortfall { store.present(.ask("接下来的付款有缺口，帮我看看怎么挪。" + card.title), from: "card-" + card.id.uuidString) }
                else { store.sheetSource = "card-" + card.id.uuidString; store.performCardAction(card) }
            }.buttonStyle(ButlerActionStyle(amber: amber))
        }
    }
    @ViewBuilder private var more: some View {
        if additionalCount > 0 {
            NavigationLink { ButlerListView() } label: { Text("还有 \(additionalCount) 件 ›").yubaiFont(YubaiFont.caption) }
                .buttonStyle(PressButtonStyle()).foregroundStyle(ink).frame(minHeight: 44).accessibilityIdentifier("allButlerCards")
        }
    }
    private var meta: String {
        if card.kind == .offCharacter, let meta = card.meta { return meta }
        let label: String
        switch card.kind {
        case .shortfall: label = "钱不够"
        case .restrain: label = "想克制的"
        case .unknownInflow: label = "待明确"
        case .staleBalance: label = "没核对"
        case .answerQuestion: label = "待回答"
        case .offCharacter: label = "不像你"
        case .followUp: label = "该回访了"
        case .recurring: label = "周期收付"
        case .duplicate: label = "可能重复"
        case .weeklyLetter: label = "周一来信"
        }
        let area = store.current.profile.restrain.first { $0.id == card.areaID }
        return label + (area.map { " · " + $0.title } ?? "") + " · " + card.createdAt.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
    }
    private var evidenceText: String {
        if card.kind == .offCharacter, card.meta != nil {
            let link = card.evidence.count > 1 ? "看看这 \(card.evidence.count) 笔 ›" : "看这笔 ›"
            return hidden ? "金额已隐藏 · " + link : card.body
        }
        return (hidden ? "金额已隐藏" : card.body) + " · 依据 ›"
    }
    private var actionTitle: String {
        switch card.action ?? .openEvidence {
        case .openEvidence: return card.kind == .shortfall ? "问问怎么挪" : "看看这几笔"
        case .reconcileAccount: return "核对余额"
        case .confirmChangeSet: return "看看提案"
        case .answerQuestion: return "回答这个问题"
        case .openWish: return "看看心愿"
        }
    }
}

private struct ButlerActionStyle: ButtonStyle {
    var amber: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.callout, weight: .medium)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(amber ? YubaiColor.amberInk : YubaiColor.onBrand)
            .background(amber ? YubaiColor.raised : YubaiColor.brand, in: Capsule())
            .frame(minHeight: 44).opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.97 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
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
                            Button("查看付款与预留") { store.sheet = nil; store.destination = .overview }
                        }
                    }
                }
                let ids = Set(card.evidence)
                let rows = store.sortedEntries.filter { ids.contains($0.id) }
                CardRows(rows) { entry in
                    EntryLink(entry: entry, hideAmount: store.current.preferences.hideAmounts)
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
    @Environment(\.dismiss) private var dismiss
    let changeID: UUID
    var body: some View {
        Page {
            if let change = store.current.pendingChanges.first(where: { $0.id == changeID }) {
                ProposalCard(title: store.current.preferences.hideAmounts ? "等你核对的修改" : change.reason, lines: store.current.preferences.hideAmounts ? ["金额已隐藏，请显示金额后核对。"] : change.preview(in: store.current, showPreviousValues: true), primaryTitle: "记下这些修改", canConfirm: !store.current.preferences.hideAmounts, confirm: {
                    if store.apply(change, label: "确认管家提案") { dismiss() }
                }, cancel: {
                    if store.update("放下提案", { $0.pendingChanges.removeAll { $0.id == change.id } }) { dismiss() }
                })
            } else { Text("这份提案已经处理过了。") }
        }.navigationTitle("等你确认").yubaiNavigation().toolbar { CloseButton() }
    }
}

struct LetterDetailView: View {
    @Environment(AppStore.self) private var store
    let cardID: UUID
    var body: some View {
        Page(topPadding: 14) {
            if let card = store.current.cards.first(where: { $0.id == cardID }) { WeeklyLetterCard(card: card) }
            else { Text("这封来信已移除。") }
        }.navigationTitle("来信").yubaiNavigation()
            .onAppear {
                if store.current.cards.first(where: { $0.id == cardID })?.dismissedAt == nil {
                    store.update("读过来信", recordUndo: false) { ledger in
                        if let i = ledger.cards.firstIndex(where: { $0.id == cardID }) { ledger.cards[i].dismissedAt = Date() }
                    }
                }
            }
    }
}

struct WeeklyLetterCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let card: ButlerCard
    @State private var reviewProposal: ChangeSet?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let facts = card.letter {
                Text(Dates.addDays(-6, to: facts.weekEnding).formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) + " – " + facts.weekEnding.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
            Text(store.current.preferences.hideAmounts ? "金额已隐藏。" : card.body).yubaiFont(YubaiFont.quote)
            if let facts = card.letter, !store.current.preferences.hideAmounts {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeading(title: "余白这一周", meta: "每日收盘回算")
                        ChartGrow(key: "letter-chart-" + card.id.uuidString) { progress in LetterChart(points: facts.series, progress: progress) }
                    }
                }
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    ForEach(Array(facts.numbers.enumerated()), id: \.offset) { _, fact in
                        Card(style: .compact) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.label).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                                Text(fact.value).yubaiFont(YubaiFont.amountCard).numberTransition(value: Double(fact.cents ?? 0) / 100)
                            }
                        }
                    }
                }
            }
            Button("依据：这周 \(card.evidence.count) 笔记录 ›") { store.sheet = .cardEvidence(card.id) }
                .yubaiFont(YubaiFont.caption).padding(.horizontal, 10).frame(minHeight: 44).background(YubaiColor.raised, in: Capsule())
            if let learned = card.letter?.learned, !learned.isEmpty {
                Card(background: YubaiColor.brandTint) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        HStack(spacing: YubaiSpace.space6) {
                            AssistantMark(size: 14).accessibilityHidden(true)
                            Text("这周我对你多了解了一点").yubaiFont(YubaiFont.caption)
                        }.foregroundStyle(YubaiColor.brandInk)
                        ForEach(Array(learned.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: YubaiSpace.space8) {
                                Text(line.text).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.brandTintStrong).frame(maxWidth: .infinity, alignment: .leading)
                                Button("不对") { store.update("纠正来信记忆") { Memory.reject(lineMemoryID: line.memoryID, in: &$0) } }
                                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk).frame(minHeight: YubaiSize.tapMin)
                                    .buttonStyle(PressButtonStyle()).accessibilityLabel("不对：" + line.text)
                            }
                        }
                    }
                }
            }
            if let review = card.letter?.review, ProfileReview.isCurrent(review, in: store.current) {
                Card(background: YubaiColor.amberTint) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                        Text("这条还算数吗？").yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.amberInk)
                        Text(ProfileReview.summary(review)).yubaiFont(YubaiFont.row)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.space8) { reviewActions(review) }
                            VStack(spacing: YubaiSpace.space8) { reviewActions(review) }
                        }.padding(.top, YubaiSpace.space6)
                    }
                }
            }
            Text("按当前安排与已记录流水回算；历史设置和遗漏流水可能影响曲线。金额单位：元。")
                .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            Card(style: .list) {
                Toggle("每周一提醒我来信", isOn: Binding(get: { store.current.preferences.weeklyLetterPush }, set: { value in
                    Task { await store.setWeeklyLetterPush(value) }
                })).tint(YubaiColor.toggleOn).disabled(store.updatingWeeklyPush).frame(minHeight: 48)
            }
        }.sheet(item: $reviewProposal) { change in
            NavigationStack { ButlerProposalView(changeID: change.id) }.appErrors()
        }
    }
    private func reviewActions(_ review: ProfileReviewCandidate) -> some View {
        Group {
            Button("还算数") { store.update("确认消费观仍适用") { try ProfileReview.keep(review, in: &$0) } }
                .buttonStyle(PrimaryButtonStyle(compact: true))
            NavigationLink("改一下") { ProfileView() }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
            Button("不需要了") {
                do {
                    let change = try ProfileReview.remove(review, in: store.current)
                    if let existing = store.current.pendingChanges.first(where: { $0.source == change.source && $0.items == change.items }) { reviewProposal = existing }
                    else if store.update("保存消费观删除提案", { $0.pendingChanges.append(change) }) { reviewProposal = change }
                } catch { store.error = error.localizedDescription }
            }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
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
            AreaMark(x: .value("日期", point.date), y: .value("余白", Double(point.available) / 100))
                .interpolationMethod(.stepEnd).foregroundStyle(YubaiColor.brand.opacity(0.12))
            LineMark(x: .value("日期", point.date), y: .value("余白", Double(point.available) / 100))
                .interpolationMethod(.stepEnd).foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: YubaiSize.lineWidth))
        }.chartYScale(domain: domain).chartYAxis(.hidden)
            .chartPlotStyle { plot in plot.mask(alignment: .leading) { GeometryReader { geometry in Rectangle().frame(width: geometry.size.width * progress) } } }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.month().day()).foregroundStyle(YubaiColor.labelSecondary).font(.system(size: YubaiFont.chartLabel.size))
            } }.frame(height: 140)
            .accessibilityElement(children: .ignore).accessibilityLabel("一周余白变化：" + points.map { Dates.text($0.date) + " " + Money.text($0.available) }.joined(separator: "；"))
    }
}

struct LettersView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Page {
            if !store.current.cards.contains(where: { $0.kind == .weeklyLetter }) { Text("还没有来信。").yubaiFont(YubaiFont.callout) }
            ForEach(store.current.cards.filter { $0.kind == .weeklyLetter }.sorted { $0.createdAt > $1.createdAt }) { card in
                NavigationLink {
                    LetterDetailView(cardID: card.id)
                } label: {
                    HStack { Text(card.title); Spacer(); Text(Dates.text(card.createdAt)).foregroundStyle(YubaiColor.labelSecondary) }
                        .yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("来信").yubaiNavigation().toolbar { CloseButton() }
    }
}
