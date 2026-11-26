import SwiftUI
import YubaiCore

/// 常用: long-press 记一笔. One tap records with undo; 编辑常用 opens the list.
struct QuickRepeatMenu: View {
    struct Item: Identifiable {
        let id: String
        let purpose: String
        let amount: Int64
        let entry: EntryHistory.Repeat?
    }
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let dismiss: () -> Void
    @State private var items: [Item] = QuickRepeatMenu.fixtureItems ?? []

    // canvas Home.dc.html: oftenRows
    private static let fixtureItems: [Item]? = HomeFixture.current?.isOften == true
        ? [("午饭", 2_500), ("地铁", 400), ("咖啡", 1_800), ("房租", 350_000)].map { Item(id: $0.0, purpose: $0.0, amount: $0.1, entry: nil) }
        : nil

    var body: some View {
        VStack(spacing: .zero) {
            VStack(spacing: .zero) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                        .overlay(alignment: .top) { if index > 0 { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
                }
            }.padding(.horizontal, DS.Space.s16)
            if !items.isEmpty { DS.Color.separator.frame(height: HomeSpec.oftenBand) }
            Button {
                dismiss(); store.sheetSource = nil; store.sheet = .frequentEntries
            } label: {
                Text("编辑常用").dsText(DS.Font.tBody).foregroundStyle(DS.Color.accentInk)
                    .frame(maxWidth: .infinity, minHeight: HomeSpec.oftenRow, alignment: .leading)
                    .padding(.horizontal, DS.Space.s16).contentShape(Rectangle())
            }.dsPressStyle().accessibilityIdentifier("manageQuickRepeats")
        }
        .frame(maxWidth: textSize.isAccessibilitySize ? .infinity : HomeSpec.oftenWidth)
        .background(DS.Color.raised).clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
        .dsShadow(DS.Shadow.float)
        .accessibilityElement(children: .contain).accessibilityIdentifier("quickRepeatMenu")
        .task(id: store.ledgerRevision) {
            guard QuickRepeatMenu.fixtureItems == nil else { return }
            let ledger = store.current, now = Dates.now
            let value = await Task.detached(priority: .userInitiated) { EntryHistory.repeats(in: ledger, now: now) }.value
            guard !Task.isCancelled else { return }
            items = value.prefix(HomeSpec.oftenRows).map { Item(id: $0.id, purpose: $0.purpose, amount: $0.amount, entry: $0) }
        }
    }

    private func row(_ item: Item, index: Int) -> some View {
        let hide = store.preferences.hideAmounts
        let amount = HomeDisplay.money(item.amount, hidden: hide)
        return Button { record(item) } label: {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DS.Space.s8))
            layout {
                Text(item.purpose).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink).lineLimit(1).dsFillWidth()
                Text(amount).dsText(HomeSpec.oftenAmount).foregroundStyle(DS.Color.ink2).fixedSize()
            }.frame(maxWidth: .infinity, minHeight: HomeSpec.oftenRow).contentShape(Rectangle())
        }.dsPressStyle().accessibilityIdentifier("quickRepeat_\(index)")
            .accessibilityLabel(item.purpose + "，" + (hide ? "金额已隐藏" : amount) + "，记下")
    }

    private func record(_ item: Item) {
        defer { dismiss(); store.homeEntrySession = false }
        guard let entry = item.entry else { return }
        store.homeEntrySession = true
        let now = Dates.now
        let usable = store.accounts.first { $0.id == entry.accountID && !$0.archived } ?? ManualBookkeeping.defaultAccount(in: store.current)
        guard let account = usable else { return }
        do {
            var change = try ManualBookkeeping.change(amount: entry.amount, nature: .expense, accountID: account.id, day: now,
                                                      purpose: entry.purpose, category: entry.category, now: now)
            change.items = change.items.map { value in
                guard case .addEntry(var draft) = value else { return value }
                draft.subcategory = entry.subcategory; draft.categoryUserEdited = true
                return .addEntry(draft)
            }
            let saved = store.apply(change, label: "记一笔", finishing: { ledger in
                for case .addEntry(let draft) in change.items where !Classification.isPending(draft.category) {
                    let choice = CategoryAssignment(category: draft.category, subcategory: draft.subcategory)
                    if SubcategoryClassifier.valid(choice, in: ledger, nature: draft.nature) { try CategoryModel.confirm(choice, entryIDs: [draft.id], in: &ledger) }
                }
            })
            guard saved else { return }
            store.setEntrySaveToast("已记下 1 笔")
            store.finishEntrySaveMotion()
        } catch { store.error = error.localizedDescription }
    }
}

/// Scrim under the bottom bar and the menu above 记一笔, scaling from the button.
struct QuickRepeatOverlay: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if store.oftenMenu {
                DS.Color.scrim.ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture(perform: close).accessibilityHidden(true)
                    .transition(.opacity)
                QuickRepeatMenu(dismiss: close)
                    .padding(.horizontal, DS.Space.s20)
                    .padding(.bottom, HomeSpec.oftenBottom)
                    .transition(reduceMotion ? .opacity : .scale(scale: DSInteraction.floatScale, anchor: .bottom).combined(with: .opacity))
            }
        }.ignoresSafeArea(.container, edges: .bottom)
            .animation(reduceMotion ? DSMotion.reduceMotionAnimation : DSMotion.snappyAnimation, value: store.oftenMenu)
            .sensoryFeedback(.impact(weight: .medium), trigger: store.oftenMenu) { _, open in open }
    }

    private func close() { store.oftenMenu = false }
}
