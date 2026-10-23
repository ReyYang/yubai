import SwiftUI
import YubaiCore

struct WishlistView: View {
    @Environment(AppStore.self) private var store
    var focusedWishID: UUID? = nil
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            if store.current.wishlist.isEmpty {
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
            if let focusedWishID, let wish = store.current.wishlist.first(where: { $0.id == focusedWishID }) { wishRow(wish) }
            let due = store.current.wishlist.filter { $0.id != focusedWishID && followUpVisible($0) }
            ForEach(due) { wish in
                Card(style: .compact, background: YubaiColor.amberTint) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            Text("买了一个月 · 用得怎么样？").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.amberInk)
                            Spacer()
                            if let card = store.current.cards.first(where: { $0.dedupeKey == "follow:\(wish.id)" }) {
                                Menu {
                                    Button("知道了") { store.dismissCard(card.id) }
                                    Button("以后别提") { store.muteCard(card.id) }
                                } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                                    .accessibilityLabel("更多：知道了、以后别提")
                            }
                        }
                        Text(wish.title + "，用得怎么样？").yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.amberStrong)
                        if !wish.purpose.isEmpty { Text("当时说「" + wish.purpose + "」").yubaiFont(YubaiFont.callout) }
                        WishFollowUpView(wishID: wish.id)
                    }
                }
            }
            let thinking = store.current.wishlist.filter { $0.status == .thinking && $0.id != focusedWishID }.sorted { $0.createdAt > $1.createdAt }
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
                    HStack(spacing: YubaiSpace.gapGroup) { Text("已经买了 \(past.filter { $0.status == .bought }.count) 件 · 不买了 \(past.filter { $0.status == .dropped }.count) 件"); Spacer(); Image(systemName: "chevron.right") }
                        .yubaiFont(YubaiFont.row).padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.tapMin).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("心愿单").yubaiNavigation()
    }
    private func followUpVisible(_ wish: WishItem) -> Bool {
        guard wish.status == .bought, wish.followUpAnswer == nil, wish.followUpAt.map({ $0 <= Date() }) == true else { return false }
        let key = "follow:\(wish.id)"
        return !ButlerCards.isMuted(key, in: store.current) && store.current.cards.first(where: { $0.dedupeKey == key })?.dismissedAt == nil
    }
    private func wishRow(_ wish: WishItem) -> some View {
        Card { wishContent(wish) }
    }
    private func wishContent(_ wish: WishItem) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            HStack(spacing: YubaiSpace.gapGroup) { Text(wish.title).yubaiFont(YubaiFont.cardTitle); Spacer(); AmountLabel(cents: wish.amount, hide: store.current.preferences.hideAmounts) }
            if !wish.judgment.isEmpty { Text(store.current.preferences.hideAmounts ? "金额已隐藏。" : wish.judgment).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
            let days = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(wish.createdAt), to: Dates.day(Date())).day ?? 0)
            Text(wish.status == .thinking ? "已经想了 \(days) 天" : "加入 \(days) 天 · " + Dates.text(wish.createdAt)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) { wishActions(wish) }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) { wishActions(wish) }
            }
            if wish.status == .bought {
                if let id = wish.boughtEntryID, store.current.activeEntries.contains(where: { $0.id == id }) {
                    NavigationLink("购买记录") { EntryDetailView(entryID: id) }
                }
                if let answer = wish.followUpAnswer { Text("一个月后的感受：" + answer).yubaiFont(YubaiFont.callout) }
                else if let due = wish.followUpAt, due <= Date() { WishFollowUpView(wishID: wish.id) }
                else if let due = wish.followUpAt {
                    Label(Dates.text(due), systemImage: "calendar.badge.clock")
                        .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        .accessibilityLabel("\(Dates.text(due)) 问你用得怎么样")
                }
            }
        }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
    }
    @ViewBuilder private func wishActions(_ wish: WishItem) -> some View {
        if wish.status == .thinking {
            NavigationLink("已经买了") { WishEntryPicker(wishID: wish.id) }
            Button("不买了") { store.update("放下心愿") { ledger in
                if let i = ledger.wishlist.firstIndex(where: { $0.id == wish.id }) { ledger.wishlist[i].status = .dropped }
            } }
        }
        NavigationLink("再问一次") { AskYubaiView(initialText: "我还想再看看「\(wish.title)」，\(Money.input(wish.amount))元，该不该买？") }
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
                Text("选一笔已经记下的支出。").yubaiFont(YubaiFont.callout)
                let matches = Wishlist.candidates(for: wish, in: store.current, now: Date())
                let used = Set(store.current.wishlist.compactMap(\.boughtEntryID))
                let rows = all ? store.sortedEntries.filter { $0.deletedAt == nil && $0.nature == .expense && $0.date <= Date() && !used.contains($0.id) } : matches
                if rows.isEmpty { Text("还没有匹配的支出，先记一笔。") }
                CardRows(rows) { entry in
                    Button {
                        if store.update("关联心愿购买记录", { try Wishlist.markBought(wishID, entryID: entry.id, in: &$0) }) { dismiss() }
                    } label: { EntryRow(entry: entry, hideAmount: store.current.preferences.hideAmounts) }.buttonStyle(PressButtonStyle())
                }
                Toggle("查看全部支出", isOn: $all).tint(YubaiColor.toggleOn)
                NavigationLink("先记下购买") { AskYubaiView(initialText: "记一笔：\(wish.title) \(Money.input(wish.amount))元") }
            } else { Text("这条心愿已经处理过了。") }
        }.navigationTitle("对应哪一笔").yubaiNavigation()
    }
}

private struct WishFollowUpView: View {
    @Environment(AppStore.self) private var store
    let wishID: UUID
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            Text("用得怎么样？").yubaiFont(YubaiFont.rowTitle)
            TextField("想补充的话（可选）", text: $text, axis: .vertical).lineLimit(1...4)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.gapGroup) { choices }
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) { choices }
            }
        }
    }
    private var choices: some View {
        ForEach(FollowUpChoice.allCases, id: \.rawValue) { choice in
            Button(choice.rawValue) {
                store.update("记下一个月的感受") { try Wishlist.answerFollowUp(wishID, choice: choice, text: text, in: &$0, now: Date()) }
            }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).frame(minHeight: YubaiSize.tapMin).disabled(text.count > 3900)
        }
    }
}
