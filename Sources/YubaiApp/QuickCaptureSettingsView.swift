import SwiftUI
import YubaiCore
#if os(iOS)
import UserNotifications
#endif

/// Canvas S-Quick 快速记账: what the entrances recorded this week, each entrance with its own count and
/// 添加 (opens 快捷指令), then the two lists the entrances use. Whether a shortcut is installed is not
/// something iOS tells the app, so it is never shown as a state.
struct QuickCaptureSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var askingToOpen = false
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @State private var notifications: UNAuthorizationStatus?
    #endif

    var body: some View {
        let _ = SettingsRenderCounts.hit("quickBody")
        let stats = store.quickCaptureStats
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "快速记账")
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s20) {
                    HStack(alignment: .top, spacing: .zero) {
                        statistic("近 7 天快速记下", count: stats.recent).dsFillWidth()
                        statistic("没打开余白", count: stats.withoutOpening).dsFillWidth()
                    }.padding(.horizontal, DS.Space.s4)
                    DSSettingsCard(leading: DS.Space.s16) {
                        entrance(.acctCredit, "Apple Pay 付完就记", count: stats.applePay,
                                 first: true, id: "quickApplePay")
                        #if os(iOS)
                        notifyRow
                        #endif
                        entrance(.send, "Siri", count: stats.siri, first: false, id: "quickSiri")
                    }
                    DSSettingsCard(leading: DS.Space.s16) {
                        link(.acctCredit, "卡对应的账户", "\(stats.cards.count.formatted()) 张", first: true, id: "openCaptureCardRules") {
                            store.tabRouteRequest = .quickCards
                        }
                        link(.recategorize, "商户记到哪个分类", "\(store.merchantRules.count.formatted()) 条", first: false, id: "openCaptureMerchantRules") {
                            store.tabRouteRequest = .quickMerchants
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s8).padding(.bottom, DS.Space.s28)
            }.scrollIndicators(.hidden).accessibilityIdentifier("quickCaptureScroll")
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .dsEdgeSwipeBack()
        // Canvas S-Quick-Open: the system's own question before leaving for 快捷指令.
        .alert("要打开「快捷指令」吗？", isPresented: $askingToOpen) {
            Button("取消", role: .cancel) {}
            Button("打开") { openURL(URL(string: "shortcuts://")!) }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        // Read again on return from 设置, where the person may have just turned it on.
        .task(id: scenePhase) { if scenePhase == .active { await readNotifications() } }
        #endif
    }

    #if os(iOS)
    /// 记下后通知: what iOS says, and the one thing to do about it — ask, send to 设置, or nothing.
    private var notifyRow: some View {
        let on = notifications.map { [.authorized, .provisional, .ephemeral].contains($0) } ?? false
        let denied = notifications == .denied
        return Button {
            if denied {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            } else if notifications == .notDetermined {
                Task { _ = await CaptureNotifications.requestPermission(); await readNotifications() }
            }
        } label: {
            HStack(spacing: DS.Space.s12) {
                DSIconView(icon: .bell, size: DS.Size.icon, color: DS.Color.accentInk)
                Text("记下后通知").dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink).dsFillWidth()
                if on {
                    Text("已开").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink3)
                } else if notifications != nil {
                    Text(denied ? "去设置" : "打开").dsText(SettingsSpec.pillLabel).foregroundStyle(DS.Color.accentInk)
                        .padding(.horizontal, SettingsSpec.pillInset).frame(height: SettingsSpec.pillHeight)
                        .dsPill(DS.Color.accentSoft)
                }
            }
            .padding(.trailing, DS.Space.s16).frame(minHeight: SettingsSpec.row)
            .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline).padding(.leading, DS.Size.icon + DS.Space.s12) }
            .contentShape(Rectangle())
        }
        .dsPressStyle().disabled(on || notifications == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(denied ? "打开系统设置，允许余白发通知" : on ? "" : "允许余白在记下后发通知")
        .accessibilityIdentifier("quickNotify")
    }

    private func readNotifications() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    #endif

    private func statistic(_ title: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(title).dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
            Text("\(count.formatted()) 笔").dsText(SettingsSpec.quickCount).foregroundStyle(DS.Color.ink)
        }.accessibilityElement(children: .combine)
    }

    @ViewBuilder private func entrance(_ icon: DS.Icon, _ name: String, count: Int, first: Bool, id: String) -> some View {
        #if os(iOS)
        Button { askingToOpen = true } label: { entranceRow(icon, name, count: count, first: first) }
            .dsPressStyle()
            .accessibilityElement(children: .combine)
            .accessibilityHint("打开快捷指令添加余白的动作")
            .accessibilityIdentifier(id)
        #else
        // The Mac has no 记一笔 actions to add: a plain row with its count.
        entranceRow(icon, name, count: count, first: first).accessibilityElement(children: .combine).accessibilityIdentifier(id)
        #endif
    }

    private func entranceRow(_ icon: DS.Icon, _ name: String, count: Int, first: Bool) -> some View {
        Group {
            HStack(spacing: DS.Space.s12) {
                DSIconView(icon: icon, size: DS.Size.icon, color: DS.Color.accentInk)
                VStack(alignment: .leading, spacing: .zero) {
                    Text(name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink)
                    Text("近 7 天 \(count.formatted()) 笔").dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                }.dsFillWidth()
                #if os(iOS)
                // The 记一笔 actions ship on iOS only; the Mac has none to add.
                Text("添加").dsText(SettingsSpec.pillLabel).foregroundStyle(DS.Color.accentInk)
                    .padding(.horizontal, SettingsSpec.pillInset).frame(height: SettingsSpec.pillHeight)
                    .dsPill(DS.Color.accentSoft)
                #endif
            }
            .padding(.trailing, DS.Space.s16).frame(minHeight: SettingsSpec.quickRow)
            .overlay(alignment: .top) {
                if !first { DS.Color.separator.frame(height: DS.Stroke.hairline).padding(.leading, DS.Size.icon + DS.Space.s12) }
            }
            .contentShape(Rectangle())
        }
    }

    private func link(_ icon: DS.Icon, _ name: String, _ value: String, first: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSSettingsRow(icon: icon, name: name, tint: DS.Color.accentInk, accessory: .link(value), separator: !first)
        }.dsPressStyle().accessibilityIdentifier(id)
    }
}

