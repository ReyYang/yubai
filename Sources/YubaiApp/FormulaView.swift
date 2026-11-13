import SwiftUI
import YubaiCore

// MARK: - 算式里改一项

/// 存着不动 / 每月存 / 手上的钱。一边输一边看到还能花和日均变成多少。
struct FormulaEditSheet: View {
    @Environment(AppStore.self) private var store
    let field: FormulaField
    var body: some View {
        switch field {
        case .hand:
            ReconcileView()
        case .fixedSavings:
            FormulaAmountEditor(field: field, amount: store.formula.fixedSavings, percent: nil, sharing: false)
        case .saving:
            let current = store.current
            let base: Int64 = { if case .fixed(let amount)? = current.savingRule { return amount }; return 0 }()
            FormulaAmountEditor(field: field, amount: base,
                                percent: sharePercent(current.savingRule) ?? current.lastSavingSharePercent,
                                sharing: sharePercent(current.savingRule) != nil)
        }
    }
    private func sharePercent(_ rule: SavingRule?) -> Int? {
        if case .share(let percent)? = rule { return percent }
        return nil
    }
}

private struct FormulaAmountEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let field: FormulaField
    let fixedAmount: Int64
    let sharePercent: Int
    @State private var keypad: EntryKeypad
    @State private var sharing: Bool
    @State private var selected = true

    init(field: FormulaField, amount: Int64, percent: Int?, sharing: Bool) {
        self.field = field; fixedAmount = amount; sharePercent = percent ?? 20
        _sharing = State(initialValue: sharing)
        _keypad = State(initialValue: EntryKeypad(amount: sharing ? Int64(percent ?? 20) * 100 : amount))
    }

    private var title: String { field == .fixedSavings ? "存着不动" : "每月存" }
    private var value: Int64 { keypad.amount ?? 0 }
    private var percent: Int { Int(value / 100) }
    private var valid: Bool {
        guard let amount = keypad.amount, amount >= 0, amount <= Money.limit else { return false }
        return sharing ? amount % 100 == 0 && (1...90).contains(percent) : true
    }
    private var modeBinding: Binding<Bool> {
        Binding(get: { sharing }, set: { next in
            guard next != sharing else { return }
            sharing = next
            keypad = EntryKeypad(amount: next ? Int64(store.current.lastSavingSharePercent ?? sharePercent) * 100 : store.current.lastFixedSavingTarget ?? fixedAmount)
            selected = true
        })
    }
    /// 改完以后的还能花和日均；输入无效时不给结果。
    private var resultText: String? {
        guard valid else { return nil }
        let now = Date()
        var projected = store.current
        switch field {
        case .fixedSavings: projected.setFixedSavingsTotal(value, now: now)
        case .saving: projected.savingRule = sharing ? .share(percent) : .fixed(value)
        case .hand: return nil
        }
        let hide = store.preferences.hideAmounts
        var text = amount2(Finance.funds(projected, now: now).available, hide: hide)
        if let daily = Finance.pace(projected, now: now)?.daily { text += " · 日均 " + amount2(daily, hide: hide) }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                header
                if field == .saving { modePicker }
                amountDisplay
                if let resultText { ResultBar(label: "改完还能花", value: resultText, identifier: "formulaEditResult") }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.sheetHeaderTop)
        }.scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
                AmountKeypad(keypad: $keypad, amountSelected: $selected, canSave: valid, primaryTitle: "好",
                             primaryIdentifier: "saveSavingsAmount", save: save)
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)

            #endif
    }
    private var header: some View { AmountSheetHeader(title: title, cancel: { dismiss() }) }
    private var modePicker: some View {
        Segmented(choices: [(false, "固定金额"), (true, "每笔进账留几成")], selection: modeBinding,
                      identifier: { $0 ? "savingMode_share" : "savingMode_fixed" })
    }
    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            if !sharing { Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary) }
            Text(sharing ? "\(percent)%" : keypad.resultText).yubaiFont(YubaiFont.entryAmount)
                .padding(.horizontal, YubaiSpace.space8)
                .background(selected ? YubaiColor.brandTint : Color.clear, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
            EntryAmountCursor()
            Spacer(minLength: YubaiSpace.none)
        }.frame(minHeight: YubaiSize.rowDouble)
            .accessibilityElement(children: .ignore).accessibilityLabel(sharing ? "几成" : "金额")
            .accessibilityValue(sharing ? "\(percent)%" : keypad.resultText).accessibilityIdentifier("amountSheetAmount")
    }
    private func save() {
        guard valid, let cents = keypad.resolve() else { return }
        let ok = store.update("存钱") { ledger in
            switch field {
            case .fixedSavings: Reserve.setTotal(cents, in: &ledger, now: Date())
            case .saving: ledger.savingRule = sharing ? .share(Int(cents / 100)) : .fixed(cents)
            case .hand: break
            }
        }
        if ok { dismiss() }
    }
}
