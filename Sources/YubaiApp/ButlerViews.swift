import SwiftUI
import Charts
import YubaiCore

typealias CardDismissAnimation = (@escaping () -> Bool) -> Void

/// Letter cards close only through ×. Their content keeps its existing actions.
struct LetterDismissCard<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDismiss: () -> Bool
    var onMute: (() -> Bool)? = nil
    @ViewBuilder let content: (@escaping CardDismissAnimation) -> Content
    var body: some View {
        content { action in withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { _ = action() } }
            .overlay(alignment: .topTrailing) {
                Button { withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { _ = onDismiss() } } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(YubaiColor.labelSecondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).padding(4).accessibilityLabel("收起").accessibilityIdentifier("dismissLetterCard")
            }
            .accessibilityAction(named: "收起") { _ = onDismiss() }
            .accessibilityAction(named: "以后别提") { _ = onMute?() }
    }
}

struct ButlerCardView: View {
    @Environment(AppStore.self) private var store
    let card: ButlerCard
    var additionalCount = 0
    var nudgesOnce = false
    private var hidden: Bool { store.preferences.hideAmounts }
    private var exceedsRestraint: Bool {
        guard card.kind == .restrain else { return false }
        return store.restrainProgress.contains { $0.areaID == card.areaID && $0.status == .over }
    }
    private var amber: Bool { [.shortfall, .unknownInflow, .answerQuestion, .duplicate].contains(card.kind) || exceedsRestraint }
    private var ink: Color { amber ? YubaiColor.amberInk : YubaiColor.labelSecondary }
    var body: some View {
        LetterDismissCard(onDismiss: { store.dismissCard(card.id) }, onMute: { store.muteCard(card.id) }) { animateDismiss in
            cardContent(animateDismiss: animateDismiss)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("butlerCard_" + card.kind.rawValue)
    }
    private func cardContent(animateDismiss: @escaping CardDismissAnimation) -> some View {
        Card(style: .compact, background: amber ? YubaiColor.amberTint : YubaiColor.paperSheet) {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                HStack(spacing: YubaiSpace.space8) {
                    if amber { Circle().fill(YubaiColor.amberDot).frame(width: 6, height: 6).accessibilityHidden(true) }
                    Text(meta).yubaiFont(YubaiFont.meta).foregroundStyle(ink).padding(.trailing, 28)
                    Spacer(minLength: YubaiSpace.none)
                }.frame(minHeight: YubaiSize.pillHeight)
                Text(hidden ? "需要留意" : card.title).yubaiFont(YubaiFont.cardTitle)
                    .foregroundStyle(amber ? YubaiColor.amberStrong : YubaiColor.label)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("butlerTitle_" + card.kind.rawValue)
                Button { store.present(.cardEvidence(card.id), from: "card-" + card.id.uuidString) } label: {
                    Text(evidenceText)
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).multilineTextAlignment(.leading)
                }.buttonStyle(PressButtonStyle()).frame(minHeight: YubaiSize.tapMin, alignment: .leading)
                if card.evidence.count > 1 {
                    LetterEntryInset(entries: store.evidenceEntries(Set(card.evidence), activeOnly: true))
                    if card.evidence.count > 3 { Text("还有 \(card.evidence.count - 3) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.gapGroup) { actions(animateDismiss: animateDismiss); Spacer(minLength: YubaiSpace.none); more }
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) { actions(animateDismiss: animateDismiss); more }
                }.padding(.top, YubaiSpace.space4)
            }
        }.yubaiZoomSource("card-" + card.id.uuidString)
            .onAppear {
                if card.kind == .shortfall, YubaiMotion.claim("floor-alert-" + card.id.uuidString) { store.floorWarningTrigger &+= 1 }
            }
    }
    @ViewBuilder private func actions(animateDismiss: @escaping CardDismissAnimation) -> some View {
        if card.kind == .offCharacter {
            HStack(spacing: YubaiSpace.space8) {
                let worth = card.evidence.count > 1 ? "都值得" : "值得"
                Button(worth) { animateDismiss { store.cardFeedback(.worth, id: card.id) } }
                Button("有点后悔") { animateDismiss { store.cardFeedback(.regret, id: card.id) } }
            }.buttonStyle(ButlerActionStyle(amber: true))
        } else {
            Button(actionTitle) {
                if card.kind == .weeklyLetter { store.sheet = .letter(card.id) }
                else if card.kind == .shortfall { store.present(.ask("接下来的付款有缺口，帮我看看怎么挪。" + card.title), from: "card-" + card.id.uuidString) }
                else { store.sheetSource = "card-" + card.id.uuidString; store.performCardAction(card) }
            }.buttonStyle(ButlerActionStyle(amber: amber))
        }
    }
    @ViewBuilder private var more: some View {
        if additionalCount > 0 {
            TabNavigationLink(.inbox) { LetterInboxView() } label: { Text("还有 \(additionalCount) 件 ›").yubaiFont(YubaiFont.caption) }
                .buttonStyle(PressButtonStyle()).foregroundStyle(ink).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("allButlerCards")
        }
    }
    private var meta: String {
        if card.kind == .offCharacter, let meta = card.meta { return meta }
        let label: String
        switch card.kind {
        case .shortfall: label = "钱不够"
        case .restrain: label = "想克制的"
        case .unknownInflow: label = "这笔是什么？"
        case .staleBalance: label = "还没对过账"
        case .answerQuestion: label = "有个问题"
        case .offCharacter: label = "比平时贵"
        case .followUp: label = "买了一个月 · 用得怎么样？"
        case .cooldownDue: label = "心愿单"
        case .recurring: label = "像是会回来的账单"
        case .duplicate: label = "可能记重了"
        case .weeklyLetter: label = "每周来信"
        }
        let area = store.profile.restrain.first { $0.id == card.areaID }
        return label + (area.map { " · " + $0.title } ?? "") + " · " + card.createdAt.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
    }
    private var evidenceText: String {
        if card.kind == .offCharacter, card.meta != nil {
            let link = card.evidence.count > 1 ? "看看这 \(card.evidence.count) 笔 ›" : "看这笔 ›"
            return hidden ? "金额已隐藏 · " + link : card.body
        }
        return (hidden ? "金额已隐藏" : card.body) + " · 明细：\(card.evidence.count) 笔 ›"
    }
    private var actionTitle: String {
        switch card.action ?? .openEvidence {
        case .openEvidence: return card.kind == .shortfall ? "问问怎么挪" : "看看这几笔"
        case .reconcileAccount: return "对一下余额"
        case .confirmChangeSet: return "余白想这样改"
        case .answerQuestion: return "回答这个问题"
        case .openWish: return "看看心愿"
        }
    }
}

