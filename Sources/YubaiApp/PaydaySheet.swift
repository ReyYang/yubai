import SwiftUI
import YubaiCore

/// 首次只设发薪日和平时的金额；到账仍由用户确认。
struct PaydaySetupSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var day = 10
    @State private var amount: Int64 = 0
    @State private var editingAmount = false
    @State private var keypad = EntryKeypad()
    @State private var accountID: UUID?
    private var valid: Bool { amount > 0 && amount <= Money.limit && accountID != nil }

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
                    }
                }
                days
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.sheetHeaderTop)
                .padding(.bottom, YubaiSpace.gapSection)
        }.paperBackground().accessibilityElement(children: .contain).accessibilityIdentifier("paydaySetupSheet")
            .onAppear { if accountID == nil { accountID = ManualBookkeeping.defaultAccount(in: store.current)?.id } }
            .sheet(isPresented: $editingAmount) {
                AmountEntrySheet(title: "工资", keypad: $keypad, primaryTitle: "好", primaryIdentifier: "paydaySetupAmountDone",
                                 canSave: keypad.canSave, save: {
                    guard let value = keypad.resolve(), value > 0 else { return }
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
        let now = Dates.now, calendar = Dates.calendar
        let today = Dates.day(now)
        let month = calendar.dateInterval(of: .month, for: today)!.start
        func scheduled(in start: Date) -> Date {
            let last = calendar.range(of: .day, in: .month, for: start)!.count
            return Dates.addDays(min(day, last) - 1, to: start)
        }
        let thisMonth = scheduled(in: month)
        let due = thisMonth < today ? scheduled(in: Dates.addMonths(1, to: month)) : thisMonth
        var plan = Plan(title: "工资", amount: amount, dueDate: due, frequency: .monthly, inflow: true, category: "工资", nature: .income)
        plan.monthlyDay = day; plan.accountID = accountID; plan.autoPay = false
        let change = ChangeSet(source: "用户操作", reason: "哪天发工资", items: [.addPlan(plan)])
        if store.apply(change, label: "哪天发工资", silently: true, finishing: { ledger in
            ledger.cycleAnchor = .payday
            Finance.enablePaydayConfirmation(&ledger, now: now)
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
