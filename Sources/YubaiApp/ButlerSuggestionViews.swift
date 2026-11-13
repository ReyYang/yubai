import SwiftUI
import YubaiCore

@MainActor extension AppStore {
    @discardableResult func answerSuggestion(_ suggestion: ButlerSuggestion, _ answer: ButlerSuggestionAnswer) -> Bool {
        let plan: Plan?
        if case .accept = answer, case .stopSubscription(let id) = suggestion.action { plan = current.plans.first { $0.id == id } }
        else { plan = nil }
        let saved = update("管家的建议", entryMotion: false, showToast: false) {
            try ButlerSuggestions.answer(suggestion.id, answer, in: &$0, now: financialNow)
        }
        if saved, let plan {
            let provider = plan.title.replacingOccurrences(of: "会员", with: "")
            homeReceipt = ButlerReceipt(title: "已停掉", amount: nil, nextStep: "记得去\(provider) App 里取消续费", undoLabel: undoLabel)
        }
        return saved
    }
}

struct ButlerSuggestionCard: View {
    @Environment(AppStore.self) private var store
    let suggestion: ButlerSuggestion
    var more = 0
    var body: some View {
        QuestionCard(eyebrow: "余白看了这 4 周", title: suggestion.text(suggestion.observation + suggestion.proposal, hidden: store.preferences.hideAmounts),
                     more: more, evidenceTitle: "看这 \(suggestion.count) 笔", onEvidence: { store.tabRouteRequest = .butlerEvidence(suggestion.id) }, titleIdentifier: "butlerAIText",
                     yesTitle: suggestion.action.title, noTitle: suggestion.action == .neverMention ? "" : "不用",
                     yesIdentifier: "butlerAIAccept", noIdentifier: "butlerAINever",
                     yes: { store.answerSuggestion(suggestion, .accept) }, no: { store.answerSuggestion(suggestion, .never) })
            .accessibilityElement(children: .contain).accessibilityIdentifier("butlerSuggestionCard")
    }
}

struct ButlerSuggestionActions: View {
    @Environment(AppStore.self) private var store
    let suggestion: ButlerSuggestion
    var showIncorrect = false
    var finished: () -> Void = {}
    @State private var correcting = false
    var body: some View {
        ChipFlow {
            Button(suggestion.action.title) { if store.answerSuggestion(suggestion, .accept) { finished() } }
                .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("butlerAIAccept")
            if suggestion.action != .neverMention {
                Button("不用") { if store.answerSuggestion(suggestion, .never) { finished() } }
                    .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("butlerAINever")
            }
            if showIncorrect {
                Button("说得不对") { correcting = true }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("butlerAIIncorrect")
            }
        }.accessibilityElement(children: .contain).sheet(isPresented: $correcting) {
            ButlerSuggestionCorrection(suggestion: suggestion) { correcting = false; finished() }
                .environment(store).appErrors().yubaiSheetBackground()
        }
    }
}

struct ButlerSuggestionEvidence: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let suggestionID: UUID
    private var suggestion: ButlerSuggestion? {
        store.current.butlerAI?.suggestions.first {
            $0.id == suggestionID && $0.answeredAt == nil && ButlerSuggestionVerifier.verify($0, in: store.current, now: store.financialNow)
        }
    }
    private var unavailableTitle: String {
        store.current.butlerAI?.suggestions.contains { $0.id == suggestionID && $0.answeredAt == nil } == true ? "这条建议的依据已变" : "这条建议已处理"
    }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            if let suggestion {
                Text(suggestion.text(suggestion.observation, hidden: store.preferences.hideAmounts))
                    .yubaiFont(YubaiFont.butlerTitle, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("butlerEvidenceTitle")
                ButlerEvidenceEntries(suggestion: suggestion)
                let notes = store.current.memories.filter { suggestion.memoryIDs.contains($0.id) }
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                        SectionHeading(title: "余白记得的")
                        CardRows(notes) { note in
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                Text(store.preferences.hideAmounts ? "金额已隐藏" : "「" + note.text + "」")
                                    .yubaiFont(YubaiFont.cardTitle).fixedSize(horizontal: false, vertical: true)
                                Text(FixedFlowPresentation.monthDay(note.updatedAt) + " 你说的")
                                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            }.padding(.vertical, YubaiSpace.space12)
                        }.accessibilityElement(children: .contain).accessibilityIdentifier("butlerEvidenceMemories")
                    }
                }
            } else {
                EmptyState("doc.questionmark", unavailableTitle, action: "返回", onAction: { dismiss() })
            }
        }.safeAreaInset(edge: .bottom) {
            if let suggestion {
                ButlerSuggestionActions(suggestion: suggestion, showIncorrect: true, finished: { dismiss() })
                    .padding(YubaiSpace.insetPage).frame(maxWidth: .infinity, alignment: .leading).background(YubaiColor.canvas)
            }
        }.amountPrivacy(store.preferences.hideAmounts).navigationTitle("为什么这么说").yubaiNavigation()
            .accessibilityElement(children: .contain).accessibilityIdentifier("butlerAIEvidencePage")
    }
}

