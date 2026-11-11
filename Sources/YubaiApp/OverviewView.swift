import SwiftUI
import YubaiCore

struct LedgerHomeView: View {
    var body: some View { EntriesView() }
}

struct LedgerHero: View {
    @Environment(AppStore.self) private var store
    private var funds: Funds { store.funds }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TabNavigationLink(.formula) { FormulaView() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("还能花").yubaiFont(YubaiFont.heroLabel)
                        Text(funds.horizonTitle).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        AmountLabel(cents: funds.available, hide: store.preferences.hideAmounts, role: .hero,
                                    ink: funds.available < 0 ? YubaiColor.amberInk : YubaiColor.label)
                            .accessibilityIdentifier("availableFunds")
                        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).yubaiZoomSource("funds").accessibilityIdentifier("fundsFormula")
                .accessibilityLabel("还能花，" + funds.horizonTitle + "，" + (store.preferences.hideAmounts ? "金额已隐藏" : Money.text(funds.available)))
                .accessibilityHint("点开看怎么算")
            ChipFlow {
                if funds.available < 0 {
                    chip("这个月少攒 " + compact(funds.savingShortfall), amber: true)
                    chip("要攒 " + compact(funds.savingTarget))
                } else {
                    chip("每天约 " + (store.preferences.hideAmounts ? "••••" : savingDaily(funds.dailyAllowance)))
                    HStack(spacing: 6) {
                        if case .share = store.current.savingRule {} else { Image(systemName: "lock").font(.system(size: 12)) }
                        Text(savingChip)
                    }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk)
                        .padding(.horizontal, 12).frame(minHeight: 28).background(YubaiColor.brandTint, in: Capsule())
                }
            }
            if !store.current.spendingParts.isEmpty { SpendingPartsCard().padding(.top, 6) }
        }.foregroundStyle(YubaiColor.label).amountPrivacy(store.preferences.hideAmounts)
    }
    private var savingChip: String {
        if case .share(let percent) = store.current.savingRule { return "进账留" + savingShare(percent) + " · " + compact(funds.savingTarget) }
        return "要攒 " + compact(funds.savingTarget) + " · 已留出"
    }
    private func compact(_ value: Int64) -> String { store.preferences.hideAmounts ? "••••" : savingNumber(value) }
    private func chip(_ text: String, amber: Bool = false) -> some View {
        Text(text).yubaiFont(YubaiFont.caption).foregroundStyle(amber ? YubaiColor.amberInk : YubaiColor.label)
            .padding(.horizontal, 12).frame(minHeight: 28).background(amber ? YubaiColor.amberTint : YubaiColor.raised, in: Capsule())
    }
}

func savingNumber(_ value: Int64) -> String {
    let text = Money.text(value, currency: false)
    return text.hasSuffix(".00") ? String(text.dropLast(3)) : text
}
func savingDaily(_ value: Int64) -> String { savingNumber((value + 50) / 100 * 100) }
func savingShare(_ percent: Int) -> String {
    switch percent { case 10: "一成"; case 20: "两成"; case 30: "三成"; default: "\(percent)%" }
}

