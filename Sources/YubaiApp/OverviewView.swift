import SwiftUI
import YubaiCore

func savingNumber(_ value: Int64) -> String {
    AmountLabel.text(value)
}
func savingDaily(_ value: Int64) -> String { savingNumber(value) }
func savingShare(_ percent: Int) -> String {
    switch percent { case 10: "一成"; case 20: "两成"; case 30: "三成"; default: "\(percent)%" }
}

extension Funds {
    var horizonTitle: String { "到 " + FixedFlowPresentation.monthDay(cycleEnd) }
}

struct SavingsView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: SavingsAmountField?
    @State private var addingPayday = false
    private var hide: Bool { store.preferences.hideAmounts }
    private var fixed: Int64 { store.funds.fixedSavingsTotal }
    private var sharing: Bool { if case .share = store.current.savingRule { true } else { false } }
    private var percent: Int { if case .share(let value) = store.current.savingRule { value } else { 20 } }
    private var target: Int64 { store.funds.savingTarget }
    private var fixedTarget: Int64 { if case .fixed(let amount) = store.current.savingRule { amount } else { 0 } }
    private var suggestion: (average: Int64, suggestion: Int64)? {
        guard !sharing, let value = Reserve.suggestedMonthly(store.current, now: Date()), value.suggestion > 0, value.suggestion != fixedTarget else { return nil }
        return value
    }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            hero
            howCard
            if let suggestion { suggestionChip(suggestion) }
            if !sharing { fixedSavingsRow }
            if !directIncome.isEmpty { directSection }
        }
            .amountPrivacy(hide)
            .navigationTitle("每月存").yubaiNavigation().accessibilityIdentifier("savingsPage")
            .sheet(item: $editing) { field in
                SavingsAmountEditor(field: field, initial: field == .fixed ? fixed : field == .target ? fixedTarget : Int64(percent) * 100) { value in
                    store.update("存钱") { ledger in
                        switch field {
                        case .fixed: ledger.setFixedSavingsTotal(value)
                        case .target: ledger.savingRule = .fixed(value)
                        case .share: ledger.savingRule = .share(Int(value / 100))
                        }
                    }
                }.environment(store).yubaiSheetBackground().presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $addingPayday) { PaydaySetupSheet().environment(store).yubaiSheetBackground() }
    }

    // MARK: 每月存
    private var hero: some View {
        VStack(alignment: sharing ? .center : .leading, spacing: YubaiSpace.space4) {
            Text(sharing ? "存下的钱" : "每月存").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            HStack(spacing: YubaiSpace.gapGroup) {
                AmountLabel(cents: sharing ? fixed : fixedTarget, hide: hide, role: .hero)
                Button { editing = sharing ? .fixed : .target } label: {
                    Image(systemName: "pencil").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                        .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton).controlSurface(in: Circle()).yubaiHitTarget()
                }.buttonStyle(PressButtonStyle()).accessibilityLabel(sharing ? "修改存下的钱" : "修改每月存")
                    .accessibilityIdentifier(sharing ? "editFixedSavings" : "editSavingTarget")
            }
            Text("这个月已存进 " + amount2(store.reserve.setAside, hide: hide)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
        }.frame(maxWidth: .infinity, alignment: sharing ? .center : .leading)
    }
    private var fixedSavingsRow: some View {
        Button { editing = .fixed } label: {
            Card(style: .list) {
                EntryFormRow(title: "存下的钱") {
                    HStack(spacing: YubaiSpace.space8) {
                        AmountLabel(cents: fixed, hide: hide, role: .small, ink: YubaiColor.labelSecondary)
                        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    }
                }
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("editFixedSavings")
    }

    // MARK: 怎么存
    private var howCard: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Text("怎么存").yubaiFont(YubaiFont.rowTitle)
                Segmented(choices: [(false, "固定金额"), (true, "每笔进账留几成")], selection: Binding(get: { sharing }, set: { value in
                    store.update("存钱") { ledger in
                        ledger.switchSavingMode(sharing: value)
                        if value { ledger.cycleAnchor = .calendarMonth }
                    }
                }), identifier: { $0 ? "savingMode_share" : "savingMode_fixed" }).accessibilityIdentifier("savingMode")
                if sharing { EntryFormDivider(); shareChoices }
                EntryFormDivider()
                Text("每月从哪天算").yubaiFont(YubaiFont.rowTitle)
                cycleAnchorControl
            }
        }
    }
    private func suggestionChip(_ value: (average: Int64, suggestion: Int64)) -> some View {
        Card(style: .compact) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space12) { suggestionTitle(value); Spacer(minLength: YubaiSpace.space8); suggestionButton(value.suggestion) }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) { suggestionTitle(value); suggestionButton(value.suggestion) }
            }
        }.accessibilityIdentifier("suggestedMonthlySaving")
    }
    private func suggestionTitle(_ value: (average: Int64, suggestion: Int64)) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text("改成每月存 " + amount2(value.suggestion, hide: hide)).yubaiFont(YubaiFont.row)
            Text("前三个月平均每月剩 " + amount2(value.average, hide: hide)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    private func suggestionButton(_ amount: Int64) -> some View {
        Button("用这个") { store.update("每月存") { $0.savingRule = .fixed(amount) } }
            .buttonStyle(PressButtonStyle()).foregroundStyle(YubaiColor.brandInk).yubaiHitTarget().accessibilityIdentifier("useSuggestedMonthlySaving")
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
        Segmented(choices: [(true, "发工资那天"), (false, "每月 1 号")], selection: Binding(get: { store.funds.cycleIsPayday }, set: { payday in
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
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            Text("直接放进来的").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.space16)
            CardRows(directIncome) { entry in
                TabNavigationLink(.entryDetail(entry.id)) { EntryDetailView(entryID: entry.id) } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: YubaiSpace.space8) { directIncomeTitle(entry).fixedSize(); Spacer(minLength: YubaiSpace.space8); directIncomeAmount(entry).fixedSize() }
                        VStack(alignment: .leading, spacing: YubaiSpace.space8) { directIncomeTitle(entry); directIncomeAmount(entry) }
                    }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
                }.hidesListDisclosure().buttonStyle(PressButtonStyle()).accessibilityIdentifier("directSavingsEntry_" + entry.id.uuidString)
            }
        }
    }
    private func directIncomeTitle(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(entry.displayTitle).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.row).lineLimit(1)
            Text(FixedFlowPresentation.monthDay(entry.date) + " · " + store.accountName(entry.accountID))
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func directIncomeAmount(_ entry: Entry) -> some View {
        AmountLabel(cents: entry.amount, hide: hide, sign: .inflow, ink: YubaiColor.brandInk)
    }

}

