import SwiftUI
import YubaiCore

struct WishlistView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var phase
    var focusedWishID: UUID? = nil
    @State private var now = Dates.now
    @State private var addingWish = false
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            if !store.current.wishlist.isEmpty { SavingsHeader() }
            WishlistCooldownCards()
            let focused = store.current.wishlist.first { $0.id == focusedWishID }
            let due = store.current.wishlist.filter { $0.id != focusedWishID && followUpVisible($0) }
            let thinking = store.current.wishlist.filter { $0.status == .thinking && $0.coolUntil.map { $0 <= now } != true && $0.id != focusedWishID }.sorted { $0.createdAt > $1.createdAt }
            let regrets = store.current.wishlist.filter { $0.followUpAnswer?.hasPrefix(FollowUpChoice.regret.rawValue) == true }
            if store.current.wishlist.isEmpty {
                EmptyState(.wish, onAction: { addingWish = true })
            }
            if let focused, focused.coolUntil.map({ $0 <= now }) != true { wishRow(focused) }
            ForEach(due) { wish in
                followUpCard(wish)
            }
            ForEach(regrets) { wish in
                WishRegretEntry(wish: wish)
            }
            if !thinking.isEmpty {
                VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                    Text("在想 · \(thinking.count) 件").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.insetCard)
                    CardRows(thinking) { wish in wishContent(wish).padding(.vertical, YubaiSpace.gapGroup) }
                }
            }
            let past = store.current.wishlist.filter { $0.status != .thinking && $0.id != focusedWishID }
            if !past.isEmpty {
                NavigationLink {
                    Page { ForEach(past.sorted { $0.createdAt > $1.createdAt }) { wish in wishRow(wish) } }.navigationTitle("过去的心愿").yubaiNavigation()
                } label: {
                    HStack(spacing: YubaiSpace.gapGroup) { Text("买了 \(past.filter { $0.status == .bought }.count) 件 · 划掉 \(past.filter { $0.status == .dropped }.count) 件"); Spacer(); Image(systemName: "chevron.right") }
                        .yubaiFont(YubaiFont.row).padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.tapMin).paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row, style: .continuous))
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("pastWishes")
            }
        }.amountPrivacy(store.preferences.hideAmounts).navigationTitle("心愿单").yubaiNavigation().accessibilityIdentifier("wishlistPage").task(id: store.ledgerRevision) { now = Dates.now }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addingWish = true } label: {
                        Image(systemName: "plus").yubaiHitTarget().accessibilityHidden(true)
                    }.buttonStyle(TextLinkStyle()).accessibilityLabel("写一个心愿").accessibilityIdentifier("addWishButton")
                }
            }
            .sheet(isPresented: $addingWish) { NavigationStack { WishEditor() }.environment(store).appErrors().yubaiSheetBackground() }
            .onChange(of: phase) { _, value in if value == .active { now = Dates.now } }
    }
    private func followUpCard(_ wish: WishItem) -> some View {
        LetterDismissCard(onDismiss: { store.dismissWishFollowUp(wish.id) }, onMute: { store.dismissWishFollowUp(wish.id, mute: true) }) { animateDismiss in
            Card(style: .compact, background: YubaiColor.amberTint) {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text("买了一个月").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.amberInk).accessibilityIdentifier("wishFollowUpAge")
                    Text(wish.title + "，用得怎么样？").yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.amberStrong)
                    if !wish.purpose.isEmpty { Text("当时说「" + wish.purpose + "」").yubaiFont(YubaiFont.callout) }
                    WishFollowUpView(wishID: wish.id, showsTitle: false, animateDismiss: animateDismiss)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("butlerCard_followUp")
    }
    private func ageText(_ wish: WishItem) -> String? {
        let days: Int = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(wish.createdAt), to: Dates.day(now)).day ?? 0)
        guard wish.status == .thinking else { return "加入 \(days) 天 · " + Dates.text(wish.createdAt) }
        guard let until = wish.coolUntil else { return "放了 \(days) 天" }
        guard until > now else { return nil }
        return "冷静中 · 还有 " + WishWaitText.remaining(until: until, now: now)
    }
    private func followUpVisible(_ wish: WishItem) -> Bool {
        guard wish.status == .bought, wish.followUpAnswer == nil, wish.followUpAt.map({ $0 <= Dates.now }) == true else { return false }
        let key = "follow:\(wish.id)"
        return !ButlerCards.isMuted(key, in: store.current) && store.cards.first(where: { $0.dedupeKey == key })?.dismissedAt == nil
    }
    private func wishRow(_ wish: WishItem) -> some View {
        Card { wishContent(wish) }
    }
    private func wishContent(_ wish: WishItem) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            wishHeading(wish)
            if let age = ageText(wish) {
                Text(age).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    .accessibilityIdentifier("wishWait_" + wish.id.uuidString)
                    .accessibilityValue(wish.coolUntil.map { "等待 \(Int(($0.timeIntervalSince(wish.createdAt) / 3600).rounded())) 小时" } ?? "")
            }
            if wish.status != .bought {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space8) { wishActions(wish) }
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) { wishActions(wish) }
                }
            }
            if wish.status == .bought {
                if let due = wish.followUpAt {
                    Label(Dates.text(due), systemImage: "calendar.badge.clock")
                        .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        .accessibilityLabel("\(Dates.text(due)) 问你用得怎么样")
                        .accessibilityIdentifier("wishFollowUpDate_" + wish.id.uuidString)
                }
                if let id = wish.boughtEntryID, store.entriesByID[id].map({ $0.deletedAt == nil }) == true {
                    NavigationLink("购买记录") { BillDetailRoute(entryID: id) }.accessibilityIdentifier("wishBoughtEntry_" + wish.id.uuidString)
                }
                if let answer = wish.followUpAnswer { Text("一个月后的感受：" + answer).yubaiFont(YubaiFont.callout) }
                else if let due = wish.followUpAt, due <= Dates.now { WishFollowUpView(wishID: wish.id) }
            }
        }.buttonStyle(WishActionButtonStyle()).accessibilityIdentifier("wish_" + wish.id.uuidString)
    }
    private func wishHeading(_ wish: WishItem) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: YubaiSpace.gapGroup))
        return layout {
            Text(wish.title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            if wish.status == .bought { Pill(text: "已买", variant: .brand, showsDot: false) }
            AmountLabel(cents: wish.amount, hide: store.preferences.hideAmounts)
        }
    }
    @ViewBuilder private func wishActions(_ wish: WishItem) -> some View {
        if wish.status == .thinking {
            NavigationLink("已经买了") { WishEntryPicker(wishID: wish.id) }.frame(maxWidth: .infinity).accessibilityIdentifier("wishPurchase_" + wish.id.uuidString)
            Button("不买了") { store.update("放下心愿") { ledger in
                if let i = ledger.wishlist.firstIndex(where: { $0.id == wish.id && $0.status == .thinking }) {
                    ledger.wishlist[i].status = .dropped
                    ledger.wishlist[i].droppedAt = Dates.now; ledger.wishlist[i].coolUntil = nil
                    for j in ledger.cards.indices where ledger.cards[j].dedupeKey == "cooldown:\(wish.id)" { ledger.cards[j].dismissedAt = Dates.now }
                }
            } }.frame(maxWidth: .infinity)
        }
        Button("再问一次") { store.openAsk("我还想再看看「\(wish.title)」，\(Money.text(wish.amount, currency: false))元，该不该买？", send: true) }.frame(maxWidth: .infinity)
    }

}

