import SwiftUI
import YubaiCore

/// One worked exercise. The numeric column uses the same width on every row.
struct FormulaView: View {
    @Environment(AppStore.self) private var store
    private var derivation: SpendingDerivation { store.spendingDerivation }
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        let value = derivation
        return Page(spacing: YubaiSpace.gapGroup, topPadding: YubaiSpace.space8, identifier: "formulaPage") {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    question(value)
                    EntryFormDivider()
                    sources(value)
                    answer(value)
                    if let daily = value.daily { dailyRow(daily, days: value.daysLeft) }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("formulaCard")
        }.navigationTitle("还能花").yubaiNavigation().amountPrivacy(hide)
    }
    private func question(_ value: SpendingDerivation) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("这一期还能花多少？").yubaiFont(YubaiFont.heroLabel).fixedSize()
                Spacer(minLength: YubaiSpace.none)
                dates(value).fixedSize()
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text("这一期还能花多少？").yubaiFont(YubaiFont.heroLabel)
                dates(value)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, YubaiSpace.space12)
    }
    private func dates(_ value: SpendingDerivation) -> some View {
        Text(NowFormat.monthDay(value.interval.start) + " – " + NowFormat.monthDay(value.cycleEnd))
            .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func sources(_ value: SpendingDerivation) -> some View {
        VStack(spacing: YubaiSpace.none) {
            Button {
                if let salary = value.salary { store.present(.editEntry(salary.id)) }
                else { showEntries(value.interval) }
            } label: {
                row("工资", detail: value.salary.map { NowFormat.monthDay($0.date) } ?? NowFormat.monthDay(value.interval.start),
                    amount: value.exerciseIncome, subtracting: false, value: value)
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_income")
            if value.saving != 0 {
                EntryFormDivider()
                Button { store.present(.formulaEdit) } label: { row("先存起来", amount: value.saving, value: value) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_saving")
            }
            if value.bills != 0 {
                EntryFormDivider()
                TabNavigationLink(.cycleBills) { CycleBillsView() } label: {
                    row("要付的账单", detail: "\(value.billCount) 样", amount: value.bills, value: value)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_bills")
            }
            if value.yearlySetAside != 0 {
                EntryFormDivider()
                TabNavigationLink(.yearlyBills) { YearlyBillsView() } label: { row("年付每月先留", amount: value.yearlySetAside, value: value) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_yearlySetAside")
            }
            EntryFormDivider()
            Button { showEntries(value.interval) } label: { row("已经花了", detail: "\(value.entryIDs.count) 笔", amount: value.spent, value: value) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_spent")
        }
    }
    private func row(_ title: String, detail: String? = nil, amount: Int64, subtracting: Bool = true, value: SpendingDerivation) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) {
                sourceLabel(title, detail: detail).fixedSize()
                Spacer(minLength: YubaiSpace.space8)
                numericColumn(amount, subtracting: subtracting, value: value)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                sourceLabel(title, detail: detail)
                numericColumn(amount, subtracting: subtracting, value: value, constrained: true).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble).padding(.vertical, YubaiSpace.space4).contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel(title + (detail.map { "，" + $0 } ?? "") + "，" + (hide ? "金额已隐藏" : AmountLabel.text(subtracting ? -amount : amount)))
    }
    private func sourceLabel(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            HStack(spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.row)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            }
            if let detail { Text(detail).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
        }
    }
    private func numericColumn(_ amount: Int64, subtracting: Bool, value: SpendingDerivation, constrained: Bool = false) -> some View {
        HStack(spacing: YubaiSpace.space4) {
            Text(subtracting ? (amount < 0 ? "+" : "−") : (amount < 0 ? "−" : ""))
                .yubaiFont(YubaiFont.amountDonut).frame(width: YubaiSpace.space24)
            ZStack(alignment: .trailing) {
                // Invisible candidates reserve one shared right-aligned column.
                ForEach(0..<5, id: \.self) { index in
                    AmountLabel(cents: [value.exerciseIncome, value.saving, value.bills, value.yearlySetAside, value.spent][index], hide: hide, role: .account, sign: .none).hidden().accessibilityHidden(true)
                }
                AmountLabel(cents: amount, hide: hide, role: .account, sign: .none)
            }.fixedSize(horizontal: !constrained, vertical: false)
        }.foregroundStyle(YubaiColor.label)
    }
    private func answer(_ value: SpendingDerivation) -> some View {
        let ink = value.available < 0 ? YubaiColor.amberInk : YubaiColor.brandInk
        return VStack(alignment: .trailing, spacing: YubaiSpace.space8) {
            numericColumn(value.spent, subtracting: true, value: value, constrained: true).hidden()
                .overlay(alignment: .bottom) { Rectangle().fill(YubaiColor.label).frame(height: YubaiSize.separator) }
                .frame(height: YubaiSize.separator).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) { answerLabel(ink); Spacer(minLength: YubaiSpace.space8); answerAmount(value.available, ink: ink) }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) { answerLabel(ink); answerAmount(value.available, ink: ink).frame(maxWidth: .infinity, alignment: .trailing) }
            }.padding(.vertical, YubaiSpace.space8)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("formulaRow_available")
    }
    private func answerLabel(_ ink: Color) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Text("还能花").yubaiFont(YubaiFont.row, weight: .semibold).fixedSize()
            Image(systemName: "checkmark").yubaiFont(YubaiFont.caption, weight: .semibold)
                .foregroundStyle(ink).frame(width: YubaiSpace.space24, height: YubaiSpace.space24)
                .background(valueIsNegative ? YubaiColor.amberTint : YubaiColor.brandTint, in: Circle()).accessibilityHidden(true)
        }
    }
    private var valueIsNegative: Bool { derivation.available < 0 }
    private func answerAmount(_ amount: Int64, ink: Color) -> some View {
        AmountLabel(cents: amount, hide: hide, role: .display, ink: ink)
            .padding(.bottom, YubaiSpace.space8)
            .overlay(alignment: .bottom) {
                VStack(spacing: YubaiSpace.space4) {
                    Rectangle().fill(YubaiColor.label).frame(height: YubaiSize.separator)
                    Rectangle().fill(YubaiColor.label).frame(height: YubaiSize.separator)
                }.accessibilityHidden(true)
            }.accessibilityIdentifier("formulaResult")
    }
    private func dailyRow(_ daily: Int64, days: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { Text("分到 \(days) 天，每天").fixedSize(); Spacer(minLength: YubaiSpace.space8); dailyAmount(daily, days: days) }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text("分到 \(days) 天，每天"); dailyAmount(daily, days: days).frame(maxWidth: .infinity, alignment: .trailing) }
        }.yubaiFont(YubaiFont.row).padding(.vertical, YubaiSpace.space12)
            .accessibilityElement(children: .combine).accessibilityIdentifier("formulaRow_daily")
    }
    private func dailyAmount(_ daily: Int64, days: Int) -> some View {
        HStack(spacing: YubaiSpace.space4) {
            Text("÷ \(days) =").yubaiFont(YubaiFont.amountSummary).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
            AmountLabel(cents: daily, hide: hide, role: .summary)
        }
    }
    private func showEntries(_ interval: DateInterval) {
        store.resetRootNavigation(); store.ledgerPreset = LedgerPreset(mode: .detail, interval: interval); store.destination = .ledger
    }
}