struct FundsCalculationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var funds: Funds { store.funds }
    private var incomeRows: [Entry] { store.sortedEntries.filter { $0.deletedAt == nil && $0.nature == .income && $0.date >= funds.cycleStart && $0.date <= Date() } }
    var body: some View {
        Page(spacing: 12, topPadding: 8) {
            Text(FixedFlowPresentation.monthDay(funds.cycleStart) + " – " + FixedFlowPresentation.monthDay(funds.cycleEnd))
                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).frame(maxWidth: .infinity)
            composition.padding(.bottom, 8)
            Card(style: .list) {
                VStack(spacing: 0) {
                    formula("流动资金", funds.liquidStart, detail: liquidDetail)
                    formula(funds.cycleIsPayday ? "这个月收入" : "这个月到账", funds.cycleIncome, detail: incomeDetail, inflow: true)
                    formula(savingTitle, -funds.savingTarget)
                    formula("已经花了", -funds.cycleSpent, detail: spentDetail)
                    formula("还要付", -funds.dueRest, detail: dueDetail)
                    formula("还能花", funds.available, total: true)
                }
            }
            NavigationLink { SavingsView(backTitle: "还能花") } label: {
                HStack(spacing: 8) {
                    Text("存着不动和每月要攒").yubaiFont(YubaiFont.row)
                    Spacer(minLength: 4)
                    Text(savingsSummary(store.current)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                }.padding(.horizontal, 16).frame(minHeight: 52).paperCardSurface(in: Capsule())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openSavings")
            NavigationLink { SpendingPartsView(backTitle: "还能花") } label: {
                HStack {
                    Text("分项").yubaiFont(YubaiFont.row)
                    Spacer()
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                }.padding(.horizontal, 16).frame(minHeight: 52).paperCardSurface(in: Capsule())
            }.buttonStyle(PressButtonStyle()).accessibilityLabel("分项，分配还能花").accessibilityIdentifier("openSpendingParts")
        }.accessibilityIdentifier("fundsCalculationPage").amountPrivacy(store.preferences.hideAmounts)
            .safeAreaInset(edge: .top, spacing: 0) { LedgerSheetHeader(title: "还能花怎么算", done: { dismiss() }).padding(.horizontal, 20) }
            .manualSheetNavigation()
    }
    private var savingTitle: String {
        if case .share(let percent) = store.current.savingRule { return "进账留" + savingShare(percent) }
        return "这个月要攒"
    }
    private var liquidDetail: String {
        guard !store.preferences.hideAmounts else { return "" }
        if funds.debt > 0 || funds.goals > 0 || funds.uncertainInflow > 0 { return "存着不动 " + savingNumber(store.funds.fixedSavingsTotal) }
        return "存款 " + savingNumber(funds.liquidStart + funds.fixedSavingsTotal) + " − 存着不动 " + savingNumber(store.funds.fixedSavingsTotal)
    }
    private var incomeDetail: String? {
        guard !incomeRows.isEmpty else { return nil }
        if funds.cycleIsPayday, let first = incomeRows.first { return first.displayTitle + " · " + FixedFlowPresentation.monthDay(first.date) }
        return "\(incomeRows.count) 笔 · " + incomeRows.prefix(2).map { FixedFlowPresentation.monthDay($0.date) }.joined(separator: "、")
    }
    private var spentDetail: String? {
        guard !store.preferences.hideAmounts else { return nil }
        let rent = store.sortedEntries.filter { $0.deletedAt == nil && $0.date >= funds.cycleStart && $0.date <= Date() && $0.nature == .expense && ($0.rentID != nil || $0.title.contains("房租")) }
            .reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: store.current) }
        return rent > 0 ? "含房租 " + savingNumber(rent) : nil
    }
    private var dueDetail: String? {
        let repayments = Set(store.plans.filter { $0.nature == .repayment }.map(\.id))
        return funds.occurrences.first { !$0.inflow && Dates.day($0.date) <= funds.cycleEnd && !($0.planID.map { repayments.contains($0) } ?? false) }
            .map { $0.title + " · " + FixedFlowPresentation.monthDay($0.date) }
    }
    private var composition: some View {
        let values = [max(0, funds.cycleSpent), max(0, funds.dueRest), max(0, funds.available), max(0, funds.savingTarget)]
        let total = max(1, values.reduce(Int64(0), +))
        let colors = [YubaiColor.neutralStrong, YubaiColor.neutralSoft, YubaiColor.brand, YubaiColor.brandTint]
        return VStack(spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(values.indices, id: \.self) { index in
                        Rectangle().fill(colors[index])
                            .overlay { if index == 3 { Rectangle().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }
                            .frame(width: max(0, geometry.size.width - 6) * CGFloat(values[index]) / CGFloat(total))
                    }
                }.clipShape(Capsule())
            }.frame(height: 12)
            HStack {
                ForEach(["已花", "要付", "还能花", "要攒"], id: \.self) { title in
                    Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("已花、要付、还能花、要攒的构成")
    }
    private func formula(_ title: String, _ amount: Int64, detail: String? = nil, inflow: Bool = false, total: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).yubaiFont(YubaiFont.row, weight: total ? .semibold : .regular)
                    if let detail, !detail.isEmpty { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                }
                Spacer(minLength: 0)
                AmountLabel(cents: amount, hide: store.preferences.hideAmounts, role: total ? .summary : .amount,
                            sign: inflow ? .inflow : .automatic, ink: total ? (amount < 0 ? YubaiColor.amberInk : YubaiColor.brandInk) : YubaiColor.label)
            }.frame(minHeight: 50)
            if !total { EntryFormDivider() }
        }
    }
}

func savingsSummary(_ ledger: Ledger) -> String {
    guard !ledger.preferences.hideAmounts else { return "••••" }
    let rule: String
    if case .share(let percent) = ledger.savingRule { rule = savingShare(percent) }
    else if case .fixed(let amount) = ledger.savingRule { rule = savingNumber(amount) }
    else { rule = "0" }
    return savingNumber(ledger.fixedSavingsTotal()) + " · " + rule
}