/// Canvas S-Quick-Cards: each card with its bills in the last 30 days and the account it records to.
/// A List, so a card's account can be removed with the native swipe; its bills then go to the default account.
struct QuickCardsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let ledger = store.current
        let cards = store.quickCaptureStats.cards
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "卡对应的账户")
            List {
                Color.clear.frame(height: DS.Space.s8).dsPlainRow()
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    let account = card.accountID.flatMap { id in ledger.accounts.first { $0.id == id && !$0.archived } }
                    Button { store.settingsSheet = .captureCard(card.card) } label: {
                        HStack(spacing: DS.Space.s8) {
                            VStack(alignment: .leading, spacing: .zero) {
                                Text(card.card).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink).lineLimit(1)
                                Text(card.everUsed ? "近 30 天 \(card.recentCount.formatted()) 笔" : "还没刷过")
                                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                            }.dsFillWidth()
                            HStack(spacing: HomeSpec.gap6) {
                                DSIconView(icon: account.map { $0.kind.icon } ?? .add, size: DS.Space.s16, color: DS.Color.ink2)
                                Text(account?.name ?? "选账户").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2).lineLimit(1)
                                DSIconView(icon: .chevron, size: SettingsSpec.chevron, color: DS.Color.chevron)
                            }
                        }
                        .padding(.trailing, DS.Space.s16).frame(minHeight: SettingsSpec.subRow)
                        .overlay(alignment: .top) { if index > 0 { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
                        .contentShape(Rectangle())
                    }
                    .dsPressStyle().accessibilityElement(children: .combine).accessibilityIdentifier("quickCard_\(index)")
                    .padding(.leading, DS.Space.s16)
                    .dsCardRow(first: index == 0, last: false)
                    .modifier(MappingDelete(enabled: card.accountID != nil, scale: displayScale) {
                        store.update("删除卡对应的账户", entryMotion: false, showToast: false) {
                            QuickCapture.removeAccount(forCard: card.card, in: &$0)
                        }
                    })
                }
                // A new card can be pointed at an account before its first Apple Pay bill.
                Button { store.settingsSheet = .captureAddCard } label: {
                    HStack(spacing: DS.Space.s12) {
                        DSIconView(icon: .add, size: SettingsSpec.calendarArrow, color: DS.Color.accentInk)
                        Text("添加卡").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.accentInk).dsFillWidth()
                    }
                    .padding(.trailing, DS.Space.s16).frame(minHeight: SettingsSpec.row)
                    .overlay(alignment: .top) { if !cards.isEmpty { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
                    .contentShape(Rectangle())
                }
                .dsPressStyle().accessibilityIdentifier("quickAddCard")
                .padding(.leading, DS.Space.s16)
                .dsCardRow(first: cards.isEmpty, last: true)
                Color.clear.frame(height: DS.Space.s28).dsPlainRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .environment(\.defaultMinListRowHeight, .zero)
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .dsEdgeSwipeBack()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

/// Canvas S-Quick-Merchants: search, then each remembered merchant with the category it records to.
/// Swiping a merchant away forgets it; its next bill is guessed like any other.
struct QuickMerchantsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rules = store.merchantRules.filter { needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle) }
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "商户记到哪个分类")
            List {
                HStack(spacing: DS.Space.s8) {
                    DSIconView(icon: .search, size: DS.Space.s16, color: DS.Color.ink3)
                    TextField("", text: $query, prompt: Text("搜商户").foregroundStyle(DS.Color.ink3))
                        .textFieldStyle(.plain).dsText(DS.Font.tLabel).tint(DS.Color.accent).foregroundStyle(DS.Color.ink)
                        .focused($searching).accessibilityLabel("搜商户").accessibilityIdentifier("merchantSearch")
                }
                .padding(.horizontal, DS.Space.s12).frame(height: SettingsSpec.searchHeight)
                .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                .padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s8).padding(.bottom, DS.Space.s12)
                .dsPlainRow()
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    Button { store.settingsSheet = .captureMerchant(rule.key) } label: {
                        HStack(spacing: DS.Space.s8) {
                            Text(rule.name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink).lineLimit(1).dsFillWidth()
                            HStack(spacing: HomeSpec.gap6) {
                                DSIconView(icon: rule.icon, size: DS.Space.s16, color: DS.Color.ink2)
                                Text(rule.category).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2).lineLimit(1)
                                DSIconView(icon: .chevron, size: SettingsSpec.chevron, color: DS.Color.chevron)
                            }
                        }
                        .padding(.trailing, DS.Space.s16).frame(minHeight: SettingsSpec.row)
                        .overlay(alignment: .top) { if index > 0 { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
                        .contentShape(Rectangle())
                    }
                    .dsPressStyle().accessibilityElement(children: .combine).accessibilityIdentifier("quickMerchant_\(index)")
                    .padding(.leading, DS.Space.s16)
                    .dsCardRow(first: index == 0, last: index == rules.count - 1)
                    .modifier(MappingDelete(enabled: true, scale: displayScale) {
                        store.update("删除商户分类", entryMotion: false, showToast: false) {
                            QuickCapture.forgetMerchant(key: rule.key, in: &$0)
                        }
                    })
                }
                Color.clear.frame(height: DS.Space.s28).dsPlainRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, .zero)
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .dsEdgeSwipeBack()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

