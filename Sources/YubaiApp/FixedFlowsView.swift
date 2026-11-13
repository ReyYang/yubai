import SwiftUI
import YubaiCore

struct FixedFlowsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
                let month = store.fixedFlowMonth
        let stopped = month.stopped
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.gapGroup) {
                    Text("\(Dates.calendar.component(.month, from: month.date))月还要付").yubaiFont(YubaiFont.heroLabel)
                    Spacer(minLength: YubaiSpace.space4)
                    HStack(spacing: YubaiSpace.space4) {
                        Text("要收").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        AmountLabel(cents: month.remainingInflow, hide: store.preferences.hideAmounts, role: .small, sign: .inflow, ink: YubaiColor.brandInk)
                    }
                }
                AmountLabel(cents: month.remainingOutflow, hide: store.preferences.hideAmounts, role: .display).accessibilityIdentifier("fixedFlowRemaining")
                if month.overdueOutflow > 0 || month.overdueInflow > 0 {
                    HStack(spacing: YubaiSpace.space4) {
                        if month.overdueOutflow > 0 {
                            Text("其中").yubaiFont(YubaiFont.row)
                            overdueAmount(month.overdueOutflow)
                            Text("已过期").yubaiFont(YubaiFont.row)
                        }
                        if month.overdueInflow > 0 {
                            if month.overdueOutflow > 0 { Text("·").yubaiFont(YubaiFont.row) }
                            overdueAmount(month.overdueInflow)
                            Text("过期没收到").yubaiFont(YubaiFont.row)
                        }
                    }.foregroundStyle(YubaiColor.amberInk).accessibilityElement(children: .combine).accessibilityIdentifier("fixedFlowOverdue")
                }
            }
            if month.occurrences.isEmpty && month.later.isEmpty && stopped.isEmpty {
                EmptyState("calendar", "这个月还没有会回来的账单", action: "添加账单", onAction: { store.sheet = .addPlan })
            }
            let expenses = month.occurrences.filter { !$0.inflow }
            if !expenses.isEmpty {
                VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                    Text("要付").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, YubaiSpace.insetCard)
                    bills(expenses)
                }
            }
            let income = month.occurrences.filter(\.inflow)
            if !income.isEmpty {
                VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                    Text("要收").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, YubaiSpace.insetCard)
                    bills(income)
                }
            }
            if !month.later.isEmpty { laterBills(month.later) }
            if !stopped.isEmpty { stoppedBills(stopped) }
        }.amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("fixedFlowsScroll").navigationTitle("会回来的账单").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .primaryAction) {
                Button { store.sheetSource = nil; store.sheet = .addPlan } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加安排").accessibilityIdentifier("addFixedFlow")
            } }
    }
    private func overdueAmount(_ amount: Int64) -> some View {
        AmountLabel(cents: amount, hide: store.preferences.hideAmounts, ink: YubaiColor.amberInk)
    }
    private func laterBills(_ rows: [FixedFlowUpcoming]) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            Text("以后").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, YubaiSpace.insetCard)
            CardRows(rows, rowHeight: 52) { row in
                HStack(spacing: YubaiSpace.none) {
                    Button { edit(row.planID) } label: {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                Text(row.title).yubaiFont(YubaiFont.rowTitle)
                                Text(row.detail()).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            AmountLabel(cents: row.amount, hide: store.preferences.hideAmounts, sign: row.inflow ? .inflow : .none,
                                        ink: row.inflow ? YubaiColor.brandInk : YubaiColor.label).fixedSize(horizontal: true, vertical: false)
                            Color.clear.frame(width: YubaiSize.rowIcon).accessibilityHidden(true)
                        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityElement(children: .contain).accessibilityAddTraits(.isButton)
                        .accessibilityLabel("改" + row.title)
                        .accessibilityIdentifier("editFixedFlow_" + row.planID.uuidString)
                }.accessibilityElement(children: .contain)
                    .accessibilityIdentifier("fixedFlowLater_" + row.planID.uuidString)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("fixedFlowLater")
    }
    private func stoppedBills(_ rows: [FixedFlowArrangement]) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            Text("已停掉").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, YubaiSpace.insetCard)
            CardRows(rows) { row in
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        let planID = store.plans.first { $0.id == row.id }?.id
                        if let planID {
                            Button { edit(planID) } label: { stoppedSummary(row) }
                                .buttonStyle(.plain).accessibilityElement(children: .contain).accessibilityAddTraits(.isButton)
                                .accessibilityLabel("改" + row.title)
                                .accessibilityIdentifier("editFixedFlow_" + planID.uuidString)
                        } else { stoppedSummary(row) }
                        Button("恢复") { resume(row) }.yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.brandInk)
                            .frame(minWidth: YubaiSize.tapMin, minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle())
                            .accessibilityLabel("恢复" + row.title).accessibilityIdentifier("resumeFixedFlow_" + row.id.uuidString)
                    }
                    if !row.pending.isEmpty {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            stoppedAction(row.inflow ? "收到了" : "付了", row: row, resolution: .settle)
                            stoppedAction("不要了", row: row, resolution: .skip)
                        }
                    }
                }.padding(.vertical, YubaiSpace.space4).frame(minHeight: YubaiSize.rowDouble).accessibilityElement(children: .contain)
                    .accessibilityIdentifier("stoppedFixedFlow_" + row.id.uuidString)
            }
        }
    }
    private func stoppedSummary(_ row: FixedFlowArrangement) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(row.title).yubaiFont(YubaiFont.rowTitle)
                Text(row.detail).yubaiFont(YubaiFont.caption)
                    .foregroundStyle(row.pending.isEmpty ? YubaiColor.labelSecondary : YubaiColor.amberInk)
            }.frame(maxWidth: .infinity, alignment: .leading)
            let amount = row.pending.isEmpty ? row.amount : row.pendingAmount
            AmountLabel(cents: amount, hide: store.preferences.hideAmounts,
                        sign: row.inflow ? .inflow : .none, ink: YubaiColor.labelSecondary)
                .fixedSize(horizontal: true, vertical: false)
        }.foregroundStyle(YubaiColor.labelSecondary).opacity(row.pending.isEmpty ? 0.7 : 1)
            .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).contentShape(Rectangle())
    }
    private func edit(_ id: UUID) {
        store.sheetSource = nil; store.sheet = .editPlan(id)
    }
    private func stoppedAction(_ title: String, row: FixedFlowArrangement, resolution: FixedFlowStopResolution) -> some View {
        let ink = resolution == .skip ? YubaiColor.labelSecondary : row.inflow ? YubaiColor.brandInk : YubaiColor.amberInk
        return Button { resolve(row, resolution) } label: {
            Text(title).yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(ink)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.rowIcon)
                .overlay { Capsule().strokeBorder(ink, lineWidth: 1.5) }.yubaiHitTarget()
        }.buttonStyle(PressButtonStyle())
            .accessibilityLabel(title + row.title + "的全部 \(row.pending.count) 期")
            .accessibilityIdentifier((resolution == .settle ? "settleStoppedFixedFlow_" : "skipStoppedFixedFlow_") + row.id.uuidString)
    }
    private func resolve(_ row: FixedFlowArrangement, _ resolution: FixedFlowStopResolution) {
        do {
            let change = try FixedFlows.resolveStopped(planID: row.id, resolution: resolution, in: store.current)
            if store.apply(change, label: row.title + (resolution == .settle ? "已记下" : "不要了")) {
                store.cancelEntrySaveMotion()
                if resolution == .settle { store.fixedFlowSettleTrigger &+= 1 }
                store.toast = resolution == .settle ? "已记下" : "已不要了"
            }
        } catch { store.error = error.localizedDescription }
    }
    private func resume(_ row: FixedFlowArrangement) {
        do {
            let change = try FixedFlows.resume(id: row.id, in: store.current)
            if store.apply(change, label: "恢复安排") { store.toast = "已恢复 · " + row.title }
        } catch { store.error = error.localizedDescription }
    }
    @ViewBuilder private func bills(_ rows: [FixedFlowOccurrence]) -> some View {
        if !rows.isEmpty {
            NativeCardRows(rows) { row in
                FixedFlowBillRow(row: row)
            }.accessibilityElement(children: .contain)
                .accessibilityIdentifier(rows[0].inflow ? "fixedFlowIncomeCard" : "fixedFlowExpenseCard")
        }
    }
}

