import SwiftUI
import YubaiCore

/// Conversation and global management, with current facts beside each route.
struct YubaiTabView: View {
    @Environment(AppStore.self) private var store
    @State private var input = ""
    @State private var repeatCount = 0
    @FocusState private var focused: Bool
    private let suggestions = ["这个能买吗", "这个月钱去哪了"]
    var body: some View {
        Page(spacing: YubaiSpace.space12, topPadding: YubaiSpace.space8, identifier: "yubaiScroll") {
            askArea
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    destination(.wishlist, "心愿单", detail: wishStatus, id: "openWishlist")
                    EntryFormDivider()
                    destination(.weekly(nil), "每周来信", detail: latestLetter, id: "openWeekly")
                    EntryFormDivider()
                    destination(.profile, "消费观", detail: store.profile.restrain.isEmpty ? "" : "盯住 \(store.profile.restrain.count) 类", id: "openProfile")
                    EntryFormDivider()
                    destination(.memories, "余白记得的", detail: "\(store.settingsSummary.memoryCount) 条", id: "openMemories")
                }
            }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    destination(.accounts, "账户", detail: accountStatus, id: "openAccounts")
                    EntryFormDivider()
                    destination(.fixedFlows, "会回来的账单", detail: billStatus, id: "openFixedFlows")
                    EntryFormDivider()
                    destination(.frequent, "常用", detail: "\(repeatCount) 个", id: "openFrequentEntries")
                }
            }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    destination(.imports, "导入账单", id: "openImports")
                    EntryFormDivider()
                    destination(.backup, "备份", detail: store.preferences.lastBackupAt.map(dayText) ?? "", id: "openBackup")
                    EntryFormDivider()
                    destination(.settings, "设置", id: "openSettings")
                }
            }
        }.rootScrollContentMargins(for: .yubai).rootTabScroll(.yubai)
            .rootPageHeader { RootHeader(title: "余白") }
            .amountPrivacy(store.preferences.hideAmounts).navigationTitle("余白").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .task(id: store.ledgerRevision) {
                let ledger = store.current, now = store.financialNow
                let count = await Task.detached(priority: .userInitiated) { EntryHistory.repeats(in: ledger, now: now, limit: 1000).count }.value
                guard !Task.isCancelled else { return }; repeatCount = count
            }
    }
    private var askArea: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            ChatInputBar(text: $input, placeholder: "问余白", accessibilityLabel: "问余白", inputID: "askYubai", sendID: "sendAskHome",
                         showSend: !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, focus: $focused, send: ask) {
                AssistantMark(size: YubaiFont.navTitle.size).accessibilityHidden(true)
            } accessory: { EmptyView() }
            ChipFlow {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, text in
                    CategoryChoiceChip(title: text) {
                        if index == 1 { store.tabRouteRequest = .askQuestion(text) }
                        else { input = text; focused = true }
                    }.accessibilityIdentifier("askSuggestion_\(index)")
                }
            }
        }.padding(.bottom, YubaiSpace.space4)
    }
    private func destination(_ route: TabRoute, _ title: String, detail: String = "", id: String) -> some View {
        Button { focused = false; store.tabRouteRequest = route } label: {
            AdaptiveValueRow {
                Text(title).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label)
            } value: {
                HStack(spacing: YubaiSpace.space6) {
                    if !detail.isEmpty {
                        Text(store.preferences.hideAmounts ? HomeButler.privacyText(detail, hidden: true) : detail)
                            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                }
            }.frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(id)
    }
    private var wishStatus: String {
        let wishes = store.current.wishlist.filter { $0.status == .thinking }
        guard !wishes.isEmpty else { return "0 个" }
        let saved = LedgerHomeModel.make(store).savedTotal ?? 0
        let funded = wishes.filter { $0.amount <= saved }.min { $0.amount < $1.amount }
        return "\(wishes.count) 个" + (funded.map { " · " + $0.title + "够了" } ?? "")
    }
    private var latestLetter: String {
        store.cards.filter { $0.kind == .weeklyLetter }.map(\.createdAt).max().map(FixedFlowPresentation.monthDay) ?? ""
    }
    private var accountStatus: String {
        let date = store.current.lastReconciledAt
        return "对一下余额" + (date.map { " · 上次 " + FixedFlowPresentation.monthDay($0) } ?? "")
    }
    private var billStatus: String {
        let count = store.formula.billCount
        return "这一期还有 \(count) 样"
    }
    private func dayText(_ date: Date) -> String {
        if Dates.calendar.isDate(date, inSameDayAs: store.financialNow) { return "今天" }
        if Dates.calendar.isDate(date, inSameDayAs: Dates.addDays(-1, to: store.financialNow)) { return "昨天" }
        return FixedFlowPresentation.monthDay(date)
    }
    private func ask() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""; focused = false; store.tabRouteRequest = .askQuestion(text)
    }
}