/// A mapping row's swipe: 删除 drops the rule at once; the default takes over and nothing is lost.
private struct MappingDelete: ViewModifier {
    let enabled: Bool
    let scale: CGFloat
    let delete: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.nativeSwipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: delete) {
                    Label { Text("删除") } icon: { DS.Icon.delete.templateImage(size: HomeSpec.swipeIcon, scale: scale) }
                }
                .tint(DS.Color.warnStrong)
            }
        } else {
            content
        }
    }
}

/// One remembered merchant → category rule, read from the ledger's merchant memory.
struct QuickMerchantRule: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let income: Bool
    let category: String
    let icon: DS.Icon

    static func all(in ledger: Ledger) -> [QuickMerchantRule] {
        ledger.classificationMemory.keys.sorted().map { key in
            let income = direction(key, in: ledger)
            let choice = CategoryAssignment(path: ledger.classificationMemory[key] ?? "")
            let resolved = ledger.categoryAssignment(category: choice.category, subcategory: choice.subcategory, income: income)
            let category = ledger.categories.first { $0.name == resolved.category && $0.income == income }
            return QuickMerchantRule(key: key, name: CategoryNamespace.split(key).name, income: income,
                                     category: Classification.displayCategory(resolved.category),
                                     icon: category?.entryIcon ?? .catOther)
        }
    }

    static func direction(_ key: String, in ledger: Ledger) -> Bool {
        if let income = CategoryNamespace.split(key).income { return income }
        let value = CategoryAssignment(path: ledger.classificationMemory[key] ?? "")
        let expense = ledger.categoryAssignment(category: value.category, subcategory: value.subcategory, income: false)
        return !ledger.categories.contains { $0.name == expense.category && !$0.income }
    }
}