enum FixedFlowPresentation {
    static func monthDay(_ date: Date) -> String { date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN"))) }
    static func state(_ state: FixedFlowState, inflow: Bool) -> String {
        switch state { case .paid: inflow ? "已收到" : "已付"; case .due: "已到期"; case .upcoming: "还没到" }
    }
    static func detail(_ row: FixedFlowOccurrence, in ledger: Ledger) -> String {
        var parts = [row.statusText()]
        let entry = ledger.activeEntries.filter { $0.planID == row.planID && row.planID != nil && $0.occurrence.map(Dates.day) == Dates.day(row.date) }
            .max { ($0.recordedAt ?? $0.date) < ($1.recordedAt ?? $1.date) }
        if row.state == .paid {
            if entry?.source == "自动扣款" { parts.append("自动") }
            else if let entry { parts.append(monthDay(entry.recordedAt ?? entry.date) + "记") }
        } else if row.autoPay { parts.append("自动") }
        let account = ledger.plans.first { $0.id == row.planID }?.accountID ?? ledger.rents.first { $0.id == row.rentID }?.accountID
        if let account { parts.append(ledger.accountName(account)) }
        if let installment = row.installment { parts.append("\(installment.index)/\(installment.total) 期") }
        if row.estimated { parts.append("大约") }
        return parts.joined(separator: " · ")
    }
}

struct FixedFlowDot: View {
    let state: FixedFlowState
    var inflow = false
    private var color: Color { state == .paid || inflow ? YubaiColor.brand : state == .due ? YubaiColor.amberDot : YubaiColor.neutralStrong }
    var body: some View {
        Circle().fill(state == .paid || (state == .due && !inflow) ? color : color.opacity(0))
            .overlay { Circle().strokeBorder(color, lineWidth: 2) }.frame(width: 12, height: 12).accessibilityHidden(true)
    }
}

/// Both edit and swipe stop the saved arrangement through the same confirmation.
private struct FixedFlowStopConfirmation: ViewModifier {
    @Environment(AppStore.self) private var store
    let planID: UUID?
    let title: String
    let inflow: Bool
    @Binding var isPresented: Bool
    var onStopped: () -> Void = {}
    private var pending: [Occurrence] { planID.map { FixedFlows.unsettled(planID: $0, in: store.current) } ?? [] }
    private var message: String? {
        let pending = pending
        if pending.count > 1 { return "还有 \(pending.count) 期没记。" }
        return pending.first.map { FixedFlowPresentation.monthDay($0.date) + "这期还没记。" }
    }
    func body(content: Content) -> some View {
        content.alert("停掉「\(title)」？", isPresented: $isPresented) {
            if pending.isEmpty {
                Button("停掉", role: .destructive) { performStop() }
                    .accessibilityIdentifier("fixedFlowStopConfirm")
                    .accessibilityHint("只停以后的，已到期账单和付过的记录保留")
            } else {
                Button(inflow ? "收到了，记一笔再停" : "付了，记一笔再停") { performStop(.settle) }
                    .accessibilityIdentifier("fixedFlowStopConfirm")
                Button(inflow ? "没收到，这期也不要了" : "没付，这期也不要了", role: .destructive) { performStop(.skip) }
                    .accessibilityIdentifier("fixedFlowStopSkip")
            }
            Button("取消", role: .cancel) { isPresented = false }.accessibilityIdentifier("fixedFlowStopCancel")
        } message: {
            if let message { Text(message) }
        }
    }
    private func performStop(_ resolution: FixedFlowStopResolution? = nil) {
        guard let planID else { return }
        do {
            let change = try FixedFlows.stop(planID: planID, resolution: resolution, in: store.current)
            if store.apply(change, label: "停掉安排") {
                store.cancelEntrySaveMotion(); store.toast = "已停掉 · " + title; onStopped()
            }
        } catch { store.error = error.localizedDescription }
    }
}

private struct FixedFlowBillRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingStop = false
    let row: FixedFlowOccurrence
    private var canEnd: Bool { store.plans.contains { $0.id == row.planID && $0.active && $0.endDate == nil } }
    var body: some View {
        content.swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEnd { Button("停掉") { confirmingStop = true }.tint(YubaiColor.neutralStrong).foregroundStyle(YubaiColor.label)
                .accessibilityIdentifier("stopFixedFlow_" + row.id) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("fixedFlow_" + row.id)
            .accessibilityValue(FixedFlowPresentation.state(row.state, inflow: row.inflow))
            .contextMenu {
                if row.state == .upcoming, let id = row.planID {
                    Button(row.inflow ? "提前标记收到了" : "提前标记付了") {
                        FixedFlowCheck.record(planID: id, occurrence: row.date, title: row.title, amount: row.amount, inflow: row.inflow, store: store)
                    }
                }
            }
            .modifier(FixedFlowStopConfirmation(planID: row.planID, title: row.title, inflow: row.inflow, isPresented: $confirmingStop))
    }
    private var summary: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(row.title).yubaiFont(YubaiFont.rowTitle)
                Text(FixedFlowPresentation.detail(row, in: store.current)).yubaiFont(YubaiFont.caption)
                    .foregroundStyle(row.state == .due && row.overdueDays() > 0 ? YubaiColor.amberInk : YubaiColor.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: YubaiSpace.none) {
                if row.estimated { Text("~").yubaiFont(YubaiFont.amount) }
                AmountLabel(cents: row.amount, hide: store.preferences.hideAmounts, sign: row.inflow ? .inflow : .none, ink: row.state == .paid ? YubaiColor.labelSecondary : row.inflow ? YubaiColor.brandInk : YubaiColor.label)
            }.foregroundStyle(row.state == .paid ? YubaiColor.labelSecondary : row.inflow ? YubaiColor.brandInk : YubaiColor.label).fixedSize(horizontal: true, vertical: false)
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
    }
    private var content: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            if let id = row.planID {
                Button { edit(id) } label: { summary }
                    .buttonStyle(.plain).accessibilityElement(children: .contain).accessibilityAddTraits(.isButton)
                    .accessibilityLabel("改" + row.title)
                    .accessibilityIdentifier("editFixedFlow_" + id.uuidString)
            } else { summary }
            if let id = row.planID, row.state != .upcoming {
                if row.state == .paid {
                    FixedFlowCheck(planID: id, occurrence: row.date, title: row.title, amount: row.amount, inflow: row.inflow, state: row.state)
                        .onTapGesture { edit(id) }
                } else {
                    FixedFlowCheck(planID: id, occurrence: row.date, title: row.title, amount: row.amount, inflow: row.inflow, state: row.state)
                }
            } else if row.state == .paid { FixedFlowPaidMark(inflow: row.inflow, title: row.title) }
            else {
                Color.clear.frame(width: YubaiSize.rowIcon, height: YubaiSize.rowDouble).contentShape(Rectangle())
                    .onTapGesture { if let id = row.planID { edit(id) } }.accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble)
            .opacity(row.state == .paid ? 0.7 : 1).background(YubaiColor.paperSheet)
            .animation(YubaiMotion.control(reduceMotion: reduceMotion), value: row.state)
    }
    private func edit(_ id: UUID) { store.sheetSource = nil; store.sheet = .editPlan(id) }

}

