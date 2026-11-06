import SwiftUI
import Charts
import YubaiCore

struct ButlerSection: View {
    var body: some View { NowCardsSection() }
}

/// The action runs only after the card has left. Returning false restores it
/// when persistence fails, leaving the existing error presentation in charge.
typealias CardDismissAnimation = (@escaping () -> Bool) -> Void

struct SwipeDismissCard<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("butlerSwipeNudgeShown") private var nudgeShown = false
    let onDismiss: () -> Bool
    var onMute: (() -> Bool)? = nil
    var nudgesOnce = false
    var reportsRevealState = true
    @ViewBuilder let content: (@escaping CardDismissAnimation) -> Content
    @State private var width: CGFloat = 1
    @State private var drag: CGFloat = 0
    @State private var opacity = 1.0
    @State private var departing = false
    @State private var nudging = false
    @State private var interacted = false
    @State private var armedDirection = 0
    @State private var thresholdTrigger = 0
    #if os(macOS)
    @GestureState private var dragging = false
    @State private var horizontal: Bool?
    #endif

    private var threshold: CGFloat { width * 0.25 }
    private var right: Bool { drag > 0 && onMute != nil }
    private var labelOpacity: Double {
        guard drag < 0 || right else { return 0 }
        return min(1, Double(abs(drag) / threshold))
    }
    var body: some View {
        accessibleCard
            #if os(iOS)
            .sensoryFeedback(.impact(weight: .light), trigger: thresholdTrigger)
            #endif
            .task {
                guard nudgesOnce, !nudgeShown else { return }
                nudgeShown = true
                guard !reduceMotion else { return }
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                guard !interacted, !departing else { return }
                nudging = true
                withAnimation(YubaiMotion.easeOut(duration: YubaiMotion.durationStandard)) { drag = -24 }
                do { try await Task.sleep(for: .milliseconds(440)) } catch { return }
                guard nudging, !departing else { return }
                nudging = false
                resetDrag()
            }
            .onDisappear {
                nudging = false
                if !departing { drag = 0; armedDirection = 0 }
            }
    }
    @ViewBuilder private var accessibleCard: some View {
        if let onMute {
            gestureCard.accessibilityAction(named: "以后别提") { finish(direction: 1, action: onMute) }
        } else { gestureCard }
    }
    private var gestureCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: YubaiRadius.card, style: .continuous)
                .fill(right ? YubaiColor.amberTint : YubaiColor.neutralSoft)
                .overlay(alignment: right ? .leading : .trailing) {
                    Text(right ? "以后别提" : "知道了")
                        .yubaiFont(YubaiFont.callout, weight: .medium)
                        .foregroundStyle(right ? YubaiColor.amberInk : YubaiColor.label)
                        .padding(.horizontal, 22).opacity(labelOpacity)
                }.opacity(drag == 0 || (drag > 0 && onMute == nil) ? 0 : 1)
                .allowsHitTesting(false).accessibilityHidden(true)
            content { action in finish(direction: -1, action: action) }
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(max(-1, min(1, drag / width))) * 6))
                .offset(x: drag).opacity(opacity)
                .allowsHitTesting(!departing && drag == 0)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(1, $0) }
        .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.card))
        #if os(iOS)
        .gesture(HorizontalPan(shouldBegin: { _ in !departing }, changed: changeDrag,
                               ended: endDrag, cancelled: resetDrag))
        #else
        .simultaneousGesture(DragGesture(minimumDistance: 18)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard !departing else { return }
                if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.3 }
                guard horizontal == true else { return }
                changeDrag(value.translation.width)
            }.onEnded { value in
                guard horizontal == true else { return }
                horizontal = nil
                endDrag(value.translation.width, value.velocity.width)
            })
        .onChange(of: dragging) { _, active in
            if !active { horizontal = nil; if !departing { resetDrag() } }
        }
        #endif
        .accessibilityElement(children: .contain)
        .modifier(SwipeRevealValue(enabled: reportsRevealState, revealed: drag != 0))
        .accessibilityAction(named: "知道了") { finish(direction: -1, action: onDismiss) }
    }
    private func changeDrag(_ distance: CGFloat) {
        guard !departing else { return }
        interacted = true; nudging = false
        drag = distance > 0 && onMute == nil ? min(6, distance * 0.04) : distance
        let direction = abs(drag) >= threshold ? (drag < 0 ? -1 : 1) : 0
        if direction != 0 && direction != armedDirection { thresholdTrigger &+= 1 }
        armedDirection = direction
    }
    private func endDrag(_ distance: CGFloat, _ velocity: CGFloat) {
        guard !departing else { return }
        let right = distance > 0
        guard !right || onMute != nil else { resetDrag(); return }
        if abs(distance) >= threshold || (abs(velocity) > 650 && abs(distance) > 20) {
            finish(direction: right ? 1 : -1, action: right ? (onMute ?? onDismiss) : onDismiss)
        } else { resetDrag() }
    }
    private func resetDrag() {
        guard !departing else { return }
        nudging = false; armedDirection = 0
        withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { drag = 0 }
    }
    private func finish(direction: CGFloat, action: @escaping () -> Bool) {
        guard !departing else { return }
        interacted = true; nudging = false; departing = true
        withAnimation(YubaiMotion.dismiss(reduceMotion: reduceMotion)) {
            if reduceMotion { opacity = 0 }
            else { drag = direction * width * 1.5 }
        } completion: {
            withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) {
                if !action() { departing = false; opacity = 1; drag = 0; armedDirection = 0 }
            }
        }
    }
}

