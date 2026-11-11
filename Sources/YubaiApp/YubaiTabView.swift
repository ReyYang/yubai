import SwiftUI
import YubaiCore

/// 余白：最近问过的、我的消费观、余白记得的；输入框和三句常问的贴在底栏上方。
struct YubaiTabView: View {
    private struct AskTarget: Hashable { var text: String; var send: Bool }
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var input = ""
    @State private var target: AskTarget?
    @FocusState private var focused: Bool
    private let suggestions = ["这个能买吗", "这个月钱去哪了", "帮我记一笔"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
                recentSection
                valuesCard
                memoriesRow
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.rootScrollContentMargins().rootTabScroll(.yubai)
            .rootPageHeader { RootHeader(title: "余白") }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) { askArea }
            .amountPrivacy(store.preferences.hideAmounts)
            .navigationDestination(item: $target) { destination in
                AskYubaiView(initialText: destination.text, autoSend: destination.send)
            }
            .navigationTitle("余白").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }

    // MARK: 最近问过的
    @ViewBuilder private var recentSection: some View {
        let questions = Array(store.recentQuestions.prefix(5))
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                Text("最近问过的").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    .padding(.horizontal, YubaiSpace.space4)
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                            questionRow(question, index: index)
                            if index < questions.count - 1 { EntryFormDivider() }
                        }
                    }
                }
            }
        }
    }
    private func questionRow(_ question: (text: String, date: Date), index: Int) -> some View {
        Button { target = AskTarget(text: question.text, send: true) } label: {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text(question.text).yubaiFont(YubaiFont.row).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Text(dayText(question.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                chevron
            }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("recentQuestion_\(index)")
            .accessibilityLabel(question.text + "，" + dayText(question.date))
    }
    private func dayText(_ date: Date) -> String {
        let calendar = Dates.calendar
        let days = calendar.dateComponents([.day], from: Dates.day(date), to: Dates.day(Date())).day ?? 0
        if days <= 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 7 { return date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))) }
        return FixedFlowPresentation.monthDay(date)
    }

    // MARK: 我的消费观
    private var valuesCard: some View {
        let profile = store.profile
        return TabNavigationLink(.profile) { ProfileView() } label: {
            Card {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text("我的消费观").yubaiFont(YubaiFont.cardTitle)
                        Spacer(minLength: YubaiSpace.space8)
                        chevron
                    }
                    valueLine("想克制", profile.restrain.map(\.title).joined(separator: "、"))
                    valueLine("愿意多花", profile.generous.map(\.title).joined(separator: "、"))
                    valueLine("原则", profile.principles.first ?? "")
                }
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openProfile")
    }
    @ViewBuilder private func valueLine(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .top, spacing: YubaiSpace.gapGroup))
            layout {
                Text(title).foregroundStyle(YubaiColor.labelSecondary).frame(minWidth: textSize.isAccessibilitySize ? 0 : 64, alignment: .leading)
                Text(value).multilineTextAlignment(.leading)
            }.yubaiFont(YubaiFont.callout)
        }
    }

    // MARK: 余白记得的
    private var memoriesRow: some View {
        let count = "\(store.settingsSummary.memoryCount) 条"
        return TabNavigationLink(.memories) { MemoryView() } label: {
            Card(style: .list) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text("余白记得的").yubaiFont(YubaiFont.rowTitle)
                    Spacer(minLength: YubaiSpace.space8)
                    Text(count).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    chevron
                }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openMemories")
            .accessibilityLabel("余白记得的，" + count)
    }

    // MARK: 输入
    private var askArea: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            ChipFlow {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, text in
                    SuggestionChip(value: text, identifier: "askSuggestion_\(index)") { choose(text, send: index == 1) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            field
        }.padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSize.rootBottomPadding - YubaiSpace.gapGroup)
    }
    private var field: some View {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: YubaiSpace.gapGroup) {
            AssistantMark(size: 16).accessibilityHidden(true)
            TextField("问一句", text: $input).focused($focused).submitLabel(.send).onSubmit { ask(trimmed) }
                .yubaiFont(YubaiFont.body).accessibilityLabel("问余白").accessibilityIdentifier("askYubai")
            if !trimmed.isEmpty {
                Button { ask(trimmed) } label: {
                    Image(systemName: "arrow.up").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.onBrand)
                        .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton).background(YubaiColor.brand, in: Circle()).yubaiHitTarget()
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("发送").accessibilityIdentifier("sendAskHome")
            }
        }.padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.buttonHeight)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
    }
    private func choose(_ text: String, send: Bool) {
        if send { target = AskTarget(text: text, send: true) }
        else { input = text; focused = true }
    }
    private func ask(_ text: String) {
        guard !text.isEmpty else { return }
        input = ""; focused = false
        target = AskTarget(text: text, send: true)
    }
    private var chevron: some View {
        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
    }
}
