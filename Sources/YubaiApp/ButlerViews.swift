import SwiftUI
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
                    Image(systemName: "xmark").font(.system(size: YubaiFont.callout.size)).foregroundStyle(YubaiColor.labelSecondary)
                        .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).padding(YubaiSpace.space4).accessibilityLabel("收起").accessibilityIdentifier("dismissLetterCard")
            }
            .accessibilityAction(named: "收起") { _ = onDismiss() }
            .accessibilityAction(named: "以后别提") { _ = onMute?() }
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
        return Page(spacing: YubaiSpace.space16, topPadding: YubaiSpace.space8) {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    ForEach(Array(letter.numbers.enumerated()), id: \.offset) { index, fact in
                        factRow(fact)
                        if index < letter.numbers.count - 1 { EntryFormDivider() }
                    }
                }
            }
            Card(style: .list) {
                DisclosureGroup {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(letter.series) { point in
                            factRow(CardFact(FixedFlowPresentation.monthDay(point.date), cents: point.available))
                            if point.id != letter.series.last?.id { EntryFormDivider() }
                        }
                    }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text("每天收盘还能花"); Spacer(); Text("\(letter.series.count) 天").foregroundStyle(YubaiColor.labelSecondary) }
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text("每天收盘还能花"); Text("\(letter.series.count) 天").foregroundStyle(YubaiColor.labelSecondary) }
                    }.yubaiFont(YubaiFont.callout).frame(minHeight: YubaiSize.headerHeight)
                }.tint(YubaiColor.labelSecondary).accessibilityIdentifier("weeklyDailyAvailable")
            }
            Text("这一周的 \(rows.count) 笔").yubaiFont(YubaiFont.callout, weight: .semibold)
                .foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.space16)
            ForEach(days.keys.sorted(by: >), id: \.self) { date in
                let entries = days[date] ?? []
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    HStack {
                        Text(FixedFlowPresentation.monthDay(date)).yubaiFont(YubaiFont.callout, weight: .semibold)
                        Spacer()
                        AmountLabel(cents: entries.reduce(0) { $0 + ($1.nature.inflow ? $1.amount : -$1.amount) }, hide: store.preferences.hideAmounts, role: .day)
                    }.foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.space16)
                    CardRows(entries) { entry in EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts) }
                }
            }
        }
            .navigationTitle("依据").yubaiNavigation()
    }
    private func factRow(_ fact: CardFact) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { Text(fact.label).yubaiFont(YubaiFont.row).fixedSize(); Spacer(minLength: YubaiSpace.space8); factAmount(fact).fixedSize() }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text(fact.label).yubaiFont(YubaiFont.row); factAmount(fact) }
        }.frame(minHeight: YubaiSize.headerHeight)
    }
    private func factAmount(_ fact: CardFact) -> some View {
        Text(store.preferences.hideAmounts && fact.cents != nil ? "••••" : fact.value)
            .yubaiFont(YubaiFont.amountSmall).lineLimit(1).minimumScaleFactor(0.7)
    }
    private var genericPage: some View {
        Page {
            if let card = store.cards.first(where: { $0.id == cardID }) {
                Text(store.preferences.hideAmounts ? "依据" : card.title).yubaiFont(YubaiFont.lead)
                Text("依据生成于 " + Dates.text(card.createdAt, time: true)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        ForEach(Array((card.facts ?? []).enumerated()), id: \.offset) { _, fact in
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                Text(fact.label).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                Text(store.preferences.hideAmounts && fact.cents != nil ? "••••" : fact.value).yubaiFont(YubaiFont.body)
                            }
                        }
                        if card.kind == .shortfall {
                            Button("查看接下来要付") { store.sheet = nil; store.destination = .now }
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
        }.navigationTitle("依据").yubaiNavigation().manualSheetHeader("依据", cancelTitle: "关闭", showsAction: false).accessibilityIdentifier("butlerEvidencePage")
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
                        Card(style: .list) { CardTextFieldRow(title: "用途", text: $text, identifier: "importQuestionPurpose", multiline: true, autofocus: true) }
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
                .frame(maxWidth: YubaiSize.contentMaximum).frame(maxWidth: .infinity)
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
                ProposalCard(title: store.preferences.hideAmounts ? "余白的建议" : change.reason, lines: store.preferences.hideAmounts ? [] : change.preview(in: store.current, showPreviousValues: true), primaryTitle: Set(change.items.flatMap(\.entryIDs)).isEmpty ? "改好这 \(change.items.count) 项" : "改好这 \(Set(change.items.flatMap(\.entryIDs)).count) 笔", canConfirm: !store.preferences.hideAmounts, confirm: {
                    if store.apply(change, label: "余白的建议") { dismiss() }
                }, cancel: {
                    if store.update("不改了", { ledger in
                        ledger.pendingChanges.removeAll { $0.id == change.id }
                        for i in ledger.cards.indices where ledger.cards[i].action == .confirmChangeSet(change.id) {
                            ledger.cards[i].dismissedAt = Date()
                        }
                    }) { dismiss() }
                })
            } else { Text("这份修改已经处理过了。") }
        }.navigationTitle("余白的建议").yubaiNavigation().manualSheetHeader("余白的建议", cancelTitle: "关闭", showsAction: false).accessibilityIdentifier("butlerProposalPage")
    }
}

struct LetterDetailView: View {
    @Environment(AppStore.self) private var store
    let cardID: UUID
    var body: some View {
        WeeklyReviewView()
            .onAppear {
                if store.cards.first(where: { $0.id == cardID })?.dismissedAt == nil {
                    store.update("读过周回顾", recordUndo: false) { ledger in
                        if let i = ledger.cards.firstIndex(where: { $0.id == cardID }) { ledger.cards[i].dismissedAt = Date() }
                    }
                }
            }
    }
}