private struct ButlerActionStyle: ButtonStyle {
    var amber: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.callout, weight: .medium)
            .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
            .foregroundStyle(amber ? YubaiColor.amberInk : YubaiColor.onBrand)
            .background(amber ? YubaiColor.raised : YubaiColor.brand, in: Capsule())
            .frame(minHeight: YubaiSize.tapMin).opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.97 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

struct ButlerEvidenceView: View {
    @Environment(AppStore.self) private var store
    let cardID: UUID
    var body: some View {
        if let card = store.cards.first(where: { $0.id == cardID }), card.kind == .weeklyLetter, let letter = card.letter {
            weeklyPage(card, letter: letter)
        } else { genericPage }
    }
    private func weeklyPage(_ card: ButlerCard, letter: LetterFacts) -> some View {
        let rows = store.evidenceEntries(Set(card.evidence))
        let days = Dictionary(grouping: rows, by: { Dates.day($0.date) })
        return Page(spacing: 16, topPadding: 8) {
            Card(style: .list) {
                VStack(spacing: 0) {
                    ForEach(Array(letter.numbers.enumerated()), id: \.offset) { index, fact in
                        factRow(fact)
                        if index < letter.numbers.count - 1 { EntryFormDivider() }
                    }
                }
            }
            Card(style: .list) {
                DisclosureGroup {
                    VStack(spacing: 0) {
                        ForEach(letter.series) { point in
                            factRow(CardFact(FixedFlowPresentation.monthDay(point.date), cents: point.available))
                            if point.id != letter.series.last?.id { EntryFormDivider() }
                        }
                    }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text("每天收盘还能花"); Spacer(); Text("\(letter.series.count) 天").foregroundStyle(YubaiColor.labelSecondary) }
                        VStack(alignment: .leading, spacing: 4) { Text("每天收盘还能花"); Text("\(letter.series.count) 天").foregroundStyle(YubaiColor.labelSecondary) }
                    }.yubaiFont(YubaiFont.callout).frame(minHeight: 48)
                }.tint(YubaiColor.labelSecondary).accessibilityIdentifier("weeklyDailyAvailable")
            }
            Text("这一周的 \(rows.count) 笔").yubaiFont(YubaiFont.callout, weight: .semibold)
                .foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, 16)
            ForEach(days.keys.sorted(by: >), id: \.self) { date in
                let entries = days[date] ?? []
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(FixedFlowPresentation.monthDay(date)).yubaiFont(YubaiFont.callout, weight: .semibold)
                        Spacer()
                        AmountLabel(cents: entries.reduce(0) { $0 + ($1.nature.inflow ? $1.amount : -$1.amount) }, hide: store.preferences.hideAmounts, role: .day)
                    }.foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, 16)
                    CardRows(entries) { entry in EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts) }
                }
            }
        }.safeAreaInset(edge: .top, spacing: 0) { LedgerPageHeader(title: "明细", backTitle: "每周来信").padding(.horizontal, 20) }
            .navigationTitle("明细").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
    private func factRow(_ fact: CardFact) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { Text(fact.label).yubaiFont(YubaiFont.row).fixedSize(); Spacer(minLength: 8); factAmount(fact).fixedSize() }
            VStack(alignment: .leading, spacing: 4) { Text(fact.label).yubaiFont(YubaiFont.row); factAmount(fact) }
        }.frame(minHeight: 48)
    }
    private func factAmount(_ fact: CardFact) -> some View {
        Text(store.preferences.hideAmounts && fact.cents != nil ? "••••" : fact.value)
            .yubaiFont(YubaiFont.amountSmall).lineLimit(1).minimumScaleFactor(0.7)
    }
    private var genericPage: some View {
        Page {
            if let card = store.cards.first(where: { $0.id == cardID }) {
                Text(store.preferences.hideAmounts ? "明细" : card.title).yubaiFont(YubaiFont.lead)
                Text("明细生成于 " + Dates.text(card.createdAt, time: true)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        ForEach(Array((card.facts ?? []).enumerated()), id: \.offset) { _, fact in
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                Text(fact.label).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                Text(store.preferences.hideAmounts && fact.cents != nil ? "••••" : fact.value).yubaiFont(YubaiFont.body)
                            }
                        }
                        if card.kind == .shortfall {
                            Button("查看接下来要付") { store.sheet = nil; store.destination = .ledger }
                        }
                    }
                }
                let ids = Set(card.evidence)
                let rows = store.evidenceEntries(ids)
                CardRows(rows) { entry in
                    EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts)
                }
                if card.evidence.count > rows.count { Text("部分原始记录已移除。").yubaiFont(YubaiFont.caption) }
            } else { Text("这张卡片已移除。") }
        }.navigationTitle("明细").yubaiNavigation().manualSheetHeader("明细", cancelTitle: "关闭", showsAction: false)
    }
}

