import SwiftUI
import YubaiCore

/// 周期超了的补法：从每月存里少存一点，或者从存着的钱里出。同一张弹窗，只是第一行不同。
struct OverspendSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let source: CycleCover.Source
    var body: some View {
        if let options = store.overspend {
            OverspendEditor(source: source, options: options)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}

private struct OverspendEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let source: CycleCover.Source
    let options: Overspend.Options
    @State private var keypad: EntryKeypad

    init(source: CycleCover.Source, options: Overspend.Options) {
        self.source = source; self.options = options
        let limit = source == .saveLess ? options.maxSaveLess : options.maxFromReserve
        _keypad = State(initialValue: EntryKeypad(amount: min(options.cushion, limit)))
    }

    private var limit: Int64 { source == .saveLess ? options.maxSaveLess : options.maxFromReserve }
    private var amount: Int64 { keypad.amount ?? 0 }
    private var valid: Bool { amount > 0 && amount <= limit }
    private var title: String { source == .saveLess ? "这个月少存一点" : "从存着的钱出" }
    private var presets: [AmountPreset] {
        [AmountPreset(id: "level", title: "只补平", amount: options.level, identifier: "coverLevel"),
         AmountPreset(id: "cushion", title: "再留够 \(options.daysLeft) 天", amount: options.cushion, identifier: "coverCushion")]
    }
    private var rows: [AmountSheetRow] {
        guard valid else { return [] }
        let hide = store.preferences.hideAmounts
        let preview = Overspend.preview(store.current, source: source, amount: amount, now: Dates.now)
        var available = amount2(preview.availableAfter, hide: hide)
        if let daily = preview.dailyAfter { available += " · 日均 " + amount2(daily, hide: hide) }
        return [AmountSheetRow(label: source == .saveLess ? "每月存" : "存着的钱", value: ResultBar.change(preview.before, preview.after, hide: hide)),
                AmountSheetRow(label: "还能花", value: available)]
    }

    var body: some View {
        AmountEntrySheet(title: title, presets: presets, keypad: $keypad, rows: rows, primaryTitle: "好",
                         canSave: valid, save: save)

    }

    private func save() {
        guard valid else { return }
        let value = amount
        let source = self.source
        let before = source == .saveLess ? store.funds.savingTarget : store.funds.fixedSavingsTotal
        let hide = store.preferences.hideAmounts
        guard store.update("补平", { ledger in try Overspend.cover(&ledger, source: source, amount: value, now: Dates.now) }) else { return }
        store.toast = (source == .saveLess ? "这个月存 " : "存着的钱 ") + amount2(before - value, hide: hide)
        dismiss()
    }
}