private struct FixedFlowPaidMark: View {
    let inflow: Bool
    let title: String
    var body: some View {
        Image(systemName: "checkmark").yubaiFont(YubaiFont.row, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
            .frame(width: YubaiSize.rowIcon, height: YubaiSize.rowIcon).background(YubaiColor.neutralSoft, in: Circle())
            .contentShape(Circle())
            .accessibilityLabel((inflow ? "已收到 " : "已付 ") + title)
    }
}

struct FixedFlowCheck: View {
    @Environment(AppStore.self) private var store
    @State private var editing = false
    @State private var editedAmount = ""
    let planID: UUID
    let occurrence: Date
    let title: String
    let amount: Int64
    var inflow = false
    var state = FixedFlowState.due
    private var label: String { (inflow ? "收到了 " : "付了 ") + title }
    var body: some View {
        Group {
            if state == .paid {
                FixedFlowPaidMark(inflow: inflow, title: title)
                    .accessibilityIdentifier("settledFixedFlow_" + planID.uuidString + "_" + Dates.text(occurrence))
            } else if state == .due {
                Button { settle() } label: {
                    Text(inflow ? "收到了" : "付了").yubaiFont(YubaiFont.row, weight: .semibold)
                        .foregroundStyle(inflow ? YubaiColor.brandInk : YubaiColor.amberInk)
                        .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.rowIcon)
                        .overlay { Capsule().strokeBorder(inflow ? YubaiColor.brandInk : YubaiColor.amberInk, lineWidth: 1.5) }
                        // Keep the visible control flush with the shared swipe action gap.
                        .yubaiHitTarget(alignment: .trailing)
                }.buttonStyle(PressButtonStyle()).accessibilityLabel(label)
                    .accessibilityValue(FixedFlowPresentation.state(state, inflow: inflow))
                    .accessibilityIdentifier("settleFixedFlow_" + planID.uuidString + "_" + Dates.text(occurrence))
                    .contextMenu {
                        Button((inflow ? "收到了 " : "付了 ") + (store.preferences.hideAmounts ? "••••" : AmountLabel.text(amount))) { _ = settle() }
                        Button("改金额再记", action: edit)
                        Button("跳过这期") {
                            let change = ChangeSet(source: "用户操作", reason: "跳过这期", items: [.skipOccurrence(planID, occurrence)])
                            _ = store.apply(change, label: "跳过这期")
                        }
                    }
                    .accessibilityAction(named: "改金额再记", edit)
            }
        }
            .sheet(isPresented: $editing) {
                NavigationStack {
                    FixedFlowSettlementEditor(title: title, amount: editedAmount) { amount in settle(amount) }
                        .environment(store).appErrors()
                }.presentationDragIndicator(.visible).yubaiSheetBackground()
                    #if os(iOS)
                    .presentationDetents([.large])
                    #endif
            }
    }
    private func edit() { guard state != .paid else { return }; editedAmount = Money.input(amount); editing = true }
    @discardableResult private func settle(_ override: Int64? = nil) -> Bool {
        Self.record(planID: planID, occurrence: occurrence, title: title, amount: override ?? amount, inflow: inflow, store: store, override: override)
    }
    @MainActor @discardableResult static func record(planID: UUID, occurrence: Date, title: String, amount: Int64, inflow: Bool, store: AppStore, override: Int64? = nil) -> Bool {
        do {
            let now = Date()
            let label = (inflow ? "收到了 " : "付了 ") + title
            if var pending = store.current.activeEntries.first(where: { $0.planID == planID && $0.occurrence.map(Dates.day) == Dates.day(occurrence) && $0.date > now }) {
                pending.date = now; pending.amount = override ?? pending.amount
                guard store.update(label, { try ManualBookkeeping.edit(pending, in: &$0, now: now) }) else { return false }
            } else {
                let change = try FixedFlows.settle(planID: planID, occurrence: occurrence, amount: override, in: store.current, now: now)
                guard store.apply(change, label: label) else { return false }
            }
            store.cancelEntrySaveMotion(); store.fixedFlowSettleTrigger &+= 1
            let value = store.preferences.hideAmounts ? "••••" : AmountLabel.text(amount)
            store.toast = "已记下 · " + title + " " + value
            return true
        } catch { store.error = error.localizedDescription; return false }
    }
}

