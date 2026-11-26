import SwiftUI
import YubaiCore

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

