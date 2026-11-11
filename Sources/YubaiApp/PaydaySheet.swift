import SwiftUI
import YubaiCore

/// 发工资那天：默认填平时的数，改成这次实际到账的；多出来的可以顺手存起来。
struct PaydaySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let due = store.paydayDue {
            PaydayEditor(due: due)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}

private struct PaydayEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let due: Payday.Due
    @State private var keypad: EntryKeypad
    @State private var extraToSavings = false

    init(due: Payday.Due) {
        self.due = due
        _keypad = State(initialValue: EntryKeypad(amount: due.usual))
    }

    private var amount: Int64 { keypad.amount ?? 0 }
    private var valid: Bool { amount > 0 && amount <= Money.limit }
    private var delta: Int64 { amount - due.usual }
    private var rows: [AmountSheetRow] {
        guard valid else { return [] }
        let hide = store.preferences.hideAmounts
        let preview = Payday.preview(due, amount: amount, extraToSavings: extraToSavings && delta > 0, in: store.current, now: Date())
        let budget = amount2(preview.cycleBudget, hide: hide)
        if delta == 0 { return [AmountSheetRow(label: "这个周期能花", value: budget)] }
        let label = (delta > 0 ? "比平时多 " : "比平时少 ") + amount2(abs(delta), hide: hide)
        return [AmountSheetRow(label: label, value: "这个周期能花 " + budget)]
    }

    var body: some View {
        AmountEntrySheet(title: due.title, subtitle: "平时 " + amount2(due.usual, hide: store.preferences.hideAmounts),
                         keypad: $keypad, rows: rows, primaryTitle: "到了", primaryIdentifier: "amountSheetDone",
                         canSave: valid, save: save) {
            if delta > 0 { extraChip }
        }
        #if os(iOS)
        .presentationDetents([.height(700), .large])
        #endif
    }

    private var extraChip: some View {
        ChipFlow {
            Button { extraToSavings.toggle() } label: {
                Text("多的存起来").yubaiFont(YubaiFont.callout)
                    .foregroundStyle(extraToSavings ? YubaiColor.onBrand : YubaiColor.label)
                    .padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.tapMin)
                    .background(extraToSavings ? YubaiColor.brand : YubaiColor.card, in: Capsule()).contentShape(Capsule())
            }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(extraToSavings ? .isSelected : [])
                .accessibilityIdentifier("paydayExtraToSavings")
        }
    }

    private func save() {
        guard valid else { return }
        let value = amount, extra = extraToSavings && delta > 0, due = self.due
        if store.update("工资到了", { ledger in try Payday.confirm(due, amount: value, extraToSavings: extra, accountID: nil, in: &ledger, now: Date()) }) {
            dismiss()
        }
    }
}