struct FixedFlowSettlementEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let record: (Int64) -> Bool
    let initialAmount: Int64
    @State private var confirmingDiscard = false
    @State private var amount: String
    @State private var keypad = EntryKeypad()
    @State private var presented = false
    @State private var selected = false
    init(title: String, amount: String, record: @escaping (Int64) -> Bool) {
        self.title = title; self.record = record; initialAmount = (try? Money.parse(amount)) ?? 0; _amount = State(initialValue: amount)
    }
    var body: some View {
        ScrollViewReader { scroll in
                EntryForm(title: title + " · 这期金额", actionTitle: "记下",
                                  enabled: presented ? keypad.canSave : (try? Money.parse(amount)).map { $0 > 0 } ?? false,
                                  cancel: { if currentAmount != initialAmount { confirmingDiscard = true } else { dismiss() } }, save: {
                    finish()
                    if let cents = try? Money.parse(amount), record(cents) { dismiss() }
                }) {
                EditableAmountDisplay(amount: amount, keypad: keypad, presented: presented, selected: selected,
                                      identifier: "fixedFlowSettlementAmount") {
                    guard !presented else { return }
                    keypad = EntryKeypad(amount: (try? Money.parse(amount)) ?? 0); selected = true; presented = true
                }.id("settlementAmount")
            }.finishAmountOnOutsideTap(presented: presented, finish: finish)
                .task(id: presented) {
                    guard presented else { return }
                    do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                    withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { scroll.scrollTo("settlementAmount", anchor: .top) }
                }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            if presented {
                AmountKeypad(keypad: $keypad, amountSelected: $selected, canSave: keypad.canSave,
                             primaryTitle: "好", primaryIdentifier: "amountKeypadDone", save: finish)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: presented)
            .entryDiscardGuard(dirty: currentAmount != initialAmount, amount: currentAmount, confirming: $confirmingDiscard)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
    private var currentAmount: Int64 { presented ? keypad.amount ?? 0 : (try? Money.parse(amount)) ?? 0 }
    private func finish() {
        guard presented else { return }
        if let cents = keypad.resolve() { amount = Money.input(cents) }
        selected = false; presented = false
    }
}

struct FixedFlowEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var planID: UUID? = nil
    @State private var inflow = false
    @State private var amount = ""
    @State private var title = ""
    @State private var frequency = Frequency.monthly
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var category = "其他支出"
    @State private var installments: Int?
    @State private var autoPay = false
    @State private var estimated = false
    @State private var intoFixedSavings = false
    @State private var pickingSchedule = false
    @State private var confirmingStop = false
    @State private var confirmingDiscard = false
    @State private var initialSignature = ""
    @State private var initialized = false
    @State private var original: FixedFlowEdit?
    @State private var balances: [UUID: Int64] = [:]
    @State private var keypad = EntryKeypad()
    @State private var amountKeypadPresented = false
    @State private var amountSelected = false
    @State private var amountPreviewDates: [Date] = []
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accounts: [Account] { store.accounts.filter { !$0.archived || (planID != nil && $0.id == accountID) } }
    private var hasAccount: Bool { accounts.contains { $0.id == accountID } }
    private var categories: [String] { FixedFlows.categories(inflow: inflow, in: store.current) }
    private var savedPlan: Plan? { store.plans.first { $0.id == planID } }
    private var canStop: Bool { savedPlan.map { $0.active && $0.endDate == nil && $0.stoppedAt == nil } ?? false }
    private var scheduleChanged: Bool { original.map { $0.frequency != frequency || $0.date != Dates.day(date) } ?? true }
    private var scheduleDate: Date { !scheduleChanged && frequency != .once ? savedPlan?.dueDate ?? date : date }
    private var monthlyDay: Int? {
        guard !scheduleChanged, frequency == .monthly, let savedPlan else { return nil }
        return savedPlan.monthlyDay ?? Dates.calendar.component(.day, from: savedPlan.dueDate)
    }
    private var editChange: ChangeSet? {
        guard let planID, let original, let cents = try? Money.parse(amount), cents > 0 else { return nil }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != original.title || cents != original.amount || frequency != original.frequency || Dates.day(date) != original.date ||
                accountID != original.accountID || category != original.category || installments != original.installments ||
                autoPay != original.autoPay || estimated != original.estimated || intoFixedSavings != original.intoFixedSavings else { return nil }
        return try? update(planID)
    }
    private var plan: Plan? {
        guard let cents = try? Money.parse(amount), cents > 0 else { return nil }
        var plan = Plan(title: title.trimmingCharacters(in: .whitespacesAndNewlines), amount: cents, dueDate: Dates.day(date),
                        frequency: frequency, inflow: inflow, category: category, nature: inflow ? .income : .expense)
        plan.accountID = hasAccount ? accountID : nil; plan.installments = frequency == .once ? nil : installments
        plan.autoPay = autoPay && hasAccount; plan.autoPaySince = plan.autoPay ? Dates.day(Date()) : nil; plan.estimated = estimated; plan.intoFixedSavings = inflow && intoFixedSavings
        return plan
    }
    private var validationError: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title.isEmpty && original == nil ? nil : "填写账单名字" }
        if !amount.isEmpty && ((try? Money.parse(amount)).map { $0 <= 0 } ?? true) { return "金额须大于 0.00 元" }
        if let planID, original != nil {
            do { _ = try update(planID) } catch FixedFlowEditError.noChanges { return nil } catch { return error.localizedDescription }
        }
        return nil
    }
    var body: some View {
        let change = amountKeypadPresented ? nil : editChange
        ScrollViewReader { scroll in
                EntryForm(title: planID == nil ? "添加账单" : "改账单", actionTitle: "好",
                          enabled: planID == nil ? plan != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : change != nil,
                          scrollIdentifier: "fixedFlowEditor", cancel: cancel, save: save) {
                if planID == nil { Segmented(choices: [(false, "要付"), (true, "要收")], selection: $inflow) }
                EditableAmountDisplay(amount: amount, keypad: keypad, presented: amountKeypadPresented,
                                      selected: amountSelected, identifier: "fixedFlowAmount", open: openAmount)
                    .id("fixedFlowAmountRow")
                InlineFieldError(message: amount.isEmpty ? nil : ((try? Money.parse(amount)).map { $0 <= 0 } ?? true) ? "金额须大于 0.00 元" : nil)
                EntrySavingHintBar(hint: EntryHint.make(ledger: store.current, amount: amountKeypadPresented ? keypad.amount ?? 0 : (try? Money.parse(amount)) ?? 0,
                                                       category: category, isFixedBill: true, nature: inflow ? .income : .expense))
                EntryFormFields(purpose: $title, purposeTitle: "名字", purposeIdentifier: "fixedFlowTitle", purposeError: title.isEmpty && original != nil ? "填写账单名字" : nil, nature: inflow ? .income : .expense,
                                accounts: accounts, balances: balances, accountID: $accountID, otherAccountID: .constant(nil), date: $date,
                                showsRecent: false, showsDate: false, optionalAccount: true, accountTitle: inflow ? "收到哪里" : "从哪里付", focus: $titleFocused) {
                        EntryFormRow(title: "分类") {
                            Menu {
                                ForEach(categories, id: \.self) { name in Button(name) { category = name } }
                            } label: { Text(Classification.displayCategory(category)).manualFormChip() }.buttonStyle(PressButtonStyle())
                                .accessibilityLabel("分类").accessibilityValue(Classification.displayCategory(category))
                                .accessibilityIdentifier("fixedFlowCategory")
                        }.frame(minHeight: YubaiSize.rowSingle)
                        EntryFormDivider()
                        EntryFormRow(title: "共几期") {
                            HStack(spacing: 0) {
                                Button { let value = max(0, (installments ?? 0) - 1); installments = value == 0 ? nil : value } label: { Image(systemName: "minus").frame(width: 34, height: 30).contentShape(Capsule()) }
                                    .disabled(installments == nil).accessibilityLabel("减少期数").buttonRepeatBehavior(.enabled)
                                Text(installments.map { "\($0) 期" } ?? "一直").fixedSize().yubaiFont(YubaiFont.callout).padding(.horizontal, 8)
                                Button { installments = min(2400, (installments ?? 0) + 1) } label: { Image(systemName: "plus").frame(width: 34, height: 30).contentShape(Capsule()) }
                                    .disabled(installments == 2400).accessibilityLabel("增加期数").buttonRepeatBehavior(.enabled)
                            }.background(YubaiColor.raised, in: Capsule()).buttonStyle(.plain)
                                .disabled(frequency == .once).accessibilityIdentifier("fixedFlowInstallments")
                        }.frame(minHeight: YubaiSize.rowSingle)
                        InlineFieldError(message: validationError)
                }
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        Toggle("到日子自动记", isOn: $autoPay).tint(YubaiColor.toggleOn).disabled(!hasAccount).accessibilityIdentifier("fixedFlowAutoPay").frame(minHeight: YubaiSize.rowSingle)
                        EntryFormDivider()
                        Toggle("金额会变", isOn: $estimated).tint(YubaiColor.toggleOn).accessibilityIdentifier("fixedFlowEstimated").frame(minHeight: YubaiSize.rowSingle)
                        if inflow {
                            EntryFormDivider()
                            Toggle(isOn: $intoFixedSavings) { Label("到账放进存着不动", systemImage: "lock") }
                                .tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.rowSingle).accessibilityIdentifier("fixedFlowIntoFixedSavings")
                        }
                    }.yubaiFont(YubaiFont.row).tint(YubaiColor.toggleOn)
                }
                preview(change: change)
                if canStop {
                    Button("停掉") { confirmingStop = true }.buttonStyle(DestructiveButtonStyle())
                        .accessibilityIdentifier("fixedFlowEditStop")
                }
            }
                // No identifier here: it would replace the sheet header buttons' own ones.
                .finishAmountOnOutsideTap(presented: amountKeypadPresented, finish: finishAmount)
                .task(id: amountKeypadPresented) {
                    guard amountKeypadPresented else { return }
                    do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                    withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { scroll.scrollTo("fixedFlowAmountRow", anchor: .top) }
                }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            EntryKeyboardTray(purpose: $title, purposeTitle: "名字", purposeIdentifier: "fixedFlowTitle", focus: $titleFocused) {
                ChipFlow {
                    EntryDateChip(date: $date, inTray: true, allowsFuture: true)
                    EntryAccountMenu(accounts: accounts, balances: balances, selection: $accountID, optional: true, inTray: true)
                    EntryRepeatChip(selected: frequency != .once,
                                    value: frequency == .monthly ? "每月 \(monthlyDay ?? Dates.calendar.component(.day, from: date)) 号" : frequency == .once ? "不重复" : frequency.label,
                                    inTray: true) { pickingSchedule = true }.accessibilityIdentifier("fixedFlowSchedule")
                }
            } keys: {
                if amountKeypadPresented {
                    AmountKeypad(keypad: $keypad, amountSelected: $amountSelected, canSave: keypad.canSave,
                                 primaryTitle: "完成", primaryIdentifier: "amountKeypadDone", save: finishAmount, embedded: true)
                }
            }
        }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: amountKeypadPresented)
            .environment(\.yubaiFormSurface, true)
            #if os(iOS)
            .presentationDetents([.large])
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .entryDiscardGuard(dirty: initialized && signature != initialSignature, amount: amountKeypadPresented ? keypad.amount ?? 0 : (try? Money.parse(amount)) ?? 0, confirming: $confirmingDiscard)
            .onAppear { load(); openAmount() }
            .onChange(of: titleFocused) { _, focused in if focused { finishAmount() } else { openAmount() } }
            .onChange(of: accountID) { _, _ in if !hasAccount { autoPay = false } }
            .onChange(of: inflow) { _, value in
                if !value { intoFixedSavings = false }
                if planID == nil, !categories.contains(category) { category = inflow ? "其他收入" : "其他支出" }
            }
            .modifier(FixedFlowStopConfirmation(planID: planID, title: savedPlan?.title ?? title, inflow: inflow,
                                                isPresented: $confirmingStop, onStopped: { dismiss() }))
            .popover(isPresented: $pickingSchedule) {
                VStack(spacing: YubaiSpace.gapGroup) {
                    Picker("多久一次", selection: $frequency) { ForEach(Frequency.allCases) { Text($0.label).tag($0) } }.frame(width: 320)
                    DatePicker("第一次", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).frame(width: 320, height: 360).fixedSize()
                    Button("完成") { pickingSchedule = false }.frame(minHeight: YubaiSize.tapMin)
                }.padding(YubaiSpace.insetCard).frame(minWidth: 300).transaction { $0.animation = nil }
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
    }
    private func openAmount() {
        guard !amountKeypadPresented else { return }
        titleFocused = false
        amountPreviewDates = previewDates(change: editChange)
        keypad = EntryKeypad(amount: (try? Money.parse(amount)) ?? 0)
        amountSelected = true; amountKeypadPresented = true
    }
    private func finishAmount() {
        guard amountKeypadPresented else { return }
        if let cents = keypad.resolve() { amount = Money.input(cents) }
        amountSelected = false; amountKeypadPresented = false
    }
    private func load() {
        guard !initialized else { return }; initialized = true
        if let planID {
            guard let value = FixedFlows.edit(planID: planID, in: store.current) else { dismiss(); return }
            original = value; title = value.title; amount = Money.input(value.amount); frequency = value.frequency; date = value.date
            inflow = value.inflow; accountID = value.accountID; category = value.category
            installments = value.installments; autoPay = value.autoPay; estimated = value.estimated; intoFixedSavings = value.intoFixedSavings
        }
        balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) }); initialSignature = signature
    }
    private var signature: String { "\(inflow)|\(amountKeypadPresented ? keypad.amount ?? 0 : (try? Money.parse(amount)) ?? 0)|\(title)|\(frequency)|\(Dates.day(date))|\(accountID?.uuidString ?? "")|\(category)|\(installments ?? 0)|\(autoPay)|\(estimated)|\(intoFixedSavings)" }
    private func cancel() { if signature != initialSignature { confirmingDiscard = true } else { dismiss() } }
    private func preview(change: ChangeSet?) -> some View {
        let dates = previewDates(change: change)
        return HStack(spacing: YubaiSpace.gapGroup) {
            ForEach(dates, id: \.self) { day in
                VStack(spacing: YubaiSpace.space4) {
                    FixedFlowDot(state: Dates.day(day) <= Dates.day(Date()) ? .due : .upcoming)
                    Text(FixedFlowPresentation.monthDay(day)).yubaiFont(YubaiFont.chartLabel).foregroundStyle(YubaiColor.labelSecondary)
                }.frame(maxWidth: .infinity)
            }
        }.padding(.top, YubaiSpace.space4).accessibilityElement(children: .ignore)
            .accessibilityLabel("接下来\(dates.count)期：" + dates.map(FixedFlowPresentation.monthDay).joined(separator: "、"))
    }
    private func previewDates(change: ChangeSet?) -> [Date] {
        if amountKeypadPresented { return amountPreviewDates }
        var preview = savedPlan ?? Plan(title: title, amount: 1, dueDate: Dates.day(date), frequency: frequency)
        if let item = change?.items.first, case .updatePlan(let updated) = item { preview = updated }
        else {
            if scheduleChanged {
                preview.dueDate = Dates.day(date); preview.frequency = frequency
                preview.monthlyDay = frequency == .monthly ? Dates.calendar.component(.day, from: date) : nil
                // Even while another field is invalid, retain the linked periods
                // so the finite preview still counts the same history as Core.
                if let planID {
                    let linked = store.current.activeEntries.filter { $0.planID == planID }.compactMap(\.occurrence).map(Dates.day)
                    preview.previousOccurrences = Array(Set(preview.previousOccurrences + linked)).sorted()
                }
            }
            preview.installments = frequency == .once && planID == nil ? nil : installments
        }
        // This is a read-only schedule preview, including for stopped plans.
        preview.active = true; preview.endDate = nil; preview.stoppedAt = nil
        var ledger = store.current; ledger.plans = [preview]; ledger.rents = []
        let first = Dates.day(date)
        let end = frequency.advance(first, by: 4)
        let days = max(1, (Dates.calendar.dateComponents([.day], from: first, to: end).day ?? 0) + 1)
        return Array(Finance.occurrences(in: ledger, now: first, days: days).filter { Dates.day($0.date) >= first }.prefix(4).map(\.date))
    }
    private func save() {
        finishAmount()
        if let planID {
            do {
                let change = try update(planID)
                if store.apply(change, label: "修改安排") { dismiss() }
            } catch FixedFlowEditError.noChanges { }
            catch { store.error = error.localizedDescription }
            return
        }
        guard let plan, !plan.title.isEmpty else { return }
        let change = ChangeSet(source: "用户操作", reason: "添加安排「\(plan.title)」", items: [.addPlan(plan)])
        if store.apply(change, label: "添加安排") { dismiss() }
    }
    private func update(_ planID: UUID) throws -> ChangeSet {
        try FixedFlows.update(planID: planID, title: title, amount: Money.parse(amount), frequency: frequency, date: date,
                              accountID: accountID, category: category, installments: installments,
                              autoPay: autoPay, estimated: estimated, in: store.current, intoFixedSavings: intoFixedSavings)
    }
}