extension Funds {
    var horizonTitle: String { "到 " + FixedFlowPresentation.monthDay(cycleEnd) }
}

struct SavingsView: View {
    @Environment(AppStore.self) private var store
    let backTitle: String
    @State private var editing: SavingsAmountField?
    @State private var addingPayday = false
    private var fixed: Int64 { store.funds.fixedSavingsTotal }
    private var sharing: Bool { if case .share = store.current.savingRule { true } else { false } }
    private var percent: Int { if case .share(let value) = store.current.savingRule { value } else { 20 } }
    private var target: Int64 { store.funds.savingTarget }
    private var fixedTarget: Int64 { if case .fixed(let amount) = store.current.savingRule { amount } else { 0 } }
    var body: some View {
        Page(spacing: 24, topPadding: 8) {
            VStack(spacing: 4) {
                Text("存着不动").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                Text(store.preferences.hideAmounts ? "••••" : Money.text(fixed)).yubaiFont(YubaiFont.savingsHero).lineLimit(1).minimumScaleFactor(0.7)
                Text(store.preferences.hideAmounts ? "••••" : sharing ? "这个月已留 " + Money.text(target, currency: false) : "这个月攒完 → " + Money.text(fixed + target, currency: false))
                    .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
            }.frame(maxWidth: .infinity).padding(.bottom, 4)
            Card(style: .list) {
                VStack(spacing: 0) {
                    savingsAmountRow("存着不动", subtitle: "不算进还能花", value: fixed, field: .fixed)
                    EntryFormDivider()
                    ViewThatFits(in: .horizontal) {
                        HStack { Text("要攒").fixedSize(); Spacer(minLength: 8); savingMode.fixedSize() }
                        VStack(alignment: .leading, spacing: 8) { Text("要攒"); savingMode }
                    }.yubaiFont(YubaiFont.row).padding(.vertical, 8).frame(minHeight: 56)
                    EntryFormDivider()
                    if sharing {
                        ChipFlow {
                            Text("每笔进账留").yubaiFont(YubaiFont.row)
                            ForEach([10, 20, 30], id: \.self) { value in
                                Button(savingShare(value)) { store.update("攒钱") { $0.savingRule = .share(value) } }
                                    .buttonStyle(SavingsChoiceStyle(selected: percent == value))
                            }
                            Button("自定") { editing = .share }.buttonStyle(SavingsChoiceStyle(selected: ![10, 20, 30].contains(percent)))
                        }.frame(minHeight: 56)
                    } else {
                        savingsAmountRow("每月要攒", subtitle: store.funds.cycleIsPayday ? "发工资那天先留出" : nil, value: fixedTarget, field: .target)
                    }
                    EntryFormDivider()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { Text("每月从哪天算").fixedSize(); Spacer(minLength: 8); cycleAnchorControl.fixedSize() }
                        VStack(alignment: .leading, spacing: 8) { Text("每月从哪天算"); cycleAnchorControl }
                    }.yubaiFont(YubaiFont.row).padding(.vertical, 8).frame(minHeight: 56)
                }
            }
            if !directIncome.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("直接放进来的").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, 16)
                    CardRows(directIncome) { entry in
                        NavigationLink { EntryDetailView(entryID: entry.id) } label: {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { directIncomeTitle(entry).fixedSize(); Spacer(minLength: 8); directIncomeAmount(entry).fixedSize() }
                                VStack(alignment: .leading, spacing: 8) { directIncomeTitle(entry); directIncomeAmount(entry) }
                            }.frame(minHeight: 56).contentShape(Rectangle())
                        }.hidesListDisclosure().buttonStyle(PressButtonStyle()).accessibilityIdentifier("directSavingsEntry_" + entry.id.uuidString)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("每月攒下").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, 16)
                if store.current.savingHistory.contains(where: \.tracked) {
                    Card(style: .list) {
                        VStack(spacing: 0) {
                            let history = store.current.savingHistory.filter(\.tracked).sorted { $0.cycleStart > $1.cycleStart }
                            ForEach(history) { row in
                                historyRow(row)
                                if row.id != history.last?.id { EntryFormDivider() }
                            }
                        }
                    }
                }
            }
        }.safeAreaInset(edge: .top, spacing: 0) { LedgerPageHeader(title: "攒钱", backTitle: backTitle).padding(.horizontal, 20) }
            .navigationTitle("攒钱").yubaiNavigation().accessibilityIdentifier("savingsPage")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(item: $editing) { field in
                SavingsAmountEditor(field: field, initial: field == .fixed ? fixed : field == .target ? fixedTarget : Int64(percent) * 100) { value in
                    store.update("攒钱") { ledger in
                        switch field {
                        case .fixed: ledger.setFixedSavingsTotal(value)
                        case .target: ledger.savingRule = .fixed(value)
                        case .share: ledger.savingRule = .share(Int(value / 100))
                        case .salary: break
                        }
                    }
                }.environment(store).yubaiSheetBackground().presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $addingPayday) { SavingsPaydayEditor().environment(store).yubaiSheetBackground() }
    }
    private func savingsAmountRow(_ title: String, subtitle: String?, value: Int64, field: SavingsAmountField) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { savingsAmountTitle(title, subtitle: subtitle).fixedSize(); Spacer(minLength: 8); amountButton(value, field: field).fixedSize() }
            VStack(alignment: .leading, spacing: 8) { savingsAmountTitle(title, subtitle: subtitle); amountButton(value, field: field) }.padding(.vertical, 8)
        }.frame(minHeight: 56)
    }
    private func savingsAmountTitle(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).yubaiFont(YubaiFont.row)
            if let subtitle { Text(subtitle).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
        }
    }
    private func amountButton(_ value: Int64, field: SavingsAmountField) -> some View {
        Button { editing = field } label: {
            AmountLabel(cents: value, hide: store.preferences.hideAmounts, role: .summary)
                .padding(.horizontal, 12).frame(minHeight: 36).background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(field == .fixed ? "修改存着不动" : "修改每月要攒")
            .accessibilityIdentifier(field == .fixed ? "editFixedSavings" : "editSavingTarget")
    }
    private var savingMode: some View {
        Segmented(choices: [(false, "固定金额"), (true, "每笔进账留")], selection: Binding(get: { sharing }, set: { value in
            store.update("攒钱") { $0.switchSavingMode(sharing: value) }
        })).accessibilityIdentifier("savingMode")
    }
    private var cycleAnchorControl: some View {
        Segmented(choices: [(true, "发工资那天"), (false, "每月 1 号")], selection: Binding(get: { store.funds.cycleIsPayday }, set: { payday in
            if payday {
                var monthly = store.current
                monthly.plans.removeAll { $0.frequency != .monthly }
                if Finance.nextPayday(in: monthly, now: Date()) == nil { addingPayday = true; return }
            }
            store.update("攒钱") { $0.cycleAnchor = payday ? .payday : .calendarMonth }
        })).accessibilityIdentifier("savingCycleAnchor")
    }
    private var directIncome: [Entry] { store.sortedEntries.filter { $0.deletedAt == nil && $0.nature == .income && $0.intoFixedSavings } }
    private func directIncomeTitle(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayTitle).yubaiFont(YubaiFont.row)
            Text(FixedFlowPresentation.monthDay(entry.date) + " · " + store.accountName(entry.accountID))
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func directIncomeAmount(_ entry: Entry) -> some View {
        AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts, sign: .inflow, ink: YubaiColor.brandInk)
    }
    private func historyRow(_ row: CycleSaving) -> some View {
        HStack(spacing: 8) {
            Text("\(Dates.calendar.component(.month, from: row.cycleEnd))月" + (sharing ? (row.income == 0 ? " · 没进账" : " · 进账 " + (store.preferences.hideAmounts ? "••••" : savingNumber(row.income))) : ""))
                .yubaiFont(YubaiFont.row)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if row.saved == row.target { Image(systemName: "checkmark") }
                Text(row.income == 0 && row.target == 0 ? "没进账" : row.saved >= row.target ? "攒够了" : "少攒 " + (store.preferences.hideAmounts ? "••••" : savingNumber(row.target - row.saved)))
            }.yubaiFont(YubaiFont.caption).foregroundStyle(row.saved < row.target ? YubaiColor.amberInk : YubaiColor.brandInk)
            AmountLabel(cents: row.saved + row.leftover, hide: store.preferences.hideAmounts)
        }.frame(minHeight: 48)
    }
}

