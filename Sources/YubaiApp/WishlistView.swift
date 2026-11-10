import SwiftUI
import YubaiCore

struct WishlistView: View {
    @Environment(AppStore.self) private var store
    var focusedWishID: UUID? = nil
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            SavingsHeader()
            WishlistCooldownCards()
            let focused = store.current.wishlist.first { $0.id == focusedWishID }
            let due = store.current.wishlist.filter { $0.id != focusedWishID && followUpVisible($0) }
            let thinking = store.current.wishlist.filter { $0.status == .thinking && $0.id != focusedWishID }.sorted { $0.createdAt > $1.createdAt }
            let regrets = store.current.wishlist.filter { $0.followUpAnswer?.hasPrefix(FollowUpChoice.regret.rawValue) == true }
            if focused == nil && due.isEmpty && thinking.isEmpty && regrets.isEmpty {
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(0..<2) { index in
                            if index > 0 { EntryFormDivider() }
                            HStack(spacing: YubaiSpace.gapSection) { DashedPlaceholder(); Spacer(); DashedPlaceholder().frame(width: YubaiSize.rowSingle) }
                                .frame(minHeight: YubaiSize.rowDouble)
                        }
                    }
                }.accessibilityHidden(true)
                EmptyState("heart", "心愿单还是空的", showsPlaceholder: false, action: "该不该买", onAction: { store.sheet = .ask("该不该买？") })
            }
            if let focused { wishRow(focused) }
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
                        .yubaiFont(YubaiFont.row).padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.tapMin).paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row))
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("pastWishes")
            }
        }.navigationTitle("心愿单").yubaiNavigation()
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
        let now: Date = Date()
        let days: Int = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(wish.createdAt), to: Dates.day(now)).day ?? 0)
        guard wish.status == .thinking else { return "加入 \(days) 天 · " + Dates.text(wish.createdAt) }
        guard let until = wish.coolUntil else { return "放了 \(days) 天" }
        guard until > now else { return nil }
        let remaining: Int = max(until > now ? 1 : 0, Dates.calendar.dateComponents([.day], from: Dates.day(now), to: Dates.day(until)).day ?? 0)
        return "冷静中 · 还有 \(remaining) 天"
    }
    private func followUpVisible(_ wish: WishItem) -> Bool {
        guard wish.status == .bought, wish.followUpAnswer == nil, wish.followUpAt.map({ $0 <= Date() }) == true else { return false }
        let key = "follow:\(wish.id)"
        return !ButlerCards.isMuted(key, in: store.current) && store.cards.first(where: { $0.dedupeKey == key })?.dismissedAt == nil
    }
    private func wishRow(_ wish: WishItem) -> some View {
        Card { wishContent(wish) }
    }
    private func wishContent(_ wish: WishItem) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text(wish.title).yubaiFont(YubaiFont.rowTitle)
                if wish.status == .bought { Pill(text: "已买", variant: .brand, showsDot: false) }
                Spacer(minLength: YubaiSpace.space8)
                AmountLabel(cents: wish.amount, hide: store.preferences.hideAmounts)
            }
            if let age = ageText(wish) { Text(age).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            if !wish.judgment.isEmpty { Text(store.preferences.hideAmounts ? "金额已隐藏。" : wish.judgment).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
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
                if let id = wish.boughtEntryID, store.entriesByID[id].map { $0.deletedAt == nil } == true {
                    NavigationLink("购买记录") { EntryDetailView(entryID: id) }
                }
                if let answer = wish.followUpAnswer { Text("一个月后的感受：" + answer).yubaiFont(YubaiFont.callout) }
                else if let due = wish.followUpAt, due <= Date() { WishFollowUpView(wishID: wish.id) }
            }
        }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
    }
    @ViewBuilder private func wishActions(_ wish: WishItem) -> some View {
        if wish.status == .thinking {
            NavigationLink("已经买了") { WishEntryPicker(wishID: wish.id) }
            Button("不买了") { store.update("放下心愿") { ledger in
                if let i = ledger.wishlist.firstIndex(where: { $0.id == wish.id && $0.status == .thinking }) {
                    ledger.wishlist[i].status = .dropped
                    ledger.wishlist[i].droppedAt = Date(); ledger.wishlist[i].coolUntil = nil
                    for j in ledger.cards.indices where ledger.cards[j].dedupeKey == "cooldown:\(wish.id)" { ledger.cards[j].dismissedAt = Date() }
                }
            } }
        }
        NavigationLink("再问一次") { AskYubaiView(initialText: "我还想再看看「\(wish.title)」，\(Money.text(wish.amount, currency: false))元，该不该买？") }
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
                let matches = Wishlist.candidates(for: wish, in: store.current, now: Date())
                let used = Set(store.current.wishlist.compactMap(\.boughtEntryID))
                let rows = all ? store.sortedEntries.filter { $0.deletedAt == nil && $0.nature == .expense && $0.date <= Date() && !used.contains($0.id) } : matches
                if rows.isEmpty { EmptyState("list.bullet", "没有匹配的支出", action: "查看全部支出", onAction: { all = true }) }
                CardRows(rows) { entry in
                    Button {
                        if store.update("关联心愿购买记录", { try Wishlist.markBought(wishID, entryID: entry.id, in: &$0) }) { dismiss() }
                    } label: { EntryRow(entry: entry, hideAmount: store.preferences.hideAmounts) }.buttonStyle(PressButtonStyle())
                }.accessibilityLabel("选择已经记下的支出")
                Toggle("查看全部支出", isOn: $all).tint(YubaiColor.toggleOn)
                NavigationLink("先记下购买") { AskYubaiView(initialText: "记一笔：\(wish.title) \(Money.text(wish.amount, currency: false))元") }
            } else { Text("这条心愿已经处理过了。") }
        }.navigationTitle("对应哪一笔").yubaiNavigation()
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
                TextField("补充", text: $text, axis: .vertical).lineLimit(1...4)
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
