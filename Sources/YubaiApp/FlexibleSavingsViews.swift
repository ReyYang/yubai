import SwiftUI
import YubaiCore

struct SavingsTransferSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let direction: SavingsTransfer.Direction
    var offer: SavingsTopupOffer? = nil
    @State private var keypad = EntryKeypad(amount: 0)
    private var amount: Int64 { keypad.amount ?? 0 }
    private var preview: Reserve.TransferPreview {
        Reserve.transferPreview(store.current, direction: direction, amount: amount, now: store.financialNow)
    }
    private var valid: Bool { preview.valid && (offer.map { amount <= $0.amount } ?? true) }
    private var title: String { offer != nil ? "补一部分" : direction == .take ? "拿出来用" : "放回去" }
    var body: some View {
        AmountEntrySheet(title: title, keypad: $keypad, primaryTitle: direction == .take ? "拿出来" : "放回去",
                         primaryIdentifier: "confirmSavingsTransfer", canSave: valid, primaryAboveKeypad: true, save: save) {
            SavingsTransferPreview(preview: preview, hide: store.preferences.hideAmounts)
        }.accessibilityIdentifier("savingsTransferSheet")
    }
    private func save() {
        guard valid, let amount = keypad.resolve() else { return }
        let ok = store.update(direction == .take ? "拿出来用" : "放回去", entryMotion: false) { ledger in
            let now = store.financialNow
            if let offer { try Reserve.answerTopup(offer, amount: amount, in: &ledger, now: now) }
            else { try Reserve.transfer(direction, amount: amount, in: &ledger, now: now) }
        }
        if ok { dismiss() }
    }
}

private struct SavingsTransferPreview: View {
    let preview: Reserve.TransferPreview
    let hide: Bool
    var body: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                row("存下的钱", before: preview.savedBefore, after: preview.valid ? preview.savedAfter : preview.savedBefore, identifier: "transferSavedPreview")
                EntryFormDivider()
                row("还能花", before: preview.availableBefore, after: preview.valid ? preview.availableAfter : preview.availableBefore, identifier: "transferAvailablePreview")
            }
        }.amountPrivacy(hide).accessibilityIdentifier("savingsTransferPreview")
    }
    private func row(_ title: String, before: Int64, after: Int64, identifier: String) -> some View {
        EntryFormRow(title: title) {
            HStack(spacing: YubaiSpace.space8) {
                AmountLabel(cents: before, hide: hide, role: .amount, ink: YubaiColor.labelSecondary)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                AmountLabel(cents: after, hide: hide, role: .summary, ink: after < 0 ? YubaiColor.amberInk : YubaiColor.brandInk)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(title + "，" + amount2(before, hide: hide) + "，变为 " + amount2(after, hide: hide))
            .accessibilityIdentifier(identifier)
    }
}

struct SavingsFloorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var keypad: EntryKeypad
    init(initial: Int64?) { _keypad = State(initialValue: EntryKeypad(amount: initial ?? 0)) }
    var body: some View {
        AmountEntrySheet(title: "想一直留着", keypad: $keypad, primaryTitle: "好", primaryIdentifier: "saveSavingsFloor",
                         canSave: keypad.amount != nil, save: { save(keypad.resolve()) }) {
            if store.current.profile.floorAmount != nil {
                Button("清掉") { save(nil) }.buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("clearSavingsFloor")
            }
        }.accessibilityIdentifier("savingsFloorSheet")
    }
    private func save(_ amount: Int64?) {
        if store.update("想一直留着", entryMotion: false, { try Reserve.setFloor(amount, in: &$0, now: store.financialNow) }) { dismiss() }
    }
}

struct SavingsTopupCard: View {
    @Environment(AppStore.self) private var store
    let offer: SavingsTopupOffer
    var more = 0
    @State private var partial = false
    var body: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                ButlerKicker(title: "上个月从存的钱里拿了 " + amount2(offer.amount, hide: store.preferences.hideAmounts), more: more)
                Text("这个月补回去吗").yubaiFont(YubaiFont.butlerTitle).fixedSize(horizontal: false, vertical: true)
                ChipFlow {
                    Button("全部补上") { answer(offer.amount) }.buttonStyle(NowCardButtonStyle(primary: true))
                        .disabled(!Reserve.transferPreview(store.current, direction: .putBack, amount: offer.amount, now: store.financialNow).valid)
                        .accessibilityIdentifier("savingsTopupAll")
                    Button("补一部分") { partial = true }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("savingsTopupPartial")
                    Button("不补了") { answer(0) }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("savingsTopupDecline")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("savingsTopupCard")
            .sheet(isPresented: $partial) {
                SavingsTransferSheet(direction: .putBack, offer: offer).environment(store).appErrors().yubaiSheetBackground().presentationDragIndicator(.visible)
            }
    }
    private func answer(_ amount: Int64) {
        _ = store.update(amount == 0 ? "不补了" : "放回去", recordUndo: amount > 0, entryMotion: false, showToast: amount > 0) {
            try Reserve.answerTopup(offer, amount: amount, in: &$0, now: store.financialNow)
        }
    }
}