private enum SavingsAmountField: String, Identifiable { case fixed, target, share, salary; var id: String { rawValue } }
private struct SavingsChoiceStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular).padding(.horizontal, 10).frame(minHeight: 32)
            .background(selected ? YubaiColor.raised : .clear, in: Capsule())
            .overlay { if selected { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
private struct SavingsAmountEditor: View {
    @Environment(\.dismiss) private var dismiss
    let field: SavingsAmountField
    let save: (Int64) -> Bool
    @State private var keypad: EntryKeypad
    @State private var selected = true
    init(field: SavingsAmountField, initial: Int64, save: @escaping (Int64) -> Bool) {
        self.field = field; self.save = save; _keypad = State(initialValue: EntryKeypad(amount: initial))
    }
    private var title: String { field == .fixed ? "存着不动" : field == .target ? "每月要攒" : field == .salary ? "大概多少" : "每笔进账留" }
    private var valid: Bool {
        guard let value = keypad.amount else { return false }
        return field == .share ? value % 100 == 0 && (100...9000).contains(value) : field == .salary ? value > 0 : value >= 0
    }
    var body: some View {
        VStack(spacing: 16) {
            LedgerSheetHeader(title: title, done: { dismiss() }).padding(.horizontal, 20)
            Text(keypad.resultText + (field == .share ? "%" : "")).yubaiFont(YubaiFont.amountInput).padding(.horizontal, 20)
            AmountKeypad(keypad: $keypad, amountSelected: $selected, canSave: valid, primaryTitle: "完成", primaryIdentifier: "saveSavingsAmount", save: {
                guard valid, let value = keypad.resolve() else { return }
                if save(value) { dismiss() }
            })
        }.presentationDetents([.height(440 + YubaiSpace.sheetHeaderTop)])
    }
}

private struct SavingsPaydayEditor: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var day = min(28, Dates.calendar.component(.day, from: Date()))
    @State private var amount: Int64 = 0
    @State private var accountID: UUID?
    @State private var editingAmount = false
    private var accounts: [Account] { store.accounts.filter { !$0.archived } }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(style: .list) {
                    VStack(spacing: 0) {
                        EntryFormRow(title: "每月几号") { Text("\(day) 号").foregroundStyle(YubaiColor.labelSecondary) }.frame(minHeight: 48)
                        EntryFormDivider()
                        EntryFormRow(title: "大概多少") {
                            Button { editingAmount = true } label: {
                                AmountLabel(cents: amount, role: .summary).padding(.horizontal, 12).frame(minHeight: 36)
                                    .background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: 12))
                            }.accessibilityLabel("大概多少").accessibilityIdentifier("paydayAmount")
                        }.frame(minHeight: 48)
                        EntryFormDivider()
                        EntryFormRow(title: "到哪张卡") {
                            Menu {
                                ForEach(accounts) { account in Button(account.name) { accountID = account.id } }
                            } label: { Text(store.accountName(accountID)).foregroundStyle(YubaiColor.labelSecondary) }
                                .accessibilityIdentifier("paydayAccount")
                        }.frame(minHeight: 48)
                    }.yubaiFont(YubaiFont.row)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: textSize.isAccessibilitySize ? 4 : 7), spacing: 6) {
                    ForEach(1...28, id: \.self) { value in
                        Button { day = value } label: {
                            Text("\(value)").yubaiFont(YubaiFont.callout).lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(day == value ? YubaiColor.onBrand : YubaiColor.label)
                                .background(day == value ? YubaiColor.label : YubaiColor.raised, in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityLabel("每月 \(value) 号").accessibilityAddTraits(day == value ? .isSelected : [])
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }.safeAreaInset(edge: .top, spacing: 0) {
            ManualSheetHeader(title: "发工资那天", actionTitle: "好", enabled: amount > 0 && accountID != nil, cancel: { dismiss() }, action: save).padding(.horizontal, 20)
        }.buttonStyle(PressButtonStyle()).paperBackground()
            .onAppear { accountID = ManualBookkeeping.defaultAccount(in: store.current)?.id }
            .sheet(isPresented: $editingAmount) {
                SavingsAmountEditor(field: .salary, initial: amount) { value in amount = value; return true }.yubaiSheetBackground()
            }
            .presentationDetents([.large])
    }
    private func save() {
        guard amount > 0, let accountID else { return }
        let month = Dates.calendar.dateInterval(of: .month, for: Date())!.start
        // Start at the next payday so a day already passed this month isn't shown as due.
        let thisMonth = Dates.addDays(day - 1, to: month)
        let due = thisMonth < Dates.day(Date()) ? Dates.addMonths(1, to: thisMonth) : thisMonth
        var plan = Plan(title: "工资", amount: amount, dueDate: due, frequency: .monthly, inflow: true, category: "工资", nature: .income)
        plan.accountID = accountID; plan.monthlyDay = day
        let change = ChangeSet(source: "用户操作", reason: "添加工资", items: [.addPlan(plan)])
        if store.apply(change, label: "发工资那天", finishing: { $0.cycleAnchor = .payday }) { dismiss() }
    }
}