struct WishEntryPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let wishID: UUID
    @State private var all = false
    var body: some View {
        Page {
            if let wish = store.current.wishlist.first(where: { $0.id == wishID && $0.status == .thinking }) {
                let matches = Wishlist.candidates(for: wish, in: store.current, now: Dates.now)
                let used = Set(store.current.wishlist.compactMap(\.boughtEntryID))
                let rows = all ? store.sortedEntries.filter { $0.deletedAt == nil && $0.nature == .expense && $0.date <= Dates.now && !used.contains($0.id) } : matches
                if rows.isEmpty { EmptyState("list.bullet", "没有匹配的支出", action: "查看全部支出", onAction: { all = true }) }
                CardRows(rows) { entry in
                    Button {
                        if store.update("关联心愿购买记录", { try Wishlist.markBought(wishID, entryID: entry.id, in: &$0) }) { dismiss() }
                    } label: { EntryRow(entry: entry, hideAmount: store.preferences.hideAmounts) }.buttonStyle(PressButtonStyle())
                }.accessibilityLabel("选择已经记下的支出")
                Toggle("查看全部支出", isOn: $all).tint(YubaiColor.toggleOn)
                Button("先记下购买") { store.openAsk("记一笔：\(wish.title) \(Money.text(wish.amount, currency: false))元") }
            } else { Text("这条心愿已经处理过了。") }
        }.navigationTitle("对应哪一笔").yubaiNavigation().accessibilityIdentifier("wishEntryPicker")
    }
}

private struct WishFollowUpView: View {
    @Environment(AppStore.self) private var store
    let wishID: UUID
    var showsTitle = true
    var animateDismiss: CardDismissAnimation? = nil
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            if showsTitle { Text("用得怎么样？").yubaiFont(YubaiFont.rowTitle) }
            DisclosureGroup("更多") {
                CardTextFieldRow(title: "补充", text: $text, identifier: "wishFollowUpText", multiline: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.gapGroup) { choices }
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) { choices }
            }
        }
    }
    private var choices: some View {
        ForEach(FollowUpChoice.allCases, id: \.rawValue) { choice in
            Button(choice.rawValue) {
                let save = { store.answerWishFollowUp(wishID, choice: choice, text: text) }
                if let animateDismiss { animateDismiss(save) }
                else { _ = save() }
            }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).frame(minHeight: YubaiSize.tapMin).disabled(text.count > 3900)
        }
    }
}

private struct WishActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.callout, weight: .regular)
            .padding(.horizontal, YubaiSpace.space16).padding(.vertical, YubaiSpace.space8)
            .frame(maxWidth: .infinity, minHeight: YubaiSize.rowIcon)
            .foregroundStyle(isEnabled ? YubaiColor.label : YubaiColor.labelSecondary)
            .background(isEnabled ? YubaiColor.paperInset : Color.clear, in: Capsule())
            .overlay { if isEnabled { Capsule().strokeBorder(YubaiColor.separator, lineWidth: YubaiSize.separator) } }
            .yubaiHitTarget().contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}
