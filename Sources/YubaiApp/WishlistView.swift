import SwiftUI
import YubaiCore

struct WishlistView: View {
    @Environment(AppStore.self) private var store
    var focusedWishID: UUID? = nil
    var body: some View {
        Page {
            if store.current.wishlist.isEmpty { EmptyState("heart", "给想要的东西，一点时间", "和余白聊过一笔购买后，可以把它放在这里。心愿与回访都保存在本机。") }
            if let focusedWishID, let wish = store.current.wishlist.first(where: { $0.id == focusedWishID }) { wishRow(wish) }
            section(.thinking, title: "还在想")
            section(.bought, title: "已经买了")
            section(.dropped, title: "不买了")
        }.navigationTitle("心愿单").yubaiNavigation()
    }
    @ViewBuilder private func section(_ status: WishStatus, title: String) -> some View {
        let wishes = store.current.wishlist.filter { $0.status == status && $0.id != focusedWishID }.sorted { $0.createdAt > $1.createdAt }
        if !wishes.isEmpty {
            SectionHeading(title: title)
            ForEach(wishes) { wish in wishRow(wish) }
        }
    }
    private func wishRow(_ wish: WishItem) -> some View {
        Card { VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            HStack { Text(wish.title).yubaiFont(YubaiFont.cardTitle); Spacer(); AmountLabel(cents: wish.amount, hide: store.current.preferences.hideAmounts) }
            if !wish.judgment.isEmpty { Text(store.current.preferences.hideAmounts ? "金额已隐藏。" : wish.judgment).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
            let days = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(wish.createdAt), to: Dates.day(Date())).day ?? 0)
            Text(wish.status == .thinking ? "已经想了 \(days) 天" : "加入 \(days) 天 · " + Dates.text(wish.createdAt)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            if wish.status == .thinking {
                NavigationLink("已经买了") { WishEntryPicker(wishID: wish.id) }
                Button("不买了") { store.update("放下心愿") { ledger in if let i = ledger.wishlist.firstIndex(where: { $0.id == wish.id }) { ledger.wishlist[i].status = .dropped } } }
            }
            NavigationLink("再问一次") { AskYubaiView(initialText: "我还想再看看「\(wish.title)」，\(Money.input(wish.amount))元，这笔合理吗？") }
            if wish.status == .bought {
                if let id = wish.boughtEntryID, store.current.activeEntries.contains(where: { $0.id == id }) {
                    NavigationLink("购买记录") { EntryDetailView(entryID: id) }
                }
                if let answer = wish.followUpAnswer { Text("一个月后的感受：" + answer).yubaiFont(YubaiFont.callout) }
                else if let due = wish.followUpAt, due <= Date() { WishFollowUpView(wishID: wish.id) }
                else if let due = wish.followUpAt { Text("到 \(Dates.text(due))，再聊聊用下来的感受。").yubaiFont(YubaiFont.caption) }
            }
        }.buttonStyle(PressButtonStyle()) }
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
                Text("选一笔已经记下的支出，回访从购买日期起算。").yubaiFont(YubaiFont.callout)
                let matches = Wishlist.candidates(for: wish, in: store.current, now: Date())
                let used = Set(store.current.wishlist.compactMap(\.boughtEntryID))
                let rows = all ? store.sortedEntries.filter { $0.deletedAt == nil && $0.nature == .expense && $0.date <= Date() && !used.contains($0.id) } : matches
                if rows.isEmpty { Text("还没有匹配的支出，可以先记一笔，保存后会尝试自动关联。") }
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
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            Text("买了一个月，觉得值吗？").yubaiFont(YubaiFont.rowTitle)
            TextField("想补充的话（可选）", text: $text, axis: .vertical).lineLimit(1...4)
            ViewThatFits(in: .horizontal) {
                HStack { choices }
                VStack(alignment: .leading) { choices }
            }
        }
    }
    private var choices: some View {
        ForEach(FollowUpChoice.allCases, id: \.rawValue) { choice in
            Button(choice.rawValue) {
                store.update("记下一个月的感受") { try Wishlist.answerFollowUp(wishID, choice: choice, text: text, in: &$0, now: Date()) }
            }.frame(minHeight: YubaiSize.tapMin).disabled(text.count > 3900)
        }
    }
}
