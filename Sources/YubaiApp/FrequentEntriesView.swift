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
    var body: some View {
        Page(spacing: YubaiSpace.gapGroup) {
            CardRows(Array(items.enumerated()).map { IndexedFrequentEntry(index: $0.offset, entry: $0.element) }) { row in
                entryRow(row.entry, index: row.index)
            }
            if !hidden.isEmpty {
                CardRows(hidden) { row in hiddenRow(row) }
            }
            quickCaptureLink
        }.navigationTitle("常用").yubaiNavigation().accessibilityIdentifier("frequentEntriesPage")
            .task(id: store.ledgerRevision) { await refresh() }
    }
    /// Apple Pay 快捷指令、卡和商户对应关系仍在原来的页面里。
    private var quickCaptureLink: some View {
        Card(style: .list) {
            NavigationLink { QuickCaptureSettingsView() } label: {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text("快速记账").yubaiFont(YubaiFont.row)
                    Spacer(minLength: YubaiSpace.space8)
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openQuickCaptureSettings")
        }
    }
    private func entryRow(_ item: EntryHistory.Repeat, index: Int) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            summary(item.purpose, amount: item.amount)
            HStack(spacing: YubaiSpace.space4) {
                icon(pinned.contains(item.id) ? "pin.fill" : "pin", label: (pinned.contains(item.id) ? "取消固定" : "固定") + item.purpose,
                     identifier: "frequentPin_\(index)", selected: pinned.contains(item.id)) {
                    store.update("常用", entryMotion: false, showToast: false) { try EntryHistory.setPinned(item, pinned: !pinned.contains(item.id), in: &$0) }
                }
                icon("eye.slash", label: "隐藏" + item.purpose, identifier: "frequentHide_\(index)") {
                    store.update("常用", entryMotion: false, showToast: false) { try EntryHistory.setHidden(item, hidden: true, in: &$0) }
                }
                Spacer(minLength: YubaiSpace.none)
                icon("arrow.up", label: "向前移" + item.purpose, identifier: "frequentMoveUp_\(index)") { move(index, by: -1) }.disabled(index == 0)
                icon("arrow.down", label: "向后移" + item.purpose, identifier: "frequentMoveDown_\(index)") { move(index, by: 1) }.disabled(index == items.count - 1)
            }
        }.padding(.vertical, YubaiSpace.space4).accessibilityElement(children: .contain).accessibilityIdentifier("frequentEntry_\(index)")
    }
    private func summary(_ purpose: String, amount: Int64) -> some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return layout {
            Text(purpose).yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading)
            AmountLabel(cents: amount, hide: store.preferences.hideAmounts)
        }.frame(minHeight: YubaiSize.tapMin).accessibilityElement(children: .combine)
    }
    private func hiddenRow(_ row: EntryHistory.HiddenRepeat) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            if let purpose = row.purpose, let amount = row.amount { summary(purpose, amount: amount).foregroundStyle(YubaiColor.labelSecondary) }
            HStack(spacing: YubaiSpace.space8) {
                Image(systemName: "eye.slash").foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                if row.purpose == nil { Text("1 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                Spacer(minLength: YubaiSpace.none)
                icon("eye", label: "重新显示" + (row.purpose ?? "常用"), identifier: "frequentUnhide_" + row.id) {
                    store.update("常用", entryMotion: false, showToast: false) { try EntryHistory.unhide(row.id, in: &$0, now: Date()) }
                }
            }
        }.padding(.vertical, YubaiSpace.space4)
    }
    private func icon(_ symbol: String, label: String, identifier: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).yubaiFont(YubaiFont.row)
                .foregroundStyle(selected ? YubaiColor.brandInk : YubaiColor.labelSecondary)
                .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(label).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(identifier)
    }
    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        var ordered = items; ordered.swapAt(index, target)
        store.update("常用", entryMotion: false, showToast: false) { try EntryHistory.reorder(ordered, in: &$0) }
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