struct ButlerQuestionView: View {
    @Environment(AppStore.self) private var store
    let cardID: UUID
    @State private var text = ""
    @State private var describing = false
    private var fallback: ImportQuestion? { store.cards.first { $0.id == cardID }?.importQuestion }
    var body: some View {
        Group {
            if let fallback, fallback.isFallback { UnsortedGroupsView(questionID: fallback.id) }
            else { questionContent.navigationTitle("补充用途").yubaiNavigation() }
        }.manualSheetHeader(fallback?.isFallback == true ? "待分类" : "补充用途", cancelTitle: "关闭", showsAction: false)
    }
    private var questionContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
                if let card = store.cards.first(where: { $0.id == cardID }), let question = card.importQuestion,
                   let batch = store.imports.first(where: { $0.undoneAt == nil && $0.organization?.questions.contains(where: { $0.id == question.id }) == true }) {
                    Text(store.preferences.hideAmounts ? "这几笔是什么用途？" : question.text).yubaiFont(YubaiFont.lead)
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
                    }
                    let ids = Set(question.entryIDs)
                    let rows = store.evidenceEntries(ids)
                    CardRows(rows) { entry in EntryRow(entry: entry, hideAmount: store.preferences.hideAmounts) }
                        .accessibilityIdentifier("questionEntries")
                } else { Text("这个问题已经处理过了。") }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.gapSection)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).paperBackground()
    }
}

