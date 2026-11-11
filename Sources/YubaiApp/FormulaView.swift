import SwiftUI
import YubaiCore

/// 现在 · 点还能花的数进来：手上的钱，减存着不动，减每月存，减还没付的固定账单，等于还能花。
/// 信用卡欠款、目标预留、没写用途的进账不为 0 时各多一行减项，保证算式对得上。
struct FormulaView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var pastCycles: [DateInterval] = []
    @State private var selectedStart: Date?
    @State private var closed: ClosedFormula?
    private var editingField: FormulaField? {
        if case .formulaEdit(let field)? = store.sheet { return field }
        return nil
    }
    var body: some View {
        let formula = store.formula
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            cycleLabel(formula)
            if selectedStart == nil {
                equationCard(formula)
                SpendingPartsCard()
                incomingBlock(formula)
            } else if let closed {
                closedCard(closed)
                closedWhereButton(closed)
            } else { ProgressView() }
        }.amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("formulaPage")
            .navigationTitle("还能花").yubaiNavigation()
            .task(id: historyKey) { await loadHistory() }
    }

    // MARK: 周期
    private var historyKey: String {
        "\(store.ledgerRevision)-\(store.formula.cycleStart)-\(String(describing: selectedStart))"
    }
    private func cycleLabel(_ formula: SpendableFormula) -> some View {
        let start = selectedStart ?? formula.cycleStart
        let end = pastCycles.first { $0.start == selectedStart }.map { Dates.addDays(-1, to: $0.end) } ?? formula.cycleEnd
        let text = cycleText(start, end)
        return Menu {
            Button(cycleText(formula.cycleStart, formula.cycleEnd)) { selectedStart = nil; closed = nil }
                .accessibilityIdentifier("formulaCycleCurrent")
            ForEach(Array(pastCycles.enumerated()), id: \.element.start) { index, cycle in
                Button(cycleText(cycle.start, Dates.addDays(-1, to: cycle.end))) { closed = nil; selectedStart = cycle.start }
                    .accessibilityIdentifier("formulaCyclePast_\(index)")
            }
        } label: {
            HStack(spacing: YubaiSpace.space4) {
                Text(text).yubaiFont(YubaiFont.callout)
                Image(systemName: "chevron.down").yubaiFont(YubaiFont.meta).accessibilityHidden(true)
            }.padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.tapMin)
                .background(YubaiColor.card, in: Capsule())
        }.buttonStyle(PressButtonStyle()).frame(maxWidth: .infinity)
            .accessibilityLabel("这个周期 " + text).accessibilityIdentifier("formulaCycle")
    }
    private func cycleText(_ start: Date, _ end: Date) -> String {
        FixedFlowPresentation.monthDay(start) + " – " + FixedFlowPresentation.monthDay(end)
    }
    @MainActor private func loadHistory() async {
        let ledger = store.current; let now = Date(); let selection = selectedStart
        let result = await Task.detached(priority: .userInitiated) {
            let cycles = Finance.pastCycles(ledger, now: now)
            let formula = selection.flatMap { start in
                cycles.contains { $0.start == start } ? Finance.closedFormula(ledger, cycleStart: start) : nil
            }
            return (cycles, formula)
        }.value
        guard !Task.isCancelled else { return }
        pastCycles = result.0; closed = result.1
        if selection != nil && result.1 == nil { selectedStart = nil }
    }

    private func closedCard(_ formula: ClosedFormula) -> some View {
        let saved = store.current.savingHistory.first { $0.cycleStart == formula.cycleStart }
        let status: String? = saved.flatMap { row in
            guard row.tracked else { return nil }
            return row.saved < row.target ? "少存 " + amount2(row.target - row.saved, hide: store.preferences.hideAmounts) : "存够了"
        }
        let handTitle = store.funds.cycleIsPayday ? "发工资那天手上" : "手上的钱"
        return Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                rowLabel(minus: false, title: handTitle, detail: FixedFlowPresentation.monthDay(formula.cycleStart), cents: formula.hand, chevron: false, highlighted: false)
                plainRow(title: "存着不动", cents: formula.fixedSavings, identifier: "closedFormulaFixed")
                divider
                rowLabel(minus: true, title: "每月存", detail: status, cents: formula.saving, chevron: false, highlighted: false)
                plainRow(title: "固定账单", cents: formula.bills, identifier: "closedFormulaBills")
                plainRow(title: "花掉的", cents: formula.spent, identifier: "closedFormulaSpent")
                formulaResult(title: "剩下", amount: formula.remaining, identifier: "closedFormulaResult")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("closedFormulaCard")
    }
    private func closedWhereButton(_ formula: ClosedFormula) -> some View {
        Button {
            store.resetRootNavigation()
            store.ledgerPreset = LedgerPreset(mode: .whereTo, interval: DateInterval(start: formula.cycleStart, end: Dates.addDays(1, to: formula.cycleEnd)))
            store.destination = .ledger
        } label: {
            HStack(spacing: YubaiSpace.space4) {
                Text("看这个周期花在哪")
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).accessibilityHidden(true)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("closedFormulaWhere")
    }

    // MARK: 算式
    private func equationCard(_ formula: SpendableFormula) -> some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                handRow(formula)
                if formula.creditDebt != 0 { plainRow(title: "信用卡欠款", cents: formula.creditDebt, identifier: "formulaRow_creditDebt") }
                if formula.goals != 0 { plainRow(title: "在存钱", cents: formula.goals, identifier: "formulaRow_goals") }
                if formula.uncertainInflow != 0 { plainRow(title: "没写用途的进账", cents: formula.uncertainInflow, identifier: "formulaRow_uncertainInflow") }
                divider
                editRow(title: "存着不动", detail: nil, cents: formula.fixedSavings, field: .fixedSavings,
                        identifier: "formulaRow_fixedSavings", buttonIdentifier: "editFixedSavings")
                divider
                editRow(title: "每月存", detail: "这个月已留出", cents: formula.saving, field: .saving,
                        identifier: "formulaRow_saving", buttonIdentifier: "editSavingTarget")
                divider
                billsBlock(formula)
                resultRow(formula)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("formulaCard")
    }
    private var divider: some View {
        Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true)
    }
    private func handRow(_ formula: SpendableFormula) -> some View {
        TabNavigationLink(.accounts) { AccountsView() } label: {
            rowLabel(minus: false, title: "手上的钱", detail: formula.handAccounts.joined(separator: "、"),
                     cents: formula.hand, chevron: true, highlighted: false)
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("手上的钱，" + amount2(formula.hand, hide: store.preferences.hideAmounts))
            .accessibilityElement(children: .contain).accessibilityIdentifier("formulaRow_hand")
    }
    private func plainRow(title: String, cents: Int64, identifier: String) -> some View {
        VStack(spacing: YubaiSpace.none) {
            divider
            rowLabel(minus: true, title: title, detail: nil, cents: cents, chevron: false, highlighted: false)
        }.accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }
    private func editRow(title: String, detail: String?, cents: Int64, field: FormulaField,
                         identifier: String, buttonIdentifier: String) -> some View {
        Button {
            store.sheetSource = nil; store.sheet = .formulaEdit(field)
        } label: {
            rowLabel(minus: true, title: title, detail: detail, cents: cents, chevron: true, highlighted: editingField == field)
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(title + "，" + amount2(cents, hide: store.preferences.hideAmounts))
            .accessibilityIdentifier(buttonIdentifier)
            .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
    private func rowLabel(minus: Bool, title: String, detail: String?, cents: Int64, chevron: Bool, highlighted: Bool) -> some View {
        let hide = store.preferences.hideAmounts
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) {
                signMark(minus)
                titleStack(title: title, detail: detail)
                Spacer(minLength: YubaiSpace.space8)
                AmountLabel(cents: cents, hide: hide, role: .amount).fixedSize(horizontal: true, vertical: false)
                chevronMark(chevron)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack(spacing: YubaiSpace.space8) { signMark(minus); titleStack(title: title, detail: detail); Spacer(minLength: YubaiSpace.none); chevronMark(chevron) }
                AmountLabel(cents: cents, hide: hide, role: .amount).padding(.leading, YubaiSpace.space16 + YubaiSpace.space8)
            }
        }.padding(.vertical, YubaiSpace.space8).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading)
            .background(highlighted ? YubaiColor.brandTint : Color.clear)
            .contentShape(Rectangle())
    }
    private func signMark(_ minus: Bool) -> some View {
        Text(minus ? "−" : "").yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelSecondary)
            .frame(width: YubaiSpace.space16, alignment: .leading).accessibilityHidden(true)
    }
    private func titleStack(title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(title).yubaiFont(YubaiFont.rowTitle)
            if let detail, !detail.isEmpty { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
        }
    }
    @ViewBuilder private func chevronMark(_ shown: Bool) -> some View {
        if shown {
            Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption, weight: .medium)
                .foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
        }
    }

    // MARK: 固定账单
    private func billsBlock(_ formula: SpendableFormula) -> some View {
        VStack(spacing: YubaiSpace.none) {
            TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: {
                rowLabel(minus: true, title: "固定账单还要付", detail: "这个周期 \(formula.billCount) 项，已付 \(formula.billsPaid) 项",
                         cents: formula.billsRest, chevron: true, highlighted: false)
            }.buttonStyle(PressButtonStyle()).accessibilityElement(children: .contain).accessibilityIdentifier("formulaRow_bills")
            ForEach(formula.bills) { row in FormulaBillRow(row: row) }
            addBillButton
        }
    }
    private var addBillButton: some View {
        Button {
            store.sheetSource = nil; store.sheet = .addBill
        } label: {
            HStack(spacing: YubaiSpace.space8) {
                Image(systemName: "plus").accessibilityHidden(true)
                Text("添加")
            }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                .padding(.leading, YubaiSpace.space16 + YubaiSpace.space8)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaAddBill")
    }

    // MARK: 结果
    private func resultRow(_ formula: SpendableFormula) -> some View {
        formulaResult(title: "还能花", amount: formula.available, identifier: "formulaResult")
    }
    private func formulaResult(title: String, amount: Int64, identifier: String) -> some View {
        let ink = amount < 0 ? YubaiColor.amberInk : YubaiColor.brandInk
        return VStack(spacing: YubaiSpace.none) {
            Rectangle().fill(YubaiColor.label).frame(height: 2).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) {
                    Text("=").yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelSecondary)
                        .frame(width: YubaiSpace.space16, alignment: .leading).accessibilityHidden(true)
                    Text(title).yubaiFont(YubaiFont.rowTitle, weight: .semibold)
                    Spacer(minLength: YubaiSpace.space8)
                    AmountLabel(cents: amount, hide: store.preferences.hideAmounts, role: .account, ink: ink)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text(title).yubaiFont(YubaiFont.rowTitle, weight: .semibold)
                    AmountLabel(cents: amount, hide: store.preferences.hideAmounts, role: .account, ink: ink)
                }
            }.padding(.vertical, YubaiSpace.space12).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading)
        }.accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }

    // MARK: 要进来的
    @ViewBuilder private func incomingBlock(_ formula: SpendableFormula) -> some View {
        if !formula.incoming.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                Text("要进来的").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    .padding(.leading, YubaiSpace.insetCard)
                CardRows(formula.incoming, rowHeight: YubaiSize.rowSingle) { row in incomingRow(row) }
            }
        }
    }
    private func incomingRow(_ row: Occurrence) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text(FixedFlowPresentation.monthDay(row.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Text(row.title).yubaiFont(YubaiFont.row)
                Spacer(minLength: YubaiSpace.space8)
                AmountLabel(cents: row.amount, hide: store.preferences.hideAmounts, role: .small, sign: .inflow, ink: YubaiColor.brandInk)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text(FixedFlowPresentation.monthDay(row.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    Text(row.title).yubaiFont(YubaiFont.row)
                }
                AmountLabel(cents: row.amount, hide: store.preferences.hideAmounts, role: .small, sign: .inflow, ink: YubaiColor.brandInk)
            }.padding(.vertical, YubaiSpace.space8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 没付的账单长按出菜单，付过的不出。
private struct RowMenuIfOpen: ViewModifier {
    let open: Bool
    let planID: UUID
    let occurrence: Date
    @ViewBuilder func body(content: Content) -> some View {
        if open { content.billRowMenu(planID: planID, occurrence: occurrence) } else { content }
    }
}

/// 算式里的一行账单：日期、名字、金额，右边是和首页同一颗勾；付过的变灰沉底。
private struct FormulaBillRow: View {
    @Environment(AppStore.self) private var store
    let row: FixedFlowOccurrence
    private var paid: Bool { row.state == .paid }
    private var ink: Color { paid ? YubaiColor.labelSecondary : YubaiColor.label }
    var body: some View {
        HStack(spacing: YubaiSpace.space8) {
            if let planID = row.planID {
                TabNavigationLink(.billDetail(planID)) { BillDetailView(planID: planID) } label: { summary }
                    .buttonStyle(PressButtonStyle()).accessibilityLabel("看" + row.title)
                    .accessibilityValue(FixedFlowPresentation.monthDay(row.date))
                    .accessibilityIdentifier("formulaBill_" + planID.uuidString)
                    .modifier(RowMenuIfOpen(open: !paid, planID: planID, occurrence: row.date))
                BillCheck(planID: planID, occurrence: row.date)
            } else {
                summary
                Color.clear.frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).accessibilityHidden(true)
            }
        }.padding(.leading, YubaiSpace.space16 + YubaiSpace.space8).frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin)
            .accessibilityElement(children: .contain).accessibilityValue(paid ? "已付" : "")
    }
    private var summary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.gapGroup) {
                dateText.frame(minWidth: 64, alignment: .leading)
                Text(row.title).yubaiFont(YubaiFont.row).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: YubaiSpace.space8)
                amountView
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    dateText
                    Text(row.title).yubaiFont(YubaiFont.row).foregroundStyle(ink)
                }
                amountView
            }.padding(.vertical, YubaiSpace.space8)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private var dateText: some View {
        Text(FixedFlowPresentation.monthDay(row.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    private var amountView: some View {
        HStack(spacing: YubaiSpace.space4) {
            if row.estimated { Text("约").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            AmountLabel(cents: row.amount, hide: store.preferences.hideAmounts, role: .small, sign: .none, ink: ink)
        }.fixedSize(horizontal: true, vertical: false)
    }
}

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
            .presentationDetents([.height(660), .large])
            #endif
    }
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text(title).yubaiFont(YubaiFont.entrySheetTitle)
            Spacer(minLength: YubaiSpace.space8)
            Button("取消") { dismiss() }
                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.label)
                .padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.tapMin)
                .background(YubaiColor.card, in: Capsule()).contentShape(Capsule())
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("amountSheetCancel")
        }
    }
    private var modePicker: some View {
        SegmentedWide(choices: [(false, "固定金额"), (true, "每笔进账留几成")], selection: modeBinding,
                      identifier: { $0 ? "savingMode_share" : "savingMode_fixed" })
    }
    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            if !sharing { Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary) }
            Text(sharing ? "\(percent)%" : keypad.resultText).yubaiFont(YubaiFont.entryAmount)
                .padding(.horizontal, 6)
                .background(selected ? YubaiColor.brandTint : Color.clear, in: RoundedRectangle(cornerRadius: 10))
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