/// 卡对应的账户 · 选账户: the accounts in use; picking one saves and closes.
/// With no card yet (添加卡) the name comes first; a name already on the list edits that card.
struct CaptureCardSheet: View {
    let card: String?
    @Environment(AppStore.self) private var store
    @State private var name = ""

    var body: some View {
        let ledger = store.current
        let typed = card ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = QuickCapture.account(forCard: typed, in: ledger)
        SettingsSheetFrame(title: card ?? "添加卡", identifier: "captureCardSheet") { close in
            if card == nil {
                DSInlineTextField(title: "卡名", text: $name).padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4)
                    .accessibilityIdentifier("captureCardName")
            }
            DSPeriodOptionGroup(options: ledger.accounts.filter { !$0.archived }.map { .init(id: $0.id.uuidString, title: $0.name) },
                                selection: current?.uuidString ?? "", rowHeight: SettingsSpec.row, identifierPrefix: "captureCardAccount_") { value in
                guard let id = UUID(uuidString: value), !typed.isEmpty else { return }
                if store.update("卡对应的账户", entryMotion: false, showToast: false, { try QuickCapture.setAccount(id, forCard: typed, in: &$0) }) { close() }
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
    }
}

/// 商户记到哪个分类 · 改分类: the categories of the merchant's direction; picking one saves and closes.
struct CaptureMerchantSheet: View {
    let key: String
    @Environment(AppStore.self) private var store

    var body: some View {
        let ledger = store.current
        let rule = store.merchantRules.first { $0.key == key }
        let income = rule?.income ?? false
        SettingsSheetFrame(title: rule?.name ?? "", identifier: "captureMerchantSheet") { close in
            ScrollView {
                DSPeriodOptionGroup(options: ledger.orderedCategories(income: income).map { .init(id: $0.name, title: $0.name) },
                                    selection: rule?.category ?? "", rowHeight: SettingsSpec.row, identifierPrefix: "captureMerchantCategory_") { value in
                    guard let rule else { return }
                    // The same category again keeps its subcategory; another one replaces the whole rule.
                    guard value != rule.category else { close(); return }
                    if store.update("商户分类", entryMotion: false, showToast: false, { ledger in
                        ledger.classificationMemory.removeValue(forKey: rule.key)
                        try QuickCapture.remember(merchant: rule.name, category: value, income: income, in: &ledger)
                    }) { close() }
                }
                .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
            }.frame(maxHeight: SettingsSpec.pickerMaxHeight)
        }
    }
}
