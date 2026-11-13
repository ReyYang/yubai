import SwiftUI
import YubaiCore

private struct FrequentEntriesSnapshot: Sendable {
    var visible: [EntryHistory.Repeat]
    var hidden: [EntryHistory.HiddenRepeat]
    init(ledger: Ledger, now: Date) {
        visible = EntryHistory.repeats(in: ledger, now: now, limit: 1000)
        hidden = EntryHistory.hiddenRepeats(in: ledger, now: now)
    }
}

struct FrequentEntriesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var items: [EntryHistory.Repeat] = []
    @State private var hidden: [EntryHistory.HiddenRepeat] = []
    @State private var pinned = Set<String>()
    @State private var adding = false
    @State private var purpose = ""
    @State private var keypad = EntryKeypad()
    var body: some View {
        Page(spacing: YubaiSpace.gapGroup) {
            if items.isEmpty && hidden.isEmpty {
                EmptyState(.frequent, onAction: { adding = true })
            }
            if !items.isEmpty {
                SectionHeading(title: "显示的")
                CardRows(Array(items.enumerated()).map { IndexedFrequentEntry(index: $0.offset, entry: $0.element) }) { row in
                    entryRow(row.entry, index: row.index)
                }
            }
            if !hidden.isEmpty {
                SectionHeading(title: "不显示的")
                CardRows(hidden) { row in hiddenRow(row) }
            }
        }.accessibilityIdentifier("frequentEntriesPage")
            .sheet(isPresented: $adding) { addForm }
            .task(id: store.ledgerRevision) { await refresh() }
            #if os(iOS)
            .presentationDetents(textSize.isAccessibilitySize ? [.large] : [.height(YubaiSize.sheet560), .large])
            #endif
    }
    private var addForm: some View {
        AmountEntrySheet(title: "常用", keypad: $keypad, primaryTitle: "加一个", primaryIdentifier: "saveFrequentEntry",
                         canSave: keypad.amount.map { $0 > 0 } == true && !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && purpose.count <= 100,
                         save: {
            guard let amount = keypad.resolve() else { return }
            if store.update("常用", entryMotion: false, showToast: false, { try EntryHistory.addRepeat(purpose: purpose, amount: amount, in: &$0, now: Date()) }) { adding = false }
        }) {
            Card(style: .list) { CardTextFieldRow(title: "用途", text: $purpose, identifier: "frequentEntryPurpose") }
        }.environment(store).appErrors().yubaiSheetBackground()
    }
    private func entryRow(_ item: EntryHistory.Repeat, index: Int) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
        return layout {
            summary(item.purpose, amount: item.amount)
            HStack(spacing: YubaiSpace.space8) {
                action(pinned.contains(item.id) ? "已置顶" : "置顶", identifier: "frequentPin_\(index)") {
                    store.update("常用", entryMotion: false, showToast: false) { try EntryHistory.setPinned(item, pinned: !pinned.contains(item.id), in: &$0) }
                }.accessibilityLabel((pinned.contains(item.id) ? "取消置顶" : "置顶") + item.purpose)
                action("不显示", identifier: "frequentHide_\(index)", secondary: true) {
                    store.update("常用", entryMotion: false, showToast: false) { try EntryHistory.setHidden(item, hidden: true, in: &$0) }
                }.accessibilityLabel("不显示" + item.purpose)
            }
        }.frame(minHeight: YubaiSize.rowDouble).accessibilityElement(children: .contain).accessibilityIdentifier("frequentEntry_\(index)")
    }
    private func summary(_ purpose: String, amount: Int64) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Text(purpose).yubaiFont(YubaiFont.row).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            AmountLabel(cents: amount, hide: store.preferences.hideAmounts).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).accessibilityElement(children: .combine)
    }
    private func hiddenRow(_ row: EntryHistory.HiddenRepeat) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
        return layout {
            if let purpose = row.purpose, let amount = row.amount { summary(purpose, amount: amount).foregroundStyle(YubaiColor.labelSecondary) }
            action("放回去", identifier: "frequentUnhide_" + row.id) {
                store.update("常用", entryMotion: false, showToast: false) { try EntryHistory.unhide(row.id, in: &$0, now: Date()) }
            }.accessibilityLabel("放回去" + (row.purpose ?? "常用"))
        }.frame(minHeight: YubaiSize.rowDouble)
    }
    private func action(_ title: String, identifier: String, secondary: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).yubaiFont(YubaiFont.callout).fixedSize()
                .foregroundStyle(secondary ? YubaiColor.labelSecondary : YubaiColor.brandInk)
                .frame(minWidth: YubaiSize.tapMin, minHeight: YubaiSize.tapMin)
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(identifier)
    }
    private func refresh() async {
        let ledger = store.current, now = Date(), revision = store.ledgerRevision
        let result = await Task.detached(priority: .userInitiated) { FrequentEntriesSnapshot(ledger: ledger, now: now) }.value
        guard !Task.isCancelled, store.ledgerRevision == revision else { return }
        items = result.visible
        hidden = result.hidden
        pinned = Set((ledger.repeatPreferences ?? []).filter { $0.pinned != nil }.map(\.id))
    }
}

private struct IndexedFrequentEntry: Identifiable {
    let index: Int
    let entry: EntryHistory.Repeat
    var id: String { entry.id }
}
