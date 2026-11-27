import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct BudgetDetailView: View {
    var initialCategory: String? = nil
    var startsEditing = false
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editOverride: Bool?
    private var editing: Bool { editOverride ?? (startsEditing || initialCategory != nil) }
    @State private var target: BudgetAmountTarget?
    @State private var loaded = false

    var body: some View {
        ZStack {
            BudgetPage(period: Finance.spendableBreakdown(store.current, now: store.financialNow),
                   budgets: HomeBudgets(in: store.current, now: store.financialNow),
                   leftover: store.current.savingHistory.last(where: { $0.cycleEnd < store.financialNow })?.leftover ?? 0,
                   hidden: store.preferences.hideAmounts, editing: editing, back: { dismiss() },
                   toggleEdit: {
                       withAnimation(reduceMotion ? DSMotion.reduceMotionAnimation : DSMotion.standardAnimation) { editOverride = !editing }
                   }, edit: { target = $0 }, move: move, openFormulaSource: openFormulaSource)
                .accessibilityHidden(target != nil)
                .allowsHitTesting(target == nil)
            if let target {
                BudgetKeypadOverlay(target: target, close: { self.target = nil }, commit: { commit($0, target: target) })
                    .id(target)
            }
        }
            .dsEdgeSwipeBack()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let category = initialCategory {
                    let current = HomeBudgets(in: store.current, now: store.financialNow).ordered
                        .first { $0.categories.contains(category) }
                    target = current.map(BudgetAmountTarget.init) ?? BudgetAmountTarget(category: category)
                }
            }
    }

    private func openFormulaSource(_ row: SpendableRow, _ period: SpendableBreakdown) {
        switch row.kind {
        case .income where row.entryIDs.count == 1:
            if let id = row.entryIDs.first { store.requestCaptureSheet(.editEntry(id)) }
        case .income, .spent, .deposit, .balanceGap:
            store.resetRootNavigation()
            store.ledgerPreset = LedgerPreset(mode: .detail, interval: period.interval, entryIDs: Set(row.entryIDs))
        case .saving: store.tabRouteRequest = .savingRule
        case .bills: store.tabRouteRequest = .cycleBills
        case .carry, .withdrawal: store.tabRouteRequest = .reserve
        }
    }

    private func move(_ source: UUID, to destination: UUID) {
        guard source != destination else { return }
        _ = store.update("调整预算", entryMotion: false, showToast: false) {
            HomeBudgets.move(source, to: destination, in: &$0)
        }
    }

    private func commit(_ amount: Int64?, target: BudgetAmountTarget) -> Bool {
        store.update("调整预算", entryMotion: false, showToast: false) {
            try HomeBudgets.set(amount, id: target.id, category: target.category, in: &$0, now: store.financialNow)
        }
    }
}

private struct BudgetAmountTarget: Hashable {
    let id: UUID?
    let category: String?
    let title: String
    let amount: Int64

    init(_ budget: HomeBudget) {
        id = budget.id
        category = nil
        title = budget.name
        amount = budget.baseAmount
    }

    init(category: String) {
        id = nil
        self.category = category
        title = Classification.displayCategory(category)
        amount = 0
    }
}

private struct BudgetPage: View {
    let period: SpendableBreakdown
    let budgets: HomeBudgets
    let leftover: Int64
    let hidden: Bool
    let editing: Bool
    let back: () -> Void
    let toggleEdit: () -> Void
    let edit: (BudgetAmountTarget) -> Void
    let move: (UUID, UUID) -> Void
    let openFormulaSource: (SpendableRow, SpendableBreakdown) -> Void

