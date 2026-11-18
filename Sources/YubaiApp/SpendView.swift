import SwiftUI
import YubaiCore

/// One worked exercise. The numeric column uses the same width on every row.
struct FormulaView: View {
    @Environment(AppStore.self) private var store
    private var derivation: SpendableBreakdown { store.formula }
    private var hide: Bool { store.preferences.hideAmounts }
    private var paydayPlan: Plan? { Finance.anchorPlan(in: store.current, now: store.financialNow) }
    private var paydayDetail: String {
        guard let plan = paydayPlan else { return "未设置" }
        let day = plan.monthlyDay ?? Dates.calendar.component(.day, from: plan.dueDate)
        return "每月 \(day) 号 · " + amount2(plan.amount, hide: hide)
    }
    var body: some View {
        let value = derivation
        return Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8, identifier: "formulaPage") {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    question(value)
                    EntryFormDivider()
                    sources(value)
                    answer(value)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("formulaCard")
            Card(style: .list) {
                Button {
                    if let plan = paydayPlan { store.present(.editPlan(plan.id)) }
                    else { store.present(.paydaySetup) }
                } label: { SettingsRow(title: "发薪日与工资", detail: paydayDetail) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaPaydaySetup")
            }
            SoftLineSection()
        }.navigationTitle("还能花是怎么算的").yubaiNavigation().amountPrivacy(hide)
    }
    private func question(_ value: SpendableBreakdown) -> some View {
        Text(NowFormat.monthDay(value.cycleStart) + " – " + NowFormat.monthDay(value.cycleEnd))
            .yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, YubaiSpace.space12)
    }
    private func sources(_ value: SpendableBreakdown) -> some View {
        // Without a saving plan the formula still offers「要攒」so it can be set from here.
        let missingSaving = value.offersFormula && !value.rows.contains { $0.kind == .saving }
        let tail: Set<SpendableRow.Kind> = [.bills, .spent, .withdrawal, .balanceGap]
        let savingIndex = missingSaving ? (value.rows.firstIndex { tail.contains($0.kind) } ?? value.rows.count) : nil
        return VStack(spacing: YubaiSpace.none) {
            ForEach(Array(value.rows.enumerated()), id: \.element.id) { index, item in
                if index == savingIndex { savingSetup(value, divider: index > 0) }
                if index > 0 { EntryFormDivider() }
                source(item, value: value)
            }
            if savingIndex == value.rows.count { savingSetup(value, divider: !value.rows.isEmpty) }
        }
    }
    @ViewBuilder private func savingSetup(_ value: SpendableBreakdown, divider: Bool) -> some View {
        if divider { EntryFormDivider() }
        Button { store.present(.formulaEdit) } label: { row("要攒", amount: 0, sign: "", value: value) }
            .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaSavingSetupRow")
    }
    @ViewBuilder private func source(_ item: SpendableRow, value: SpendableBreakdown) -> some View {
        switch item.kind {
        case .bills:
            TabNavigationLink(.cycleBills) { CycleBillsView() } label: { formulaRow(item, value: value) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_" + item.id)
        default:
            Button { open(item, value: value) } label: { formulaRow(item, value: value) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaRow_" + item.id)
        }
    }
    private func formulaRow(_ item: SpendableRow, value: SpendableBreakdown) -> some View {
        row(item.title, detail: detail(item, value: value), amount: abs(item.amount),
            sign: item.kind == .income ? "" : item.amount > 0 ? "+" : "−", value: value)
    }
    private func detail(_ item: SpendableRow, value: SpendableBreakdown) -> String? {
        switch item.kind {
        case .saving where value.savingLess > 0:
            return "原来 " + amount2(value.plannedSaving, hide: hide) + (value.effectiveSaving == 0 ? " · 这个月攒不了" : " · 少攒 " + amount2(value.savingLess, hide: hide))
        case .income:
            let entries = store.evidenceEntries(Set(item.entryIDs), activeOnly: true)
            if entries.count == 1, let entry = entries.first { return HomeButler.privacyText(entry.displayTitle, hidden: hide) + " · " + NowFormat.monthDay(entry.date) }
            return "\(item.entryIDs.count) 笔"
        case .spent: return "\(item.entryIDs.count) 笔"
        case .bills: return "到 " + NowFormat.monthDay(value.cycleEnd) + " · \(item.occurrences.count) 样"
        case .carry: return item.date.map { NowFormat.monthDay($0) + " 从已存撤回" }
        case .withdrawal: return item.date.map { NowFormat.monthDay($0) + " 从已存" }
        case .balanceGap: return item.date.map { NowFormat.monthDay($0) + " 对余额" }
        default: return nil
        }
    }
    private func open(_ item: SpendableRow, value: SpendableBreakdown) {
        switch item.kind {
        case .income:
            if item.entryIDs.count == 1, let id = item.entryIDs.first { store.present(.editEntry(id)) }
            else { showEntries(value.interval, entryIDs: Set(item.entryIDs)) }
        case .spent: showEntries(value.interval, entryIDs: Set(item.entryIDs))
        case .saving: store.present(.formulaEdit)
        case .carry, .withdrawal: store.tabRouteRequest = .reserve
        case .balanceGap: showEntries(value.interval, entryIDs: Set(item.entryIDs))
        default: showEntries(value.interval)
        }
    }
    private func row(_ title: String, detail: String? = nil, amount: Int64, sign: String, value: SpendableBreakdown) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) {
                sourceLabel(title, detail: detail).fixedSize()
                Spacer(minLength: YubaiSpace.space8)
                numericColumn(amount, sign: sign, value: value)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                sourceLabel(title, detail: detail)
                numericColumn(amount, sign: sign, value: value, constrained: true).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble).padding(.vertical, YubaiSpace.space4).contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel(title + "，" + (hide ? "金额已隐藏" : AmountLabel.text(sign == "−" ? -amount : amount)) + (detail.map { "，" + $0 } ?? ""))
    }
    private func sourceLabel(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            HStack(spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.row)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            }
            if let detail { Text(detail).yubaiFont(YubaiFont.meta).foregroundStyle(title == "要攒" && derivation.savingLess > 0 ? YubaiColor.amberInk : YubaiColor.labelSecondary) }
        }
    }
    private func numericColumn(_ amount: Int64, sign: String, value: SpendableBreakdown, constrained: Bool = false) -> some View {
        ZStack(alignment: .trailing) {
            // Invisible candidates reserve one shared right-aligned column; the
            // visible sign sits right next to its own number.
            ForEach(value.rows) { candidate in
                signedAmount(abs(candidate.amount), sign: "−").hidden().accessibilityHidden(true)
            }
            signedAmount(amount, sign: sign)
        }.fixedSize(horizontal: !constrained, vertical: false).foregroundStyle(YubaiColor.label)
    }
    private func signedAmount(_ amount: Int64, sign: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space4) {
            if !sign.isEmpty { Text(sign).yubaiFont(YubaiFont.amountDonut) }
            AmountLabel(cents: amount, hide: hide, role: .account, sign: .none)
        }
    }
    private func answer(_ value: SpendableBreakdown) -> some View {
        let ink = value.deficit > 0 ? YubaiColor.amberInk : YubaiColor.brandInk
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { answerLabel(ink); Spacer(minLength: YubaiSpace.space8); answerAmount(value.headlineAmount, ink: ink, value: value) }
            VStack(alignment: .leading, spacing: YubaiSpace.space8) { answerLabel(ink); answerAmount(value.headlineAmount, ink: ink, value: value).frame(maxWidth: .infinity, alignment: .trailing) }
        }.padding(.bottom, YubaiSpace.space8)
            .accessibilityElement(children: .contain).accessibilityIdentifier("formulaRow_available")
    }
    private func answerLabel(_ ink: Color) -> some View {
        Text(derivation.headlineTitle).yubaiFont(YubaiFont.row, weight: .semibold).fixedSize()
    }
    /// The sum rule above and the double rule below span the same width: the
    /// wider of the result (with ¥) and the numeric column it totals.
    private func answerAmount(_ amount: Int64, ink: Color, value: SpendableBreakdown) -> some View {
        ZStack(alignment: .trailing) {
            numericColumn(value.spent, sign: "−", value: value).hidden().accessibilityHidden(true)
            AmountLabel(cents: amount, hide: hide, role: .display, currency: true, ink: ink)
        }
            .padding(.vertical, YubaiSpace.space8)
            .overlay(alignment: .top) { Rectangle().fill(YubaiColor.label).frame(height: YubaiSize.separator).accessibilityHidden(true) }
            .overlay(alignment: .bottom) {
                VStack(spacing: YubaiSpace.space4) {
                    Rectangle().fill(YubaiColor.label).frame(height: YubaiSize.separator)
                    Rectangle().fill(YubaiColor.label).frame(height: YubaiSize.separator)
                }.accessibilityHidden(true)
            }.accessibilityElement(children: .ignore)
            .accessibilityLabel(hide ? "金额已隐藏" : AmountLabel.text(amount, currency: true))
            .accessibilityIdentifier("formulaResult")
    }
    private func showEntries(_ interval: DateInterval, entryIDs: Set<UUID>? = nil) {
        store.resetRootNavigation(); store.ledgerPreset = LedgerPreset(mode: .detail, interval: interval, entryIDs: entryIDs); store.destination = .ledger
    }
}