private extension View {
    func manualFormChip() -> some View {
        self.yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
            .background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
    }
}

// MARK: - Round 45 · 固定账单：勾、菜单、付了、对上了、加一项、详情

/// 在「付了」「这笔对上了」「不是，另记一笔」之间来回时，记住用户已经给过的选择（只在内存里）。
@MainActor enum BillSession {
    static var declined: Set<String> = []
    static var amounts: [String: Int64] = [:]
    static func key(_ planID: UUID, _ occurrence: Date) -> String { planID.uuidString + "_" + Dates.text(occurrence) }
    static func clear(_ planID: UUID, _ occurrence: Date) {
        let id = Self.key(planID, occurrence)
        declined.remove(id); amounts[id] = nil
    }
}

@MainActor enum BillPayFlow {
    /// 点勾或菜单里的「付了」：金额会变 → 键盘；否则先找账本里已有的一笔；都没有才直接记下。
    static func pay(planID: UUID, occurrence: Date, store: AppStore) {
        guard let plan = store.plans.first(where: { $0.id == planID }) else { return }
        store.sheetSource = nil
        if plan.estimated {
            store.sheet = .billPay(planID: planID, occurrence: occurrence)
            return
        }
        if let match = FixedFlows.matchingEntries(planID: planID, occurrence: occurrence, in: store.current, now: Date()).first {
            store.sheet = .billMatch(planID: planID, occurrence: occurrence, entryID: match.id)
            return
        }
        let amount = FixedFlows.expectedAmount(planID: planID, in: store.current, now: store.financialNow) ?? plan.amount
        FixedFlowCheck.record(planID: planID, occurrence: occurrence, title: plan.title, amount: amount, inflow: plan.inflow, store: store)
    }
    static func skip(planID: UUID, occurrence: Date, store: AppStore) {
        let change = ChangeSet(source: "用户操作", reason: "跳过这期", items: [.skipOccurrence(planID, occurrence)])
        _ = store.apply(change, label: "这个月不用付")
    }
    /// 这期留出的钱：算式里有就按算式的，没有按安排里的。
    static func reserved(planID: UUID, occurrence: Date, store: AppStore) -> Int64? {
        let day = Dates.day(occurrence)
        return store.formula.bills.first { $0.planID == planID && Dates.day($0.date) == day && $0.state != .paid }?.amount
    }
}

