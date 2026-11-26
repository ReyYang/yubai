import SwiftUI
import YubaiCore

/// Conversation and global management, with current facts beside each route.
struct YubaiTabView: View {
    var asDestination = false
    @Environment(AppStore.self) private var store
    @State private var input = ""
    @State private var repeatCount = 0
    @FocusState private var focused: Bool
    private let suggestions = ["这个能买吗", "这个月钱去哪了"]
    var body: some View {
        Page(spacing: YubaiSpace.space12, topPadding: YubaiSpace.space8, identifier: "yubaiScroll", rootTab: .yubai) {
            askArea
            if !store.inboxItems.isEmpty {
                Card(style: .list) {
                    destination(.todo, "待办", detail: "\(store.inboxItems.count) 件", id: "openButlerInbox")
                }
            }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    paydayEntry
                    EntryFormDivider()
                    destination(.saving, "存钱", detail: savingStatus, id: "openSaving")
                    EntryFormDivider()
                    destination(.fixedFlows, "会回来的账单", detail: billStatus, id: "openFixedFlows")
                }
            }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    destination(.wishlist, "心愿单", detail: wishStatus, id: "openWishlist")
                    EntryFormDivider()
                    destination(.weekly(nil), "每周来信", detail: latestLetter, id: "openWeekly")
                    EntryFormDivider()
                    destination(.profile, "消费观", detail: restraintStatus, id: "openProfile")
                    EntryFormDivider()
                    destination(.memories, "余白记得的", detail: "\(store.settingsSummary.memoryCount) 条", id: "openMemories")
                }
            }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    destination(.frequent, "常用", detail: "\(repeatCount) 个", id: "openFrequentEntries")
                    EntryFormDivider()
                    destination(.accounts, "账户", detail: accountStatus, id: "openAccounts")
                    EntryFormDivider()
                    destination(.imports, "导入账单", id: "openImports")
                    EntryFormDivider()
                    if !asDestination { destination(.settings, "设置", id: "openSettings") }
                }
            }
        }.rootScrollContentMargins(for: .yubai)
            .rootPageHeader { if !asDestination { RootHeader(title: "余白") } }
            .amountPrivacy(store.preferences.hideAmounts).navigationTitle("余白").yubaiNavigation()
            #if os(iOS)
            .toolbar(asDestination ? .visible : .hidden, for: .navigationBar)
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
                    CategoryChoiceChip(title: text) { openQuestion(text) }
                        .accessibilityIdentifier("askSuggestion_\(index)")
                }
            }
        }.padding(.bottom, YubaiSpace.space4)
    }
    private var paydayEntry: some View {
        var ledger = store.current
        ledger.plans.removeAll { $0.frequency != .monthly }
        let plan = Finance.anchorPlan(in: ledger, now: store.financialNow)
        let day = plan.map { $0.monthlyDay ?? Dates.calendar.component(.day, from: $0.dueDate) }
        return hubRow("发薪日与工资", detail: day.map { "每月 \($0) 号" } ?? "未设置", id: "openPaydaySetup") {
            if let plan { store.tabRouteRequest = .billDetail(plan.id) }
            else { store.sheetSource = nil; store.sheet = .paydaySetup }
        }
    }
    private func destination(_ route: TabRoute, _ title: String, detail: String = "", id: String) -> some View {
        hubRow(title, detail: detail, id: id) { store.tabRouteRequest = route }
    }
    private func hubRow(_ title: String, detail: String, id: String, action: @escaping () -> Void) -> some View {
        Button { focused = false; action() } label: {
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
        let saved = store.homeSaving.total
        let funded = wishes.filter { $0.amount <= saved }.min { $0.amount < $1.amount }
        return "\(wishes.count) 个" + (funded.map { " · " + $0.title + "够了" } ?? "")
    }
    private var latestLetter: String {
        store.cards.filter { $0.kind == .weeklyLetter }.map(\.createdAt).max().map(FixedFlowPresentation.monthDay) ?? ""
    }
    private var restraintStatus: String {
        let count = store.current.profile.restrain.count
        return count == 0 ? "" : "盯住 \(count) 类"
    }
    private var savingStatus: String {
        store.homeSaving.started ? amount2(store.homeSaving.total, hide: store.preferences.hideAmounts) : ""
    }
    private var accountStatus: String {
        "\(store.accounts.filter { !$0.archived }.count) 个"
    }
    private var billStatus: String {
        let count = store.formula.billCount
        return "这一期还有 \(count) 样"
    }
    private func ask() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        openQuestion(text)
    }
    private func openQuestion(_ text: String) {
        focused = false
        store.tabRouteRequest = .askQuestion(text)
    }
}
