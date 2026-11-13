import SwiftUI
import YubaiCore

struct WishEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amount: Int64 = 0
    @State private var keypad = EntryKeypad()
    @State private var editingAmount = false
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    CardTextFieldRow(title: "名字", text: $title, identifier: "wishTitle", autofocus: true)
                    EntryFormDivider()
                    Button { keypad = EntryKeypad(amount: amount); editingAmount = true } label: {
                        EntryFormRow(title: "金额") { AmountLabel(cents: amount, hide: store.preferences.hideAmounts) }
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("wishAmount")
                }
            }
        }.manualSheetHeader("心愿", actionTitle: "保存", enabled: amount > 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            actionIdentifier: "saveWish", action: save)
            .sheet(isPresented: $editingAmount) {
                AmountEntrySheet(title: "金额", keypad: $keypad, primaryTitle: "好", canSave: (keypad.amount ?? 0) > 0, save: {
                    guard let value = keypad.resolve(), value > 0 else { return }
                    amount = value; editingAmount = false
                }).environment(store).yubaiSheetBackground()
            }
    }
    private func save() {
        if store.update("加入心愿单", { ledger in
            var wish = WishItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount)
            wish.createdAt = Date()
            wish.coolUntil = Wishlist.cooldownUntil(amount: amount, fromPrinciples: ledger.profile.principles, now: wish.createdAt)
            ledger.wishlist.append(wish)
        }) { dismiss() }
    }
}