private struct ButlerEvidenceEntries: View {
    @Environment(AppStore.self) private var store
    let suggestion: ButlerSuggestion
    var all = false
    private var rows: [Entry] {
        store.current.activeEntries.filter { suggestion.entryIDs.contains($0.id) }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
    }
    var body: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                ForEach(Array((all ? rows : Array(rows.prefix(4))).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { EntryFormDivider() }
                    TabNavigationLink(.entryDetail(entry.id)) { EntryDetailView(entryID: entry.id) } label: { row(entry) }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("butlerEvidenceEntry_" + entry.id.uuidString)
                }
                if !all && rows.count > 4 {
                    EntryFormDivider()
                    TabNavigationLink(.butlerEvidenceEntries(suggestion.id)) {
                        ButlerSuggestionEntriesPage(suggestionID: suggestion.id)
                    } label: { SettingsRow(title: "还有 \(rows.count - 4) 笔", chevron: true) }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("butlerEvidenceMore")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("butlerEvidenceEntries")
    }
    private func row(_ entry: Entry) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { date(entry); title(entry); amount(entry) }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                date(entry)
                HStack(spacing: YubaiSpace.space8) { title(entry); amount(entry) }
            }
        }.padding(.vertical, YubaiSpace.space12).frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
    }
    private func date(_ entry: Entry) -> some View {
        Text(FixedFlowPresentation.monthDay(entry.date) + " " + entry.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))))
            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
    }
    private func title(_ entry: Entry) -> some View {
        Text(entry.displayTitle).yubaiFont(YubaiFont.row).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("truncatableName")
    }
    private func amount(_ entry: Entry) -> some View {
        AmountLabel(cents: Finance.spendingAmount(entry, ledger: store.current), hide: store.preferences.hideAmounts, sign: .outflow).fixedSize(horizontal: false, vertical: true)
    }
}

struct ButlerSuggestionEntriesPage: View {
    @Environment(AppStore.self) private var store
    let suggestionID: UUID
    var body: some View {
        Page {
            if let suggestion = store.current.butlerAI?.suggestions.first(where: { $0.id == suggestionID }) {
                ButlerEvidenceEntries(suggestion: suggestion, all: true)
            }
        }.navigationTitle("这几笔").yubaiNavigation()
    }
}

private struct ButlerSuggestionCorrection: View {
    @Environment(AppStore.self) private var store
    let suggestion: ButlerSuggestion
    let finished: () -> Void
    @State private var sentence = ""
    var body: some View {
        Form {
            Section {
                CardTextFieldRow(title: "说一句", text: $sentence, identifier: "butlerAICorrectionText", multiline: true)
                InlineFieldError(message: sentence.count > 200 || sentence.contains(where: { $0.isNewline }) ? "请用一行、不超过 200 字" : nil)
            }.listRowBackground(YubaiColor.card)
        }.editorForm().manualSheetHeader("说得不对", actionTitle: "记下", enabled: sentence.count <= 200 && !sentence.contains(where: { $0.isNewline }), actionIdentifier: "butlerAICorrectionSave", action: {
            if store.answerSuggestion(suggestion, .incorrect(sentence)) { finished() }
        })
    }
}

struct ButlerSuggestionReviewCard: View {
    @Environment(AppStore.self) private var store
    let review: ButlerReview
    var more = 0
    var body: some View {
        QuestionCard(eyebrow: "两周到了", title: question, more: more, yesTitle: "试过了", noTitle: "不用",
                     yesIdentifier: "butlerAIReviewDone", noIdentifier: "butlerAIReviewNever",
                     yes: { answer(false) }, no: { answer(true) }).accessibilityIdentifier("butlerAIReviewCard")
    }
    private var question: String {
        if case .tryTwoWeeks(let text) = review.suggestion.action { return HomeButler.privacyText(text, hidden: store.preferences.hideAmounts) }
        return review.suggestion.text(review.suggestion.proposal, hidden: store.preferences.hideAmounts)
    }
    private func answer(_ never: Bool) {
        store.update("两周回看", entryMotion: false, showToast: false) { try ButlerSuggestions.answerReview(review.id, never: never, in: &$0, now: store.financialNow) }
    }
}