enum SavingsAmountField: String, Identifiable { case fixed, target, share; var id: String { rawValue } }
private struct SavingsChoiceStyle: ViewportButtonStyle {
    var selected: Bool
    var feedback: SavingsChoiceFeedback { SavingsChoiceFeedback(selected: selected) }
}
private struct SavingsChoiceFeedback: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular)
            .foregroundStyle(selected ? YubaiColor.onBrand : YubaiColor.label)
            .padding(.horizontal, YubaiSpace.space20).frame(minHeight: YubaiSize.tapMin)
            .background(selected ? YubaiColor.label : YubaiColor.raised, in: Capsule())
            .yubaiHitTarget().contentShape(Capsule()).opacity(configuration.isPressed ? 0.7 : 1)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct SavingsAmountEditor: View {
    @Environment(\.dismiss) private var dismiss
    let field: SavingsAmountField
    let save: (Int64) -> Bool
    @State private var keypad: EntryKeypad
    @State private var selected = true
    init(field: SavingsAmountField, initial: Int64, save: @escaping (Int64) -> Bool) {
        self.field = field; self.save = save; _keypad = State(initialValue: EntryKeypad(amount: initial))
    }
    private var title: String { field == .fixed ? "存下的钱" : field == .target ? "每月存" : "每笔进账留" }
    private var valid: Bool {
        guard let value = keypad.amount else { return false }
        return field == .share ? value % 100 == 0 && (100...9000).contains(value) : value >= 0
    }
    var body: some View {
        AmountEntrySheet(title: title, keypad: $keypad, primaryTitle: "好", primaryIdentifier: "saveSavingsAmount", canSave: valid, save: {
            guard valid, let value = keypad.resolve() else { return }
            if save(value) { dismiss() }
        })
    }
}