@MainActor enum BillEditing {
    /// 改一项安排里的某几个字段（金额、几号、账户、自动记），其余原样带上。
    @discardableResult static func change(planID: UUID, store: AppStore, label: String, _ mutate: (inout FixedFlowEdit) -> Void) -> Bool {
        guard var edit = FixedFlows.edit(planID: planID, in: store.current) else { return false }
        mutate(&edit)
        do {
            let change = try FixedFlows.update(planID: planID, title: edit.title, amount: edit.amount, frequency: edit.frequency, date: edit.date,
                                               accountID: edit.accountID, category: edit.category, installments: edit.installments,
                                               autoPay: edit.autoPay, estimated: edit.estimated, in: store.current,
                                               intoFixedSavings: edit.intoFixedSavings)
            return store.apply(change, label: label)
        } catch FixedFlowEditError.noChanges {
            return false
        } catch {
            store.error = error.localizedDescription
            return false
        }
    }
}

/// 首页「接下来 7 天」和算式页同一颗勾。点：金额会变的先问金额，否则先找账本里已有的一笔，都没有才直接记下；长按：六项菜单。
struct BillCheck: View {
    @Environment(AppStore.self) private var store
    let planID: UUID
    let occurrence: Date
    private var plan: Plan? { store.plans.first { $0.id == planID } }
    private var paid: Bool {
        let day = Dates.day(occurrence)
        if let bill = store.formula.bills.first(where: { $0.planID == planID && Dates.day($0.date) == day }) { return bill.state == .paid }
        if store.sortedEntries.contains(where: { $0.deletedAt == nil && $0.planID == planID && $0.occurrence.map(Dates.day) == day && $0.date > store.financialNow }) { return false }
        return plan?.settledOccurrences.contains { Dates.day($0) == day } ?? false
    }
    var body: some View {
        let title = plan?.title ?? ""
        let inflow = plan?.inflow ?? false
        if paid {
            mark(filled: true).accessibilityElement(children: .ignore)
                .accessibilityLabel((inflow ? "已收到 " : "已付 ") + title)
                .accessibilityIdentifier("billCheck_" + planID.uuidString)
        } else {
            Button { BillPayFlow.pay(planID: planID, occurrence: occurrence, store: store) } label: { mark(filled: false) }
                .buttonStyle(PressButtonStyle())
                .accessibilityLabel((inflow ? "收到了 " : "付了 ") + title)
                .accessibilityHint("长按有更多选项")
                .accessibilityIdentifier("billCheck_" + planID.uuidString)
                .accessibilityValue(FixedFlowPresentation.monthDay(occurrence))
                .billRowMenu(planID: planID, occurrence: occurrence)
        }
    }
    private func mark(filled: Bool) -> some View {
        Image(systemName: "checkmark").yubaiFont(YubaiFont.row, weight: .semibold)
            .foregroundStyle(filled ? YubaiColor.onBrand : YubaiColor.labelSecondary)
            .frame(width: YubaiSize.rowIcon, height: YubaiSize.rowIcon)
            .background(filled ? YubaiColor.brand : YubaiColor.neutralSoft, in: Circle())
            .yubaiHitTarget()
    }
}

/// 长按一项账单出的菜单：几种情况各一行，都是一步完成；最后一项是真的停掉，用琥珀色。
struct BillRowMenu: View {
    @Environment(AppStore.self) private var store
    let planID: UUID
    let occurrence: Date
    let stop: () -> Void
    var body: some View {
        let plan = store.plans.first { $0.id == planID }
        let amount = BillPayFlow.reserved(planID: planID, occurrence: occurrence, store: store) ?? plan?.amount ?? 0
        let payTitle = (plan?.inflow == true ? "收到了 " : "付了 ") + amount2(amount, hide: store.preferences.hideAmounts)
        Button(payTitle) { BillPayFlow.pay(planID: planID, occurrence: occurrence, store: store) }
            .accessibilityIdentifier("billMenu_pay")
        Button("已经记过了") { present(.billLink(planID: planID, occurrence: occurrence)) }
            .accessibilityIdentifier("billMenu_linked")
        Button("金额不一样") { present(.billPay(planID: planID, occurrence: occurrence)) }
            .accessibilityIdentifier("billMenu_amount")
        Button("这个月不用付") { BillPayFlow.skip(planID: planID, occurrence: occurrence, store: store) }
            .accessibilityIdentifier("billMenu_skip")
        Button("改到别的日子") { present(.billMove(planID: planID, occurrence: occurrence)) }
            .accessibilityIdentifier("billMenu_move")
        Button("以后都没有这项了", action: stop)
            .foregroundStyle(YubaiColor.amberInk).accessibilityIdentifier("billMenu_stop")
    }
    private func present(_ sheet: AppSheet) {
        store.sheetSource = nil; store.sheet = sheet
    }
}

/// 只挪当前这一期；清掉改期时把 Core 保存的原排程日交回去。
struct BillMoveSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    let occurrence: Date
    @State private var day: Date
    @State private var today = Date()
    init(planID: UUID, occurrence: Date) {
        self.planID = planID; self.occurrence = occurrence
        _day = State(initialValue: Dates.day(occurrence))
    }
    private var original: Date? {
        store.plans.first { $0.id == planID }?.occurrenceDateOverrides?.first { Dates.day($0.value) == Dates.day(occurrence) }?.key
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                ManualSheetHeader(title: "改到别的日子", actionTitle: "好", actionIdentifier: "billMoveDone", cancelIdentifier: "billMoveCancel",
                                  cancel: { dismiss() }, action: save)
                EntryCalendarView(selection: $day, today: today, identifier: "billMoveCalendar")
                if let original {
                    Button { clear() } label: {
                        Label(FixedFlowPresentation.monthDay(original), systemImage: "arrow.uturn.backward")
                            .yubaiFont(YubaiFont.callout).frame(minHeight: YubaiSize.tapMin)
                    }.buttonStyle(SecondaryButtonStyle()).accessibilityLabel("回到原定日期，" + FixedFlowPresentation.monthDay(original))
                        .accessibilityIdentifier("billMoveClear")
                }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.gapSection)
        }.paperBackground().accessibilityIdentifier("billMoveSheet")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.medium, .large])
            #endif
    }
    private func save() {
        let planID = planID, occurrence = occurrence, date = day
        let title = store.plans.first { $0.id == planID }?.title ?? "固定账单"
        if store.update("改到别的日子", entryMotion: false, showToast: false, { ledger in
            try FixedFlows.moveOccurrence(planID: planID, occurrence: occurrence, to: date, in: &ledger, now: Date())
        }) { store.toast = title + " · " + FixedFlowPresentation.monthDay(date); dismiss() }
    }
    private func clear() {
        let planID = planID, occurrence = occurrence
        let date = original ?? occurrence
        let title = store.plans.first { $0.id == planID }?.title ?? "固定账单"
        if store.update("改到别的日子", entryMotion: false, showToast: false, { ledger in
            try FixedFlows.clearOccurrenceMove(planID: planID, occurrence: occurrence, in: &ledger, now: Date())
        }) { store.toast = title + " · " + FixedFlowPresentation.monthDay(date); dismiss() }
    }
}

private struct BillRowMenuModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var confirmingStop = false
    let planID: UUID
    let occurrence: Date
    func body(content: Content) -> some View {
        let plan = store.plans.first { $0.id == planID }
        content.contextMenu { BillRowMenu(planID: planID, occurrence: occurrence, stop: { confirmingStop = true }) }
            .modifier(FixedFlowStopConfirmation(planID: planID, title: plan?.title ?? "", inflow: plan?.inflow ?? false, isPresented: $confirmingStop))
    }
}

extension View {
    /// 长按出 `BillRowMenu`；停掉要确认。
    func billRowMenu(planID: UUID, occurrence: Date) -> some View {
        modifier(BillRowMenuModifier(planID: planID, occurrence: occurrence))
    }
}

/// 账单弹窗的标题行：名字、一个小数、取消。
private struct BillSheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String? = nil
    var body: some View { AmountSheetHeader(title: title, subtitle: subtitle, cancel: { dismiss() }) }
}

