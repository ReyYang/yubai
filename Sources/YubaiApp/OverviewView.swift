import SwiftUI
import YubaiCore

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

extension Funds {
    var horizonTitle: String { "到 " + FixedFlowPresentation.monthDay(cycleEnd) }
}

struct SavingsView: View {
    @Environment(AppStore.self) private var store
    let backTitle: String
    @State private var editing: SavingsAmountField?
    @State private var addingPayday = false
    private var hide: Bool { store.preferences.hideAmounts }
    private var fixed: Int64 { store.funds.fixedSavingsTotal }
    private var sharing: Bool { if case .share = store.current.savingRule { true } else { false } }
    private var percent: Int { if case .share(let value) = store.current.savingRule { value } else { 20 } }
    private var target: Int64 { store.funds.savingTarget }
    private var fixedTarget: Int64 { if case .fixed(let amount) = store.current.savingRule { amount } else { 0 } }
    private var suggestion: (average: Int64, suggestion: Int64)? {
        guard !sharing, fixedTarget == 0, let value = Reserve.suggestedMonthly(store.current, now: Date()), value.suggestion > 0 else { return nil }
        return value
    }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            hero
            howCard
            if !directIncome.isEmpty { directSection }
            if !history.isEmpty { historySection }
        }.safeAreaInset(edge: .top, spacing: 0) { LedgerPageHeader(title: "每月存", backTitle: backTitle).padding(.horizontal, 20) }
            .amountPrivacy(hide)
            .navigationTitle("每月存").yubaiNavigation().accessibilityIdentifier("savingsPage")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(item: $editing) { field in
                SavingsAmountEditor(field: field, initial: field == .fixed ? fixed : field == .target ? fixedTarget : Int64(percent) * 100) { value in
                    store.update("存钱") { ledger in
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

    // MARK: 存着不动
    private var hero: some View {
        VStack(spacing: YubaiSpace.space4) {
            Text("存着不动").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            HStack(spacing: YubaiSpace.gapGroup) {
                AmountLabel(cents: fixed, hide: hide, role: .hero)
                Button { editing = .fixed } label: {
                    Image(systemName: "pencil").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                        .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).controlSurface(in: Circle()).yubaiHitTarget()
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("修改存着不动").accessibilityIdentifier("editFixedSavings")
            }
            if target > 0 || store.reserve.setAside > 0 {
                Text("这个月已存进 " + amount2(store.reserve.setAside, hide: hide)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
            }
        }.frame(maxWidth: .infinity)
    }

    // MARK: 怎么存
    private var howCard: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Text("怎么存").yubaiFont(YubaiFont.rowTitle)
                SegmentedWide(choices: [(false, "固定金额"), (true, "每笔进账留几成")], selection: Binding(get: { sharing }, set: { value in
                    store.update("存钱") { $0.switchSavingMode(sharing: value) }
                }), identifier: { $0 ? "savingMode_share" : "savingMode_fixed" }).accessibilityIdentifier("savingMode")
                EntryFormDivider()
                if sharing { shareChoices } else { fixedTargetRow }
                EntryFormDivider()
                Text("每月从哪天算").yubaiFont(YubaiFont.rowTitle)
                cycleAnchorControl
            }
        }
    }
    private var fixedTargetRow: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { targetTitle.fixedSize(); Spacer(minLength: 8); amountButton(fixedTarget).fixedSize() }
                VStack(alignment: .leading, spacing: 8) { targetTitle; amountButton(fixedTarget) }
            }
            if let suggestion { suggestionChip(suggestion) }
        }
    }
    private var targetTitle: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text("每月存").yubaiFont(YubaiFont.row)
            if fixedTarget > 0 && store.funds.cycleIsPayday { Text("发工资那天先留出").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
        }
    }
    private func amountButton(_ value: Int64) -> some View {
        Button { editing = .target } label: {
            AmountLabel(cents: value, hide: hide, role: .summary)
                .padding(.horizontal, 12).frame(minHeight: YubaiSize.tapMin - 8).background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: 12))
                .frame(minHeight: YubaiSize.tapMin)
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("修改每月存").accessibilityIdentifier("editSavingTarget")
    }
    private func suggestionChip(_ value: (average: Int64, suggestion: Int64)) -> some View {
        let text = "前三个月平均结余 " + amount2(value.average, hide: hide) + " · 每月存 " + amount2(value.suggestion, hide: hide)
        return Button {
            store.update("存钱") { $0.savingRule = .fixed(value.suggestion) }
        } label: {
            Text(text).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).multilineTextAlignment(.leading)
                .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
                .frame(minHeight: YubaiSize.tapMin, alignment: .leading)
                .background(YubaiColor.brandTint, in: RoundedRectangle(cornerRadius: YubaiRadius.row)).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("suggestedMonthlySaving")
    }
    private var shareChoices: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            Text("每笔进账留").yubaiFont(YubaiFont.rowTitle)
            ChipFlow {
                ForEach([10, 20, 30], id: \.self) { value in
                    Button(savingShare(value)) { store.update("存钱") { $0.savingRule = .share(value) } }
                        .buttonStyle(SavingsChoiceStyle(selected: percent == value))
                }
                Button("自定") { editing = .share }.buttonStyle(SavingsChoiceStyle(selected: ![10, 20, 30].contains(percent)))
            }
        }
    }
    private var cycleAnchorControl: some View {
        SegmentedWide(choices: [(true, "发工资那天"), (false, "每月 1 号")], selection: Binding(get: { store.funds.cycleIsPayday }, set: { payday in
            if payday {
                var monthly = store.current
                monthly.plans.removeAll { $0.frequency != .monthly }
                if Finance.nextPayday(in: monthly, now: Date()) == nil { addingPayday = true; return }
            }
            store.update("存钱") { $0.cycleAnchor = payday ? .payday : .calendarMonth }
        }), identifier: { $0 ? "savingCycleAnchor_payday" : "savingCycleAnchor_month" }).accessibilityIdentifier("savingCycleAnchor")
    }

    // MARK: 直接放进来的
    private var directIncome: [Entry] { store.sortedEntries.filter { $0.deletedAt == nil && $0.nature == .income && $0.intoFixedSavings } }
    private var directSection: some View {
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
    private func directIncomeTitle(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayTitle).yubaiFont(YubaiFont.row)
            Text(FixedFlowPresentation.monthDay(entry.date) + " · " + store.accountName(entry.accountID))
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func directIncomeAmount(_ entry: Entry) -> some View {
        AmountLabel(cents: entry.amount, hide: hide, sign: .inflow, ink: YubaiColor.brandInk)
    }

    // MARK: 每月存下
    private var history: [CycleSaving] { store.current.savingHistory.filter(\.tracked).sorted { $0.cycleStart > $1.cycleStart } }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("每月存下").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, 16)
            Card(style: .list) {
                VStack(spacing: 0) {
                    ForEach(history) { row in
                        historyRow(row)
                        if row.id != history.last?.id { EntryFormDivider() }
                    }
                }
            }
        }
    }
    private func historyRow(_ row: CycleSaving) -> some View {
        let short = row.saved < row.target
        let month = "\(Dates.calendar.component(.month, from: row.cycleEnd))月"
        let status = row.income == 0 && row.target == 0 ? "没进账" : short ? "少存 " + amount2(row.target - row.saved, hide: hide) : "存够了"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { Text(month).yubaiFont(YubaiFont.row); Spacer(minLength: 0); statusLabel(status, short: short, done: !short); AmountLabel(cents: row.saved, hide: hide, role: .summary) }
            VStack(alignment: .leading, spacing: 4) { Text(month).yubaiFont(YubaiFont.row); statusLabel(status, short: short, done: !short); AmountLabel(cents: row.saved, hide: hide, role: .summary) }.padding(.vertical, 8)
        }.frame(minHeight: 48).accessibilityElement(children: .combine)
    }
    private func statusLabel(_ text: String, short: Bool, done: Bool) -> some View {
        HStack(spacing: 4) {
            if done && text == "存够了" { Image(systemName: "checkmark") }
            Text(text)
        }.yubaiFont(YubaiFont.caption).foregroundStyle(short ? YubaiColor.amberInk : YubaiColor.brandInk)
    }
}

private enum SavingsAmountField: String, Identifiable { case fixed, target, share, salary; var id: String { rawValue } }
private struct SavingsChoiceStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular)
            .foregroundStyle(selected ? YubaiColor.onBrand : YubaiColor.label)
            .padding(.horizontal, 20).frame(minHeight: YubaiSize.tapMin)
            .background(selected ? YubaiColor.label : YubaiColor.raised, in: Capsule())
            .contentShape(Capsule()).opacity(configuration.isPressed ? 0.7 : 1)
            .accessibilityAddTraits(selected ? .isSelected : [])
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