    var body: some View {
        let _ = HomeRenderCounts.increment("budgetBody")
        VStack(spacing: .zero) {
            navigation
            ScrollView {
                if editing { editor }
                else { summary }
            }
            .contentMargins(.horizontal, DS.Space.s20)
            .contentMargins(.bottom, DS.Space.s20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("formulaPage")
        }.background(DS.Color.bg.ignoresSafeArea())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(editing ? "spendingPartsPage" : "budgetDetail")
    }

    private var navigation: some View {
        ZStack {
            Text("还能花").dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: back) {
                    DSIconView(icon: .back, size: HomeSpec.navIcon, color: DS.Color.ink)
                        .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                }.dsPressStyle().accessibilityLabel("返回").accessibilityIdentifier("BackButton")
                Spacer(minLength: .zero)
                Button(action: toggleEdit) {
                    Text(editing ? "完成" : "调整").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.accentInk)
                }.dsPressStyle().accessibilityIdentifier("toggleBudgetEditing")
            }
        }.padding(.horizontal, DS.Space.s20).frame(minHeight: DS.Size.tapMin)
    }

    private var summary: some View {
        let rows = budgets.ordered.sorted { $0.fraction > $1.fraction }.map { HomeDisplay.dsBudget($0, hidden: hidden) }
        let amber = rows.filter(\.isWarning)
        let calm = rows.filter { !$0.isWarning }
        return VStack(alignment: .leading, spacing: .zero) {
            // Spec-Issues 7: the label says which it is; overspent is amber 超支.
            Text(period.showsSpendableDeficit ? "超支" : "还能花").dsText(DS.Font.tSub)
                .foregroundStyle(period.showsSpendableDeficit ? DS.Color.warnInk : DS.Color.ink3)
                .padding(.top, DS.Space.s8)
            Text(HomeDisplay.money(period.spendableDisplayAmount, hidden: hidden))
                .dsText(DS.Font.nHero).foregroundStyle(period.showsSpendableDeficit ? DS.Color.warnInk : DS.Color.ink)
                .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .padding(.top, DS.Space.s4).accessibilityIdentifier("formulaResult")
            Text("\(BudgetPageDate.text(period.cycleStart)) – \(BudgetPageDate.text(period.cycleEnd)) · 还剩 \(HomeDisplay.daysLeft(period)) 天")
                .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
            formula.padding(.top, HomeSpec.formulaTop)
            if leftover > 0 {
                DSAlertCard(title: "上期留下", detail: "已转入机动余钱",
                            value: HomeDisplay.signed(leftover, hidden: hidden), tone: .positive)
                    .padding(.top, HomeSpec.budgetTileGap)
            }
            if !amber.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HomeSpec.budgetTileGap) {
                    ForEach(amber) { DSAmberTile(budget: $0) }
                }.padding(.top, DS.Space.s20)
            }
            if !calm.isEmpty {
                LazyVStack(spacing: .zero) {
                    ForEach(calm) { row in
                        if row.id != calm.first?.id { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                        DSBudgetRow(budget: row)
                    }
                }.padding(.top, HomeSpec.calmTop)
            }
        }.dsFillWidth()
    }

    private var formula: some View {
        VStack(spacing: .zero) {
            ForEach(period.rows) { row in
                Button {
                    openFormulaSource(row, period)
                } label: {
                    formulaLine(formulaLabel(row.kind), sign: row.amount < 0 ? "−" : row.kind != .income && row.amount > 0 ? "+" : "",
                                amount: abs(row.amount), tint: row.kind == .income ? DS.Color.ink : DS.Color.ink2, strong: false)
                }.buttonStyle(EntryTactileButtonStyle())
                    .accessibilityLabel(formulaLabel(row.kind) + "，" + (hidden ? "金额已隐藏" : HomeDisplay.money(row.amount, hidden: false)))
                    .accessibilityIdentifier("formulaRow_" + row.kind.rawValue)
                DS.Color.separator.frame(height: DS.Stroke.hairline)
            }
            // Canvas Main.dc.html 还能花 page: the sum is the last line — 还能花, or amber 超支.
            let over = period.showsSpendableDeficit
            formulaLine(over ? "超支" : "还能花", sign: "=", amount: period.spendableDisplayAmount,
                        tint: over ? DS.Color.warnInk : DS.Color.ink, strong: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("formulaRow_result")
        }.padding(.vertical, HomeSpec.heroLabelGap).padding(.horizontal, DS.Space.s16)
            .dsSurface(DS.Color.raised, radius: DS.Radius.m)
            .accessibilityElement(children: .contain).accessibilityIdentifier("formulaCard")
    }

    private func formulaLine(_ name: String, sign: String, amount: Int64, tint: Color, strong: Bool) -> some View {
        HStack(spacing: DS.Space.s8) {
            Text(name).dsText(strong ? DS.Font.tLabelStrong : DS.Font.tLabel).foregroundStyle(tint).dsFillWidth()
            Text(sign).frame(width: HomeSpec.formulaSign).foregroundStyle(DS.Color.ink3)
            Text(HomeDisplay.money(amount, hidden: hidden)).dsText(HomeSpec.headerNumber)
                .foregroundStyle(strong ? tint : DS.Color.ink).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .frame(minWidth: HomeSpec.formulaAmount, alignment: .trailing)
        }.frame(minHeight: DS.Size.iconTile)
            .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin).contentShape(Rectangle())
    }

    private func formulaLabel(_ kind: SpendableRow.Kind) -> String {
        switch kind {
        case .income: "本期入账"
        case .saving: "先攒"
        case .bills: "固定收支"
        case .spent: "已花"
        case .carry: "上期留下"
        case .withdrawal: "拿出来用"
        case .balanceGap: "余额差额"
        case .deposit: "存入"
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            section("首页显示", rows: budgets.home, draggable: true)
            section("不在首页", rows: budgets.other, draggable: false)
            if !budgets.unbudgeted.isEmpty {
                heading("没设预算")
                ChipFlow {
                    ForEach(budgets.unbudgeted, id: \.self) { category in
                        Button { edit(.init(category: category)) } label: {
                            HStack(spacing: HomeSpec.gap6) {
                                DSIconView(icon: .add, size: DS.Font.tSub.size, color: DS.Color.accentInk)
                                Text(Classification.displayCategory(category)).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2)
                            }.padding(.horizontal, DS.Space.s12).frame(minHeight: DS.Size.iconTile).dsPill(DS.Color.surface)
                        }.buttonStyle(EntryTactileButtonStyle()).accessibilityIdentifier("newBudget_" + category)
                    }
                }
            }
        }.padding(.top, DS.Space.s8)
    }

    private func heading(_ title: String) -> some View {
        Text(title).dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink3)
            .accessibilityAddTraits(.isHeader)
    }

    private func section(_ title: String, rows: ArraySlice<HomeBudget>, draggable: Bool) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            heading(title).padding(.bottom, DS.Space.s4)
            ForEach(rows) { row in
                if row.id != rows.first?.id { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                if draggable {
                    editRow(row, draggable: true)
                        .dropDestination(for: String.self) { items, _ in
                            guard let source = items.first.flatMap(UUID.init(uuidString:)),
                                  budgets.home.contains(where: { $0.id == source }), source != row.id else { return false }
                            move(source, row.id)
                            return true
                        }
                        .accessibilityActions {
                            if let index = budgets.home.firstIndex(where: { $0.id == row.id }) {
                                if index > budgets.home.startIndex {
                                    Button("上移") { move(row.id, budgets.home[index - 1].id) }
                                }
                                if index + 1 < budgets.home.endIndex {
                                    Button("下移") { move(row.id, budgets.home[index + 1].id) }
                                }
                            }
                        }
                } else { editRow(row, draggable: false) }
            }
        }
    }

    private func editRow(_ row: HomeBudget, draggable: Bool) -> some View {
        HStack(spacing: DS.Space.s12) {
            VStack(alignment: .leading, spacing: HomeSpec.heroLabelGap) {
                Text(row.name).dsText(draggable ? HomeSpec.doneText : DS.Font.tLabelStrong)
                    .foregroundStyle(DS.Color.ink2).lineLimit(1)
                Text("已花 " + HomeDisplay.money(row.spent, hidden: hidden)).dsText(DS.Font.tCaption)
                    .monospacedDigit().foregroundStyle(DS.Color.ink3)
            }.dsFillWidth()
            Button { edit(.init(row)) } label: {
                Text(HomeDisplay.money(row.baseAmount, hidden: hidden))
                    .dsText(draggable ? DS.Font.nSpine : HomeSpec.billName).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(DS.Color.ink).fixedSize()
                    .padding(.horizontal, DS.Space.s12)
                    .frame(minWidth: HomeSpec.amountPillWidth, minHeight: HomeSpec.amountPill, alignment: .trailing)
                    .dsPill(DS.Color.surface)
                    .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin).contentShape(Rectangle())
            }.buttonStyle(EntryTactileButtonStyle()).accessibilityLabel(row.name + " 预算")
                .accessibilityValue(HomeDisplay.money(row.baseAmount, hidden: hidden))
                .accessibilityIdentifier("editBudget_" + row.name)
            if draggable {
                VStack(spacing: HomeSpec.gap6) {
                    Capsule(style: .continuous).fill(DS.Color.chevron)
                    Capsule(style: .continuous).fill(DS.Color.chevron)
                }.frame(width: HomeSpec.chevron, height: DS.Space.s8)
                    .frame(width: DS.Size.tapMin, height: DS.Size.tapMin).contentShape(Rectangle())
                    .draggable(row.id.uuidString)
                    .accessibilityElement(children: .ignore).accessibilityLabel("拖动" + row.name).accessibilityIdentifier("dragBudget_" + row.name)
            }
        }.frame(minHeight: draggable ? HomeSpec.budgetRow : DS.Size.rowBill)
            .contentShape(Rectangle())
    }

}