private struct SwipeRevealValue: ViewModifier {
    let enabled: Bool
    let revealed: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.uiTestAccessibilityValue(revealed ? "revealed" : "closed") }
        else { content }
    }
}

struct ButlerListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var unknownInflowsOnly = false
    var body: some View {
        let cards = unknownInflowsOnly
            ? store.butlerVisibility.queued.filter { $0.kind == .unknownInflow }
            : store.butlerVisibility.visible
        Page(spacing: YubaiSpace.gapGroup) {
            ForEach(cards) { card in
                if let question = card.importQuestion, let batch = store.imports.first(where: { $0.undoneAt == nil && $0.organization?.questions.contains(where: { $0.id == question.id }) == true }) {
                    ImportQuestionCard(question: question, batchID: batch.id, cardID: card.id)
                } else { ButlerCardView(card: card).transition(YubaiMotion.cardTransition(reduceMotion: reduceMotion)) }
            }
            if !store.mutedTopics.isEmpty {
                Text("说过「以后别提」的：\(store.mutedTopics.count) 类").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
        }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: cards.map(\.id)).navigationTitle("需要留意").yubaiNavigation()
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
        SwipeDismissCard(onDismiss: { store.dismissCard(card.id) }, onMute: { store.muteCard(card.id) }, nudgesOnce: nudgesOnce) { animateDismiss in
            cardContent(animateDismiss: animateDismiss)
        }.accessibilityIdentifier("butlerCard_" + card.kind.rawValue)
    }
    private func cardContent(animateDismiss: @escaping CardDismissAnimation) -> some View {
        Card(style: .compact, background: amber ? YubaiColor.amberTint : YubaiColor.paperSheet) {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                HStack(spacing: YubaiSpace.space8) {
                    if amber { Circle().fill(YubaiColor.amberDot).frame(width: 6, height: 6).accessibilityHidden(true) }
                    Text(meta).yubaiFont(YubaiFont.meta).foregroundStyle(ink)
                    Spacer(minLength: YubaiSpace.none)
                }.frame(minHeight: YubaiSize.pillHeight)
                Text(hidden ? "需要留意" : card.title).yubaiFont(YubaiFont.cardTitle)
                    .foregroundStyle(amber ? YubaiColor.amberStrong : YubaiColor.label)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("butlerTitle_" + card.kind.rawValue)
                Button { store.present(.cardEvidence(card.id), from: "card-" + card.id.uuidString) } label: {
                    Text(evidenceText)
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).multilineTextAlignment(.leading)
                }.buttonStyle(PressButtonStyle()).frame(minHeight: YubaiSize.tapMin, alignment: .leading)
                if exceedsRestraint {
                    ProfileChatEntry(title: "调一下额度", context: .restrainExceeded(card.title + " · " + card.body))
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
                if card.kind == .shortfall { store.present(.ask("接下来的付款有缺口，帮我看看怎么挪。" + card.title), from: "card-" + card.id.uuidString) }
                else { store.sheetSource = "card-" + card.id.uuidString; store.performCardAction(card) }
            }.buttonStyle(ButlerActionStyle(amber: amber))
        }
    }
    @ViewBuilder private var more: some View {
        if additionalCount > 0 {
            TabNavigationLink(.butlerCards) { ButlerListView() } label: { Text("还有 \(additionalCount) 件 ›").yubaiFont(YubaiFont.caption) }
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
                            Button("查看接下来要付") { store.sheet = nil; store.destination = .overview }
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
    var body: some View {
        Page(topPadding: YubaiSpace.gapGroup) {
            if let card = store.cards.first(where: { $0.id == cardID }) { WeeklyLetterCard(card: card) }
            else { Text("这封每周来信已移除。") }
        }.navigationTitle("每周来信").yubaiNavigation()
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
            if let facts = card.letter, !store.preferences.hideAmounts {
                letterChart(facts)
                letterNumbers(facts)
            }
            Button("明细：\(card.evidence.count) 笔 ›") { store.sheet = .cardEvidence(card.id) }
                .yubaiFont(YubaiFont.caption).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.tapMin).background(YubaiColor.raised, in: Capsule())
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
                SectionHeading(title: "还能花这一周", meta: "每日收盘回算")
                ChartGrow(key: "letter-chart-" + card.id.uuidString) { progress in LetterChart(points: facts.series, progress: progress) }
            }
        }
    }
    private func letterNumbers(_ facts: LetterFacts) -> some View {
        let layout: AnyLayout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.gapGroup)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        let numbers: [CardFact] = Array(facts.numbers.prefix(3))
        return layout {
            ForEach(Array(numbers.enumerated()), id: \.offset) { _, fact in letterNumber(fact) }
        }
    }
    private func letterNumber(_ fact: CardFact) -> some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(fact.label).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                Text(fact.value).yubaiFont(YubaiFont.amountCard).numberTransition(value: Double(fact.cents ?? 0) / 100)
            }
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
                    LetterDetailView(cardID: card.id)
                } label: {
                    HStack(spacing: YubaiSpace.gapGroup) { Text(card.title); Spacer(); Text(Dates.text(card.createdAt)).foregroundStyle(YubaiColor.labelSecondary) }
                        .yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("每周来信").yubaiNavigation().manualSheetHeader("每周来信", cancelTitle: "关闭", showsAction: false)
    }
}