/// 账本里的一笔：首字、名字、日期·账户·来源、金额。
private struct BillEntryRow: View {
    @Environment(AppStore.self) private var store
    let entry: Entry
    var body: some View {
        let outflow = entry.nature == .expense
        let detail = FixedFlowPresentation.monthDay(entry.date) + " · " + store.accountName(entry.accountID) + (entry.batchID != nil ? " · 导入" : "")
        HStack(spacing: YubaiSpace.gapGroup) {
            Text(String(entry.displayTitle.prefix(1))).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.iconInk)
                .frame(width: YubaiSize.rowIcon + YubaiSpace.space4, height: YubaiSize.rowIcon + YubaiSpace.space4)
                .background(YubaiColor.iconTile, in: RoundedRectangle(cornerRadius: YubaiRadius.control)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(entry.displayTitle).yubaiFont(YubaiFont.rowTitle)
                Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts, role: .small, sign: outflow ? .outflow : .inflow,
                        ink: outflow ? YubaiColor.label : YubaiColor.brandInk).fixedSize(horizontal: true, vertical: false)
        }.contentShape(Rectangle())
    }
}

// MARK: 付了（金额会变的先改金额）

struct BillPaySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    let occurrence: Date
    var body: some View {
        if let plan = store.plans.first(where: { $0.id == planID }) {
            let expected = FixedFlows.expectedAmount(planID: planID, in: store.current, now: store.financialNow) ?? plan.amount
            BillPayEditor(plan: plan, occurrence: occurrence, expected: expected)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}

private struct BillPayEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: Plan
    let occurrence: Date
    let expected: Int64
    @State private var keypad: EntryKeypad

    init(plan: Plan, occurrence: Date, expected: Int64) {
        self.plan = plan; self.occurrence = occurrence; self.expected = expected
        let remembered = MainActor.assumeIsolated { BillSession.amounts[BillSession.key(plan.id, occurrence)] }
        _keypad = State(initialValue: EntryKeypad(amount: remembered ?? expected))
    }

    private var amount: Int64 { keypad.amount ?? 0 }
    private var valid: Bool { amount > 0 && amount <= Money.limit }
    private var rows: [AmountSheetRow] {
        guard valid, !plan.inflow, let reserved = BillPayFlow.reserved(planID: plan.id, occurrence: occurrence, store: store) else { return [] }
        let hide = store.preferences.hideAmounts
        let diff = reserved - amount
        let available = store.funds.available + diff
        if diff == 0 { return [AmountSheetRow(label: "还能花", value: amount2(available, hide: hide))] }
        let label = (diff > 0 ? "比留出的少 " : "比留出的多 ") + amount2(abs(diff), hide: hide)
        return [AmountSheetRow(label: label, value: "还能花 " + amount2(available, hide: hide), amber: diff < 0)]
    }

    var body: some View {
        AmountEntrySheet(title: plan.title, subtitle: "上次 " + amount2(expected, hide: store.preferences.hideAmounts),
                         keypad: $keypad, rows: rows, primaryTitle: plan.inflow ? "收到了" : "付了", canSave: valid, save: save)
            #if os(iOS)
            .presentationDetents([.height(640), .large])
            #endif
    }

    private func save() {
        guard valid else { return }
        let value = amount
        let key = BillSession.key(plan.id, occurrence)
        if !BillSession.declined.contains(key),
           let match = FixedFlows.matchingEntries(planID: plan.id, occurrence: occurrence, in: store.current, now: Date()).first {
            BillSession.amounts[key] = value
            store.sheet = .billMatch(planID: plan.id, occurrence: occurrence, entryID: match.id)
            return
        }
        if FixedFlowCheck.record(planID: plan.id, occurrence: occurrence, title: plan.title, amount: value, inflow: plan.inflow, store: store, override: value) {
            BillSession.clear(plan.id, occurrence)
            dismiss()
        }
    }
}

// MARK: 其实已经记过了

struct BillMatchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    let occurrence: Date
    let entryID: UUID
    var body: some View {
        if let plan = store.plans.first(where: { $0.id == planID }), let entry = store.entriesByID[entryID] {
            BillMatchContent(plan: plan, entry: entry, occurrence: occurrence,
                             expected: FixedFlows.expectedAmount(planID: planID, in: store.current, now: store.financialNow) ?? plan.amount)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }
}

private struct BillMatchContent: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: Plan
    let entry: Entry
    let occurrence: Date
    let expected: Int64
    private var resultRow: (label: String, value: String, amber: Bool)? {
        guard !plan.inflow, let reserved = BillPayFlow.reserved(planID: plan.id, occurrence: occurrence, store: store) else { return nil }
        let hide = store.preferences.hideAmounts
        let diff = reserved - entry.amount
        let available = amount2(store.funds.available + diff, hide: hide)
        if diff == 0 { return ("还能花", available, false) }
        return ((diff > 0 ? "比留出的少 " : "比留出的多 ") + amount2(abs(diff), hide: hide), "还能花 " + available, diff < 0)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                BillSheetHeader(title: plan.title, subtitle: amount2(expected, hide: store.preferences.hideAmounts))
                Text("账本里已经有一笔").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                Card { BillEntryRow(entry: entry) }
                if let row = resultRow { ResultBar(label: row.label, value: row.value, amber: row.amber) }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.sheetHeaderTop)
        }.scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
                VStack(spacing: YubaiSpace.space8) {
                    Button("就是这笔", action: confirm).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("billMatchConfirm")
                    Button("不是，另记一笔", action: separate).buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("billMatchSeparate")
                }.padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.space8)
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.height(520), .large])
            #endif
    }
    private func confirm() {
        let planID = plan.id, entryID = entry.id, day = occurrence
        if store.update("账单已付", { ledger in try FixedFlows.markPaid(planID: planID, occurrence: day, with: entryID, in: &ledger) }) {
            BillSession.clear(planID, day)
            dismiss()
        }
    }
    private func separate() {
        let key = BillSession.key(plan.id, occurrence)
        BillSession.declined.insert(key)
        if plan.estimated {
            store.sheet = .billPay(planID: plan.id, occurrence: occurrence)
            return
        }
        if FixedFlowCheck.record(planID: plan.id, occurrence: occurrence, title: plan.title, amount: expected, inflow: plan.inflow, store: store) {
            BillSession.clear(plan.id, occurrence)
            dismiss()
        }
    }
}

// MARK: 已经记过了（从最近的账里挑）

struct BillLinkSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    let occurrence: Date
    @State private var candidates: [Entry] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                BillSheetHeader(title: store.plans.first { $0.id == planID }?.title ?? "")
                if candidates.isEmpty {
                    Text("没有可选的账").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                } else {
                    Text("账本里已经有一笔").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    CardRows(candidates) { entry in
                        Button { link(entry) } label: { BillEntryRow(entry: entry).padding(.vertical, YubaiSpace.space8) }
                            .buttonStyle(PressButtonStyle()).accessibilityIdentifier("billLink_" + entry.id.uuidString)
                    }
                }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.sheetHeaderTop).padding(.bottom, YubaiSpace.gapSection)
        }.paperBackground().accessibilityIdentifier("billLinkSheet")
            .task { candidates = Array(FixedFlows.linkCandidates(planID: planID, in: store.current, now: Date()).prefix(40)) }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.large])
            #endif
    }
    private func link(_ entry: Entry) {
        let planID = planID, day = occurrence, entryID = entry.id
        if store.update("账单已付", { ledger in try FixedFlows.markPaid(planID: planID, occurrence: day, with: entryID, in: &ledger) }) {
            BillSession.clear(planID, day)
            dismiss()
        }
    }
}

// MARK: 每月几号