enum BudgetPageDate {
    static func text(_ date: Date) -> String {
        let components = Dates.calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d", components.month ?? 1, components.day ?? 1)
    }
}

private struct BudgetKeypadOverlay: View {
    let target: BudgetAmountTarget
    let close: () -> Void
    let commit: (Int64?) -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var motion = EntrySheetMotion(settled: false)
    @State private var expression: EntryAmountExpression
    @State private var replaceAmount = true
    @State private var saves = 0

    init(target: BudgetAmountTarget, close: @escaping () -> Void, commit: @escaping (Int64?) -> Bool) {
        self.target = target
        self.close = close
        self.commit = commit
        _expression = State(initialValue: EntryAmountExpression(cents: target.amount))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                EntryScrimView(motion: motion, color: DS.Color.scrim, close: cancel).ignoresSafeArea()
                panel(bottom: geometry.safeAreaInsets.bottom)
                    .modifier(EntrySheetPositionModifier(motion: motion, reduced: reduced, onClose: close))
            }.ignoresSafeArea(.container, edges: .bottom)
        }.accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal).accessibilityAction(.escape, cancel)
            .accessibilityIdentifier("budgetKeypad")
    }

    private func panel(bottom: CGFloat) -> some View {
        VStack(spacing: DS.Space.s8) {
            VStack(spacing: DS.Space.s4) {
                Capsule(style: .continuous).fill(DS.Color.grabber)
                    .frame(width: HomeSpec.sheetGrabberWidth, height: DS.Size.barCalm)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s4)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(coordinateSpace: .global).onChanged { motion.drag($0) }
                        .onEnded { motion.release($0, reduced: reduced, onClose: close) })
                    .accessibilityHidden(true)
                HStack {
                    Button(action: cancel) {
                        DSIconView(icon: .close, size: DS.Size.icon, color: DS.Color.ink3)
                            .frame(width: DS.Size.tapMin, height: DS.Size.tapMin).contentShape(Rectangle())
                    }.dsPressStyle().accessibilityLabel("取消").accessibilityIdentifier("cancelBudgetKeypad")
                    Text(target.title).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink).frame(maxWidth: .infinity)
                    if target.id != nil {
                        Button { save(nil) } label: {
                            Text("删除").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.warnInk)
                                .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin).contentShape(Rectangle())
                        }.dsPressStyle().accessibilityIdentifier("deleteBudgetKeypad")
                    } else {
                        Color.clear.frame(width: DS.Size.tapMin)
                    }
                }
                Text(expression.formattedDisplay).dsText(DS.Font.nDetail).foregroundStyle(DS.Color.ink)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale).accessibilityIdentifier("budgetKeypadAmount")
            }
            DSKeypad(canSave: expression.canSave, onKey: press, onSave: {
                if let amount = expression.evaluatedCents { save(amount) }
            }).clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
                .sensoryFeedback(DSMotion.Haptic.save, trigger: saves)
        }.padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s12)
            .padding(.bottom, max(DS.Space.s12, bottom))
            .dsSurface(DS.Color.raised, radius: DS.Radius.sheet)
    }

    private func cancel() { motion.close(reduced: reduced, onClose: close) }

    private func save(_ amount: Int64?) {
        guard !motion.closing, commit(amount) else { return }
        if amount != nil { saves += 1 }
        motion.close(reduced: reduced, sealed: true, onClose: close)
    }

    private func press(_ key: String) {
        if replaceAmount && (key.first?.isNumber == true || key == ".") { expression.reset() }
        replaceAmount = false
        expression.press(key)
    }
}


#if DEBUG
#Preview("还能花") {
    let fixture = HomeFixture.budget(.view)
    let ledger = fixture.makeLedger().ledger
    BudgetPage(period: Finance.spendableBreakdown(ledger, now: fixture.now), budgets: HomeBudgets(in: ledger, now: fixture.now),
               leftover: ledger.savingHistory.last?.leftover ?? 0, hidden: false, editing: false,
               back: {}, toggleEdit: {}, edit: { _ in }, move: { _, _ in }, openFormulaSource: { _, _ in })
}
#endif
