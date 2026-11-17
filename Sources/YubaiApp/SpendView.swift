import SwiftUI
import YubaiCore

/// One worked exercise. The numeric column uses the same width on every row.
struct FormulaView: View {
    @Environment(AppStore.self) private var store
    private var derivation: SpendableBreakdown { store.formula }
    private var hide: Bool { store.preferences.hideAmounts }
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
            SoftLineSection()
        }.navigationTitle("还能花是怎么算的").yubaiNavigation().amountPrivacy(hide)
    }
    private func question(_ value: SpendableBreakdown) -> some View {
        Text(NowFormat.monthDay(value.cycleStart) + " – " + NowFormat.monthDay(value.cycleEnd))
            .yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, YubaiSpace.space12)
    }
    private func sources(_ value: SpendableBreakdown) -> some View {
        VStack(spacing: YubaiSpace.none) {
            ForEach(value.rows) { item in
                if item.id != value.rows.first?.id { EntryFormDivider() }
                source(item, value: value)
            }
        }
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
        HStack(spacing: YubaiSpace.space4) {
            Text(sign)
                .yubaiFont(YubaiFont.amountDonut).frame(width: YubaiSpace.space24)
            ZStack(alignment: .trailing) {
                // Invisible candidates reserve one shared right-aligned column.
                ForEach(value.rows) { candidate in
                    AmountLabel(cents: abs(candidate.amount), hide: hide, role: .account, sign: .none).hidden().accessibilityHidden(true)
                }
                AmountLabel(cents: amount, hide: hide, role: .account, sign: .none)
            }.fixedSize(horizontal: !constrained, vertical: false)
        }.foregroundStyle(YubaiColor.label)
    }
    private func answer(_ value: SpendableBreakdown) -> some View {
        let ink = value.deficit > 0 ? YubaiColor.amberInk : YubaiColor.brandInk
        return VStack(alignment: .trailing, spacing: YubaiSpace.space8) {
            numericColumn(value.spent, sign: "−", value: value, constrained: true).hidden()
                .overlay(alignment: .bottom) { Rectangle().fill(YubaiColor.label).frame(height: YubaiSize.separator) }
                .frame(height: YubaiSize.separator).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) { answerLabel(ink); Spacer(minLength: YubaiSpace.space8); answerAmount(value.headlineAmount, ink: ink) }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) { answerLabel(ink); answerAmount(value.headlineAmount, ink: ink).frame(maxWidth: .infinity, alignment: .trailing) }
            }.padding(.vertical, YubaiSpace.space8)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("formulaRow_available")
    }
    private func answerLabel(_ ink: Color) -> some View {
        Text(derivation.headlineTitle).yubaiFont(YubaiFont.row, weight: .semibold).fixedSize()
    }
    private func answerAmount(_ amount: Int64, ink: Color) -> some View {
        AmountLabel(cents: amount, hide: hide, role: .display, currency: true, ink: ink)
            .padding(.bottom, YubaiSpace.space8)
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
