import SwiftUI
import YubaiCore

/// 长按 ＋：最近常记的几笔，点一下就记下，给撤销；末尾是「拍小票」。
/// 点完任何一行调 `dismiss()`。
struct QuickRepeatMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let dismiss: () -> Void
    @State private var items: [EntryHistory.Repeat] = []

    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index)
                EntryFormDivider()
            }
            if store.preferences.isAIEnabled(for: .receiptRecognition) && IntelligenceRuntime.isConfigured && IntelligenceRuntime.cloud.unavailableModel == nil { receiptRow }
        }.padding(.horizontal, YubaiSpace.insetCard).frame(maxWidth: textSize.isAccessibilitySize ? .infinity : 230)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
            .accessibilityElement(children: .contain).accessibilityIdentifier("quickRepeatMenu")
            .task(id: store.ledgerRevision) {
                let ledger = store.current, now = Date()
                let value = await Task.detached(priority: .userInitiated) { EntryHistory.repeats(in: ledger, now: now) }.value
                guard !Task.isCancelled else { return }; items = value
            }
    }

    private func row(_ item: EntryHistory.Repeat, index: Int) -> some View {
        let hide = store.preferences.hideAmounts
        return Button { record(item) } label: {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
            layout {
                Text(item.purpose).yubaiFont(YubaiFont.row).lineLimit(1)
                if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
                AmountLabel(cents: item.amount, hide: hide, role: .amount, sign: .none).fixedSize()
            }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("quickRepeat_\(index)")
            .accessibilityLabel(item.purpose + "，" + (hide ? "金额已隐藏" : AmountLabel.text(item.amount)) + "，记下")
    }
    private var receiptRow: some View {
        Button {
            dismiss(); store.sheetSource = nil; store.sheet = .screenshotCapture(nil)
        } label: {
            Text("拍小票").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.brandInk)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("quickReceipt")
    }

    private func record(_ item: EntryHistory.Repeat) {
        defer { dismiss() }
        let now = Date()
        let usable = store.accounts.first { $0.id == item.accountID && !$0.archived } ?? ManualBookkeeping.defaultAccount(in: store.current)
        guard let account = usable else { return }
        do {
            var change = try ManualBookkeeping.change(amount: item.amount, nature: .expense, accountID: account.id, day: now,
                                                      purpose: item.purpose, category: item.category, now: now)
            change.items = change.items.map { entry in
                guard case .addEntry(var draft) = entry else { return entry }
                draft.subcategory = item.subcategory; draft.categoryUserEdited = true
                return .addEntry(draft)
            }
            let saved = store.apply(change, label: "记一笔", finishing: { ledger in
                for case .addEntry(let draft) in change.items where !Classification.isPending(draft.category) {
                    let choice = CategoryAssignment(category: draft.category, subcategory: draft.subcategory)
                    if SubcategoryClassifier.valid(choice, in: ledger, nature: draft.nature) { try CategoryModel.confirm(choice, entryIDs: [draft.id], in: &ledger) }
                }
            })
            guard saved else { return }
            let amount = store.preferences.hideAmounts ? "••••" : AmountLabel.text(item.amount, sign: .outflow)
            store.setEntrySaveToast("已记下 · " + item.purpose + " " + amount + " · " + store.accountName(account.id))
            store.finishEntrySaveMotion()
        } catch { store.error = error.localizedDescription }
    }
}