struct ButlerProposalView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let changeID: UUID
    var body: some View {
        Page {
            if let change = store.current.pendingChanges.first(where: { $0.id == changeID }) {
                ProposalCard(title: store.preferences.hideAmounts ? "余白想这样改" : change.reason, lines: store.preferences.hideAmounts ? [] : change.preview(in: store.current, showPreviousValues: true), primaryTitle: Set(change.items.flatMap(\.entryIDs)).isEmpty ? "改好这 \(change.items.count) 项" : "改好这 \(Set(change.items.flatMap(\.entryIDs)).count) 笔", canConfirm: !store.preferences.hideAmounts, confirm: {
                    if store.apply(change, label: "余白想这样改") { dismiss() }
                }, cancel: {
                    if store.update("不改了", { ledger in
                        ledger.pendingChanges.removeAll { $0.id == change.id }
                        for i in ledger.cards.indices where ledger.cards[i].action == .confirmChangeSet(change.id) {
                            ledger.cards[i].dismissedAt = Date()
                        }
                    }) { dismiss() }
                })
            } else { Text("这份修改已经处理过了。") }
        }.navigationTitle("余白想这样改").yubaiNavigation().manualSheetHeader("余白想这样改", cancelTitle: "关闭", showsAction: false)
    }
}

struct LetterDetailView: View {
    @Environment(AppStore.self) private var store
    let cardID: UUID
    var backTitle = "来信"
    var body: some View {
        Page(topPadding: YubaiSpace.gapGroup) {
            if let card = store.cards.first(where: { $0.id == cardID }) { WeeklyLetterCard(card: card) }
            else { Text("这封每周来信已移除。") }
        }.safeAreaInset(edge: .top, spacing: 0) { LedgerPageHeader(title: "每周来信", backTitle: backTitle).padding(.horizontal, 20) }
            .navigationTitle("每周来信").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear {
                if store.cards.first(where: { $0.id == cardID })?.dismissedAt == nil {
                    store.update("读过每周来信", recordUndo: false) { ledger in
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
    private var letterBody: String {
        guard let facts = card.letter else { return card.body }
        return WeeklyLetter.displayBody(card.body, facts: facts)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            if let facts = card.letter {
                Text(Dates.addDays(-6, to: facts.weekEnding).formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) + " – " + facts.weekEnding.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
            Text(store.preferences.hideAmounts ? "金额已隐藏。" : letterBody).yubaiFont(YubaiFont.quote).accessibilityIdentifier("letterBody")
            if let facts = card.letter { LetterSavingsTiles(facts: facts) }
            if let subscriptions = card.letter?.subscriptions, !subscriptions.isEmpty {
                LetterSubscriptionCard(candidates: subscriptions, letterDate: card.createdAt)
            }
            if let facts = card.letter {
                letterNumbers(facts)
                if !store.preferences.hideAmounts { letterChart(facts) }
            }
            NavigationLink { ButlerEvidenceView(cardID: card.id) } label: {
                Card(style: .list) {
                    HStack(spacing: 8) {
                        Text("明细 · \(card.evidence.count) 笔").yubaiFont(YubaiFont.row)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }.frame(minHeight: 48)
                }
            }.hidesListDisclosure().buttonStyle(PressButtonStyle()).accessibilityIdentifier("weeklyLetterEvidence")
            if let learned = card.letter?.learned, !learned.isEmpty {
                Card(background: YubaiColor.brandTint) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        HStack(spacing: YubaiSpace.space8) {
                            AssistantMark(size: 14).accessibilityHidden(true)
                            Text("新记得的 \(learned.count) 条").yubaiFont(YubaiFont.caption)
                        }.foregroundStyle(YubaiColor.brandInk)
                        ForEach(Array(learned.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: YubaiSpace.space8) {
                                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                    Text(line.text).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.brandTintStrong)
                                    if let memory = store.current.memories.first(where: { $0.id == line.memoryID }) {
                                        Text(Dates.text(memory.updatedAt) + " · " + memory.source.label)
                                            .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button("不对") { store.update("纠正每周来信记忆") { Memory.reject(lineMemoryID: line.memoryID, in: &$0) } }
                                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk).frame(minHeight: YubaiSize.tapMin)
                                    .buttonStyle(PressButtonStyle()).accessibilityLabel("不对：" + line.text)
                            }
                        }
                    }
                }
            }
            if let review = card.letter?.review, ProfileReview.isCurrent(review, in: store.current) {
                Card(background: YubaiColor.amberTint) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        Text("这条还算数吗？").yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.amberInk)
                        Text(ProfileReview.summary(review)).yubaiFont(YubaiFont.row)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.space8) { reviewActions(review) }
                            VStack(spacing: YubaiSpace.space8) { reviewActions(review) }
                        }.padding(.top, YubaiSpace.space8)
                    }
                }
            }
            Card(style: .list) {
                WeeklyLetterReminder()
            }
            ProfileChatEntry(title: "聊聊这周", context: .weeklyLetter(card.body))
        }.sheet(item: $reviewProposal) { change in
            NavigationStack { ButlerProposalView(changeID: change.id) }.appErrors().yubaiSheetBackground()
        }
    }
    private func letterChart(_ facts: LetterFacts) -> some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                SectionHeading(title: "还能花这一周", meta: "每天收盘")
                ChartGrow(key: "letter-chart-" + card.id.uuidString) { progress in LetterChart(points: facts.series, progress: progress) }
            }
        }
    }
    private func letterNumbers(_ facts: LetterFacts) -> some View {
        let numbers = Array(facts.numbers.prefix(3))
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.gapGroup)) : AnyLayout(HStackLayout(alignment: .top, spacing: YubaiSpace.gapGroup))
        return VStack(spacing: YubaiSpace.gapGroup) {
            layout {
                ForEach(Array(numbers.prefix(2).enumerated()), id: \.offset) { _, fact in letterNumber(fact) }
            }
            if let third = numbers.dropFirst(2).first {
                Card(style: .compact) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { Text(third.label).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).fixedSize(); Spacer(minLength: 8); letterAmount(third).fixedSize() }
                        VStack(alignment: .leading, spacing: 4) { Text(third.label).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary); letterAmount(third) }
                    }
                }
            }
        }
    }
    private func letterNumber(_ fact: CardFact) -> some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(fact.label).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                letterAmount(fact)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private func letterAmount(_ fact: CardFact) -> some View {
        Text(store.preferences.hideAmounts && fact.cents != nil ? "••••" : fact.value).yubaiFont(YubaiFont.amountCard)
            .lineLimit(1).minimumScaleFactor(0.7).numberTransition(value: Double(fact.cents ?? 0) / 100)
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
                    else if store.update("保存消费观修改", { $0.pendingChanges.append(change) }) { reviewProposal = change }
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
            AreaMark(x: .value("日期", point.date), y: .value("还能花", Double(point.available) / 100))
                .interpolationMethod(.stepEnd).foregroundStyle(YubaiColor.brand.opacity(0.12))
            LineMark(x: .value("日期", point.date), y: .value("还能花", Double(point.available) / 100))
                .interpolationMethod(.stepEnd).foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: YubaiSize.lineWidth))
        }.chartYScale(domain: domain).chartYAxis(.hidden)
            .chartPlotStyle { plot in plot.mask(alignment: .leading) { GeometryReader { geometry in Rectangle().frame(width: geometry.size.width * progress) } } }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.month().day()).foregroundStyle(YubaiColor.labelSecondary).font(.system(size: YubaiFont.chartLabel.size))
            } }.frame(height: 140)
            .accessibilityElement(children: .ignore).accessibilityLabel("一周还能花变化：" + points.map { Dates.text($0.date) + " " + Money.text($0.available) }.joined(separator: "；"))
    }
}

struct LettersView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Page {
            if !store.cards.contains(where: { $0.kind == .weeklyLetter }) { EmptyState("envelope", "还没有每周来信", action: "问余白", onAction: { store.sheet = .ask("") }) }
            ForEach(store.cards.filter { $0.kind == .weeklyLetter }.sorted { $0.createdAt > $1.createdAt }) { card in
                NavigationLink {
                    LetterDetailView(cardID: card.id, backTitle: "每周来信")
                } label: {
                    HStack(spacing: YubaiSpace.gapGroup) { Text(card.title); Spacer(); Text(Dates.text(card.createdAt)).foregroundStyle(YubaiColor.labelSecondary) }
                        .yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("每周来信").yubaiNavigation().manualSheetHeader("每周来信", cancelTitle: "关闭", showsAction: false)
    }
}
