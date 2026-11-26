import SwiftUI
import YubaiCore

struct PaydaySetupSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var day = Payday.defaultDay
    @State private var amount: Int64 = .zero
    @State private var currentAvailable = ""
    @State private var editingAmount = false
    @State private var keypad = EntryKeypad()
    @State private var accountID: UUID?
    private var valid: Bool { amount > .zero && amount <= Money.limit && accountID != nil }
    private var showsCurrentAvailable: Bool {
        let now = store.financialNow
        return Payday.nominalDate(day: day, inMonthOf: now) < Dates.day(now) &&
            Finance.spendableBreakdown(store.current, now: now).income == .zero
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                header
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        EntryFormRow(title: "每月几号") { Text("\(day) 号").yubaiFont(YubaiFont.rowTitle) }
                        EntryFormDivider()
                        EntryFormRow(title: "平时") {
                            Button { keypad = EntryKeypad(amount: amount); editingAmount = true } label: {
                                AmountLabel(cents: amount, hide: store.preferences.hideAmounts, role: .summary)
                                    .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                            }.buttonStyle(PressButtonStyle()).accessibilityLabel("工资金额").accessibilityIdentifier("paydaySetupAmount")
                        }
                        if showsCurrentAvailable {
                            EntryFormDivider()
                            MoneyInputRow(title: "这期还能花", text: $currentAvailable, identifier: "paydaySetupCurrentAvailable")
                        }
                    }
                }
                days
            }.padding(.horizontal, YubaiSpace.insetPage)
                .padding(.bottom, YubaiSpace.gapSection)
        }.paperBackground().accessibilityElement(children: .contain).accessibilityIdentifier("paydaySetupSheet")
            .onAppear { if accountID == nil { accountID = ManualBookkeeping.defaultAccount(in: store.current, nature: .income)?.id } }
            .sheet(isPresented: $editingAmount) {
                AmountEntrySheet(title: "工资", keypad: $keypad, primaryTitle: "好", primaryIdentifier: "paydaySetupAmountDone",
                                 canSave: keypad.canSave, save: {
                    guard let value = keypad.resolve(), value > .zero else { return }
                    amount = value; editingAmount = false
                }).environment(store).yubaiSheetBackground().presentationDragIndicator(.visible)
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.medium, .large])
            #endif
    }
    private var header: some View {
        ManualSheetHeader(title: "哪天发工资", actionTitle: "好", enabled: valid,
                          actionIdentifier: "paydaySetupDone", cancelIdentifier: "paydaySetupCancel", cancel: { dismiss() }, action: save)
    }
    private var days: some View { MonthDayChoices(selection: $day, identifier: "paydaySetupDay_") }
    private func save() {
        guard valid, let accountID else { return }
        let now = Dates.now
        let available = showsCurrentAvailable ? try? Money.parse(currentAvailable) : nil
        if store.update("哪天发工资", entryMotion: false, showToast: false, { ledger in
            try Payday.configure(day: day, amount: amount, accountID: accountID,
                                 currentPeriodAvailable: available.flatMap { $0 > .zero ? $0 : nil },
                                 in: &ledger, now: now)
        }) { dismiss() }
    }
}

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
        let preview = Payday.preview(due, amount: amount, extraToSavings: extraToSavings && delta > 0, in: store.current, now: Dates.now)
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
        if store.update("工资到了", { ledger in try Payday.confirm(due, amount: value, extraToSavings: extra, accountID: nil, in: &ledger, now: Dates.now) }) {
            dismiss()
        }
    }
}