private struct BillDayPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    let current: Int
    let pick: (Int) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                BillSheetHeader(title: "每月几号")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: YubaiSpace.space8), count: textSize.isAccessibilitySize ? 4 : 7), spacing: YubaiSpace.space8) {
                    ForEach(1...28, id: \.self) { value in
                        Button { pick(value); dismiss() } label: {
                            Text("\(value)").yubaiFont(YubaiFont.callout).lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin)
                                .foregroundStyle(current == value ? YubaiColor.onBrand : YubaiColor.label)
                                .background(current == value ? YubaiColor.brand : YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                        }.buttonStyle(PressButtonStyle()).accessibilityLabel("每月 \(value) 号")
                            .accessibilityAddTraits(current == value ? .isSelected : [])
                            .accessibilityIdentifier("billDay_\(value)")
                    }
                }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.sheetHeaderTop).padding(.bottom, YubaiSpace.gapSection)
        }.paperBackground()
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
    }
}

// MARK: 一项固定账单

struct BillDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    @State private var history: FixedFlows.History?
    @State private var editingAmount = false
    @State private var editingDay = false
    @State private var confirmingStop = false
    @State private var keypad = EntryKeypad()
    private var plan: Plan? { store.plans.first { $0.id == planID } }

    var body: some View {
        Group {
            if let plan { content(plan) } else { Color.clear.onAppear { dismiss() } }
        }.navigationTitle(plan?.title ?? "").yubaiNavigation()
            .task(id: "\(store.ledgerRevision)-\(store.financialNow)") { await refreshHistory() }
    }

    private func content(_ plan: Plan) -> some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            settingsCard(plan)
            if let history, !history.entries.isEmpty { historyBlock(plan, history) }
            if plan.active && plan.endDate == nil && plan.stoppedAt == nil { stopButton }
        }.amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("billDetailPage")
            .sheet(isPresented: $editingAmount) {
                AmountEntrySheet(title: "金额", keypad: $keypad, primaryTitle: "好", canSave: keypad.canSave, save: {
                    if let value = keypad.resolve() { BillEditing.change(planID: planID, store: store, label: plan.title) { $0.amount = value } }
                    editingAmount = false
                }).presentationDragIndicator(.visible).yubaiSheetBackground()
                    #if os(iOS)
                    .presentationDetents([.height(520), .large])
                    #endif
            }
            .sheet(isPresented: $editingDay) {
                BillDayPicker(current: monthlyDay(plan), pick: { changeDay($0) }).presentationDragIndicator(.visible).yubaiSheetBackground()
            }
            .modifier(FixedFlowStopConfirmation(planID: planID, title: plan.title, inflow: plan.inflow, isPresented: $confirmingStop,
                                                onStopped: { dismiss() }))
    }

    private func monthlyDay(_ plan: Plan) -> Int {
        plan.monthlyDay ?? Dates.calendar.component(.day, from: plan.dueDate)
    }
    private func expected(_ plan: Plan) -> Int64 {
        FixedFlows.expectedAmount(planID: plan.id, in: store.current, now: store.financialNow) ?? plan.amount
    }
    @MainActor private func refreshHistory() async {
        let ledger = store.current; let planID = planID; let now = store.financialNow
        let value = await Task.detached(priority: .userInitiated) { FixedFlows.history(planID: planID, in: ledger, now: now) }.value
        guard !Task.isCancelled else { return }
        history = value
    }

    // MARK: 设置
    private func settingsCard(_ plan: Plan) -> some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                amountRow(plan)
                rowDivider
                dayRow(plan)
                rowDivider
                accountRow(plan)
                rowDivider
                autoRow(plan)
            }
        }
    }
    private var rowDivider: some View {
        Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true)
    }
    private func detailRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text(title).yubaiFont(YubaiFont.row)
                Spacer(minLength: YubaiSpace.space8)
                value()
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.row)
                value()
            }.padding(.vertical, YubaiSpace.space8)
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading)
    }
    private func amountRow(_ plan: Plan) -> some View {
        let value = amount2(expected(plan), hide: store.preferences.hideAmounts)
        let text = plan.estimated ? "每月不一样 · 约 " + value : value
        return Button {
            keypad = EntryKeypad(amount: expected(plan)); editingAmount = true
        } label: {
            detailRow("金额") { Text(text).yubaiFont(YubaiFont.rowTitle, weight: .semibold).multilineTextAlignment(.trailing) }
                .contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("billDetailAmount")
    }
    private func dayRow(_ plan: Plan) -> some View {
        let monthly = plan.frequency == .monthly
        return Button {
            if monthly { editingDay = true } else { store.sheetSource = nil; store.sheet = .editPlan(plan.id) }
        } label: {
            detailRow(monthly ? "每月几号" : "多久一次") {
                Text(monthly ? "\(monthlyDay(plan)) 号" : plan.frequency.label).yubaiFont(YubaiFont.rowTitle, weight: .semibold)
            }.contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("billDetailDay")
    }
    private func accountRow(_ plan: Plan) -> some View {
        let accounts = store.accounts.filter { !$0.archived }
        return Menu {
            ForEach(accounts) { account in
                Button(account.name) { BillEditing.change(planID: plan.id, store: store, label: plan.title) { $0.accountID = account.id } }
            }
        } label: {
            detailRow(plan.inflow ? "收到哪里" : "从哪付") {
                Text(store.accountName(plan.accountID)).yubaiFont(YubaiFont.rowTitle, weight: .semibold)
            }.contentShape(Rectangle())
        }.accessibilityIdentifier("billDetailAccount")
    }
    private func autoRow(_ plan: Plan) -> some View {
        let binding = Binding(get: { plan.autoPay }, set: { value in
            BillEditing.change(planID: plan.id, store: store, label: plan.title) { $0.autoPay = value; $0.estimated = !value }
        })
        return Toggle("到日子自动记一笔", isOn: binding).tint(YubaiColor.toggleOn).yubaiFont(YubaiFont.row)
            .disabled(plan.accountID == nil).frame(minHeight: YubaiSize.rowDouble).accessibilityIdentifier("billDetailAutoPay")
    }

    // MARK: 付过的
    private func historyBlock(_ plan: Plan, _ history: FixedFlows.History) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            HStack(alignment: .firstTextBaseline) {
                Text("付过的").yubaiFont(YubaiFont.caption, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                Spacer(minLength: YubaiSpace.space8)
                Text("平均 " + amount2(history.average, hide: store.preferences.hideAmounts))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.padding(.horizontal, YubaiSpace.insetCard)
            CardRows(history.entries, rowHeight: YubaiSize.rowSingle) { entry in historyRow(entry, plan: plan) }
        }.accessibilityIdentifier("billDetailHistory")
    }
    private func historyRow(_ entry: Entry, plan: Plan) -> some View {
        let note = entry.displayTitle == plan.title ? "" : entry.displayTitle
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) {
                Text(FixedFlowPresentation.monthDay(entry.date)).yubaiFont(YubaiFont.row)
                if !note.isEmpty { Text("· " + note).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).lineLimit(1) }
                Spacer(minLength: YubaiSpace.space8)
                AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts, role: .small, sign: plan.inflow ? .inflow : .outflow)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(FixedFlowPresentation.monthDay(entry.date) + (note.isEmpty ? "" : " · " + note)).yubaiFont(YubaiFont.row)
                AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts, role: .small, sign: plan.inflow ? .inflow : .outflow)
            }.padding(.vertical, YubaiSpace.space8)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .contextMenu {
                Button("和账单分开") { separate(entry) }.accessibilityIdentifier("billDetailUnlink")
            }
    }
    private func separate(_ entry: Entry) {
        let id = entry.id
        store.update("分开这一笔") { ledger in try FixedFlows.unlink(entryID: id, in: &ledger) }
    }

    private var stopButton: some View {
        Button { confirmingStop = true } label: {
            Text("以后都没有这项了").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.amberInk)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("billDetailStop")
    }

    private func changeDay(_ day: Int) {
        guard let edit = FixedFlows.edit(planID: planID, in: store.current) else { return }
        let calendar = Dates.calendar
        var parts = calendar.dateComponents([.year, .month], from: edit.date)
        parts.day = day
        guard let date = calendar.date(from: parts) else { return }
        BillEditing.change(planID: planID, store: store, label: plan?.title ?? "") { $0.date = Dates.day(date) }
    }
}
