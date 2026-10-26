import SwiftUI
import YubaiCore

struct FixedFlowsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let ledger = store.current
        let month = store.fixedFlowMonth
        let stopped = month.stopped
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.gapGroup) {
                    Text("\(Dates.calendar.component(.month, from: month.date))月还要付").yubaiFont(YubaiFont.heroLabel)
                    Spacer(minLength: YubaiSpace.space4)
                    HStack(spacing: YubaiSpace.space4) {
                        Text("要收").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        AmountLabel(cents: month.remainingInflow, hide: ledger.preferences.hideAmounts, role: .small, sign: .inflow, ink: YubaiColor.brandInk)
                    }
                }
                AmountLabel(cents: month.remainingOutflow, hide: ledger.preferences.hideAmounts, role: .display).accessibilityIdentifier("fixedFlowRemaining")
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
            if month.occurrences.isEmpty && stopped.isEmpty {
                Text("这个月还没有固定收付").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
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
            if !stopped.isEmpty { stoppedBills(stopped) }
        }.amountPrivacy(ledger.preferences.hideAmounts).accessibilityIdentifier("fixedFlowsScroll").navigationTitle("固定收付").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .primaryAction) {
                Button { store.sheetSource = nil; store.sheet = .addPlan } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加安排").accessibilityIdentifier("addFixedFlow")
            } }
    }
    private func overdueAmount(_ amount: Int64) -> some View {
        AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts, ink: YubaiColor.amberInk)
    }
    private func stoppedBills(_ rows: [FixedFlowArrangement]) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            Text("已停掉").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, YubaiSpace.insetCard)
            CardRows(rows) { row in
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                Text(row.title).yubaiFont(YubaiFont.rowTitle)
                                Text(row.detail).yubaiFont(YubaiFont.caption)
                                    .foregroundStyle(row.pending.isEmpty ? YubaiColor.labelSecondary : YubaiColor.amberInk)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            let amount = row.pending.isEmpty ? row.amount : row.pendingAmount
                            AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts,
                                        sign: row.inflow ? .inflow : .none, ink: YubaiColor.labelSecondary)
                                .fixedSize(horizontal: true, vertical: false)
                        }.foregroundStyle(YubaiColor.labelSecondary).opacity(row.pending.isEmpty ? 0.7 : 1)
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
    private func stoppedAction(_ title: String, row: FixedFlowArrangement, resolution: FixedFlowStopResolution) -> some View {
        let ink = resolution == .skip ? YubaiColor.labelSecondary : row.inflow ? YubaiColor.brandInk : YubaiColor.amberInk
        return Button(title) { resolve(row, resolution) }.yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(ink)
            .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.rowIcon)
            .overlay { Capsule().strokeBorder(ink, lineWidth: 1.5) }.yubaiHitTarget().buttonStyle(PressButtonStyle())
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
            if store.apply(change, label: "恢复安排") { store.toast = "已恢复" }
        } catch { store.error = error.localizedDescription }
    }
    @ViewBuilder private func bills(_ rows: [FixedFlowOccurrence]) -> some View {
        if !rows.isEmpty {
            CardRows(rows) { row in
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

private struct FixedFlowBillRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @GestureState private var dragging = false
    @State private var horizontal: Bool?
    #endif
    @State private var offset: CGFloat = 0
    @State private var resting: CGFloat = 0
    @State private var confirmingStop = false
    let row: FixedFlowOccurrence
    private let revealDistance = YubaiSize.swipeRevealDistance
    private var canEnd: Bool { store.current.plans.contains { $0.id == row.planID && $0.active && $0.endDate == nil } }
    private var pendingStop: [Occurrence] { row.planID.map { FixedFlows.unsettled(planID: $0, in: store.current) } ?? [] }
    private var pendingStopMessage: String? {
        let pending = pendingStop
        if pending.count > 1 { return "还有 \(pending.count) 期没记。" }
        return pending.first.map { FixedFlowPresentation.monthDay($0.date) + "这期还没记。" }
    }
    var body: some View {
        Group {
            if canEnd {
                SwipeActionRow(offset: offset, revealed: resting < 0, title: "停掉", tint: YubaiColor.neutralStrong, ink: YubaiColor.label, weight: .medium,
                               actionIdentifier: "stopFixedFlow_" + row.id, action: stop) { content }
                    #if os(iOS)
                    .gesture(HorizontalPan(shouldBegin: { $0 < 0 || resting < 0 }, changed: { distance in
                        offset = max(-revealDistance, min(0, resting + distance))
                    }, ended: { distance, _ in
                        resting = resting < 0 ? (distance > 0 ? 0 : -revealDistance) : (offset < -revealDistance * 0.43 ? -revealDistance : 0)
                        reset()
                    }, cancelled: reset))
                    #else
                    .simultaneousGesture(DragGesture(minimumDistance: 18)
                        .updating($dragging) { _, state, _ in state = true }
                        .onChanged { value in
                            if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.3 }
                            guard horizontal == true else { return }
                            offset = max(-revealDistance, min(0, resting + value.translation.width))
                        }.onEnded { _ in
                            guard horizontal == true else { return }
                            resting = offset < -revealDistance * 0.43 ? -revealDistance : 0; reset()
                        })
                    .onChange(of: dragging) { _, active in if !active { reset() } }
                    #endif
                    .onChange(of: canEnd) { _, value in if !value { resting = 0; reset() } }
                    .onDisappear { resting = 0; reset() }
                    .accessibilityAction(named: "停掉", stop)
            } else { content }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("fixedFlow_" + row.id)
            .uiTestAccessibilityValue(resting < 0 ? "revealed" : "closed", appendingTo: FixedFlowPresentation.state(row.state, inflow: row.inflow))
            .contextMenu {
                if row.state == .upcoming, let id = row.planID {
                    Button(row.inflow ? "提前标记收到了" : "提前标记付了") {
                        FixedFlowCheck.record(planID: id, occurrence: row.date, title: row.title, amount: row.amount, inflow: row.inflow, store: store)
                    }
                }
            }
            .alert("停掉「\(row.title)」？", isPresented: $confirmingStop) {
                stopActions
            } message: {
                if let message = pendingStopMessage { Text(message) }
            }
    }
    @ViewBuilder private var stopActions: some View {
        if pendingStop.isEmpty {
            Button("停掉以后的", role: .destructive) { performStop() }
                .accessibilityIdentifier("fixedFlowStopConfirm")
                .accessibilityHint("只停以后的，已到期账单和付过的记录保留")
        } else {
            Button(row.inflow ? "收到了，记一笔再停" : "付了，记一笔再停") { performStop(.settle) }
                .accessibilityIdentifier("fixedFlowStopConfirm")
            Button(row.inflow ? "没收到，这期也不要了" : "没付，这期也不要了", role: .destructive) { performStop(.skip) }
                .accessibilityIdentifier("fixedFlowStopSkip")
        }
        Button("取消", role: .cancel) { confirmingStop = false }.accessibilityIdentifier("fixedFlowStopCancel")
    }
    private func performStop(_ resolution: FixedFlowStopResolution? = nil) {
        guard let id = row.planID else { return }
        do {
            let change = try FixedFlows.stop(planID: id, resolution: resolution, in: store.current)
            if store.apply(change, label: "停掉安排") { store.cancelEntrySaveMotion(); store.toast = "已停掉" }
        } catch { store.error = error.localizedDescription }
    }
    private var content: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(row.title).yubaiFont(YubaiFont.rowTitle)
                Text(FixedFlowPresentation.detail(row, in: store.current)).yubaiFont(YubaiFont.caption)
                    .foregroundStyle(row.state == .due && row.overdueDays() > 0 ? YubaiColor.amberInk : YubaiColor.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: YubaiSpace.none) {
                if row.estimated { Text("~").yubaiFont(YubaiFont.amount) }
                AmountLabel(cents: row.amount, hide: store.current.preferences.hideAmounts, sign: row.inflow ? .inflow : .none, ink: row.state == .paid ? YubaiColor.labelSecondary : row.inflow ? YubaiColor.brandInk : YubaiColor.label)
            }.foregroundStyle(row.state == .paid ? YubaiColor.labelSecondary : row.inflow ? YubaiColor.brandInk : YubaiColor.label).fixedSize(horizontal: true, vertical: false)
            if let id = row.planID, row.state != .upcoming {
                FixedFlowCheck(planID: id, occurrence: row.date, title: row.title, amount: row.amount, inflow: row.inflow, state: row.state)
            } else if row.state == .paid { FixedFlowPaidMark(inflow: row.inflow, title: row.title) }
            else { Color.clear.frame(width: YubaiSize.rowIcon).accessibilityHidden(true) }
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble)
            .opacity(row.state == .paid ? 0.7 : 1).background(YubaiColor.card)
            .animation(YubaiMotion.control(reduceMotion: reduceMotion), value: row.state)
    }
    private func reset() {
        #if os(macOS)
        horizontal = nil
        #endif
        withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { offset = resting }
    }
    private func stop() { resting = 0; reset(); confirmingStop = true }
}

private struct FixedFlowPaidMark: View {
    let inflow: Bool
    let title: String
    var body: some View {
        Image(systemName: "checkmark").yubaiFont(YubaiFont.row, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
            .frame(width: YubaiSize.rowIcon, height: YubaiSize.rowIcon).background(YubaiColor.neutralSoft, in: Circle())
            .accessibilityLabel((inflow ? "已收到 " : "已付 ") + title)
    }
}

struct FixedFlowCheck: View {
    @Environment(AppStore.self) private var store
    @State private var editing = false
    @State private var editedAmount = ""
    @FocusState private var amountFocused: Bool
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
                    .highPriorityGesture(LongPressGesture(minimumDuration: YubaiMotion.durationDismiss).onEnded { _ in edit() })
                    .accessibilityAction(named: "改金额再记", edit)
            }
        }
            .sheet(isPresented: $editing) {
                NavigationStack {
                    Page(topPadding: YubaiSpace.gapGroup) {
                        ManualSheetHeader(title: title + " · 这期金额", actionTitle: "记下", enabled: (try? Money.parse(editedAmount)).map { $0 > 0 } ?? false,
                                          cancel: { editing = false }, action: { if let amount = try? Money.parse(editedAmount), settle(amount) { editing = false } })
                        TextField("金额", text: $editedAmount).numericInput().yubaiFont(YubaiFont.amountDisplay)
                            .focused($amountFocused).accessibilityIdentifier("fixedFlowSettlementAmount")
                    }
                        #if os(iOS)
                        .toolbar(.hidden, for: .navigationBar)
                        #endif
                        .onAppear { amountFocused = true }
                }.environment(store).appErrors().presentationDragIndicator(.visible)
                    #if os(iOS)
                    .presentationDetents([.medium])
                    #endif
            }
    }
    private func edit() { guard state != .paid else { return }; editedAmount = Money.input(amount); editing = true }
    @discardableResult private func settle(_ override: Int64? = nil) -> Bool {
        Self.record(planID: planID, occurrence: occurrence, title: title, amount: override ?? amount, inflow: inflow, store: store, override: override)
    }
    @MainActor @discardableResult static func record(planID: UUID, occurrence: Date, title: String, amount: Int64, inflow: Bool, store: AppStore, override: Int64? = nil) -> Bool {
        do {
            let change = try FixedFlows.settle(planID: planID, occurrence: occurrence, amount: override, in: store.current)
            guard store.apply(change, label: (inflow ? "收到了 " : "付了 ") + title) else { return false }
            store.cancelEntrySaveMotion(); store.fixedFlowSettleTrigger &+= 1
            let value = store.current.preferences.hideAmounts ? "••••" : AmountLabel.text(amount)
            store.toast = title + " " + value + " 已记下"
            return true
        } catch { store.error = error.localizedDescription; return false }
    }
}

struct FixedFlowEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inflow = false
    @State private var amount = ""
    @State private var title = ""
    @State private var frequency = Frequency.monthly
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var installments: Int?
    @State private var autoPay = false
    @State private var estimated = false
    @State private var pickingSchedule = false
    @State private var balances: [UUID: Int64] = [:]
    private var accounts: [Account] { store.current.accounts.filter { !$0.archived } }
    private var hasAccount: Bool { accounts.contains { $0.id == accountID } }
    private var plan: Plan? {
        guard let cents = try? Money.parse(amount), cents > 0 else { return nil }
        var plan = Plan(title: title.trimmingCharacters(in: .whitespacesAndNewlines), amount: cents, dueDate: Dates.day(date),
                        frequency: frequency, inflow: inflow, category: inflow ? "其他收入" : "其他支出", nature: inflow ? .income : .expense)
        plan.accountID = hasAccount ? accountID : nil; plan.installments = frequency == .once ? nil : installments
        plan.autoPay = autoPay && hasAccount; plan.autoPaySince = plan.autoPay ? Dates.day(Date()) : nil; plan.estimated = estimated
        return plan
    }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            ManualSheetHeader(title: "添加", actionTitle: "好", enabled: plan != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              cancel: { dismiss() }, action: save)
            Segmented(choices: [(false, "要付"), (true, "要收")], selection: $inflow)
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                TextField("0", text: $amount).numericInput().yubaiFont(YubaiFont.amountDisplay).accessibilityLabel("金额")
            }.frame(minHeight: YubaiSize.rowDouble)
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    EntryFormRow(title: "名字") { TextField("", text: $title).multilineTextAlignment(.trailing).accessibilityLabel("名字") }.frame(minHeight: YubaiSize.rowSingle)
                    EntryFormDivider()
                    EntryFormRow(title: frequency == .monthly ? "每月几号" : "多久一次") {
                        Button(FixedFlowArrangement.schedule(frequency, date: date).replacingOccurrences(of: " 日", with: " 号")) { pickingSchedule = true }
                            .manualFormChip().accessibilityIdentifier("fixedFlowSchedule")
                    }.frame(minHeight: YubaiSize.rowSingle)
                    EntryFormDivider()
                    EntryFormRow(title: inflow ? "收到哪里" : "从哪里付") {
                        EntryAccountMenu(accounts: accounts, balances: balances, selection: $accountID, optional: true, emptyTitle: "选账户后可自动记")
                    }.frame(minHeight: YubaiSize.rowSingle)
                    EntryFormDivider()
                    EntryFormRow(title: "共几期") {
                        Menu {
                            Button("一直") { installments = nil }
                            ForEach(2...60, id: \.self) { count in Button("\(count) 期") { installments = count } }
                        } label: { Text(installments.map { "\($0) 期" } ?? "一直") }.manualFormChip()
                            .disabled(frequency == .once).accessibilityIdentifier("fixedFlowInstallments")
                    }.frame(minHeight: YubaiSize.rowSingle)
                }
            }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    Toggle("到日子自动记", isOn: $autoPay).disabled(!hasAccount).accessibilityIdentifier("fixedFlowAutoPay").frame(minHeight: YubaiSize.rowSingle)
                    EntryFormDivider()
                    Toggle("金额会变", isOn: $estimated).accessibilityIdentifier("fixedFlowEstimated").frame(minHeight: YubaiSize.rowSingle)
                }.yubaiFont(YubaiFont.row).tint(YubaiColor.toggleOn)
            }
            preview
        }
            #if os(iOS)
            .presentationDetents([.large])
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear { balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) }) }
            .onChange(of: accountID) { _, _ in if !hasAccount { autoPay = false } }
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
    private var preview: some View {
        let count = frequency == .once ? 1 : min(4, installments ?? 4)
        return HStack(spacing: YubaiSpace.gapGroup) {
            ForEach(0..<count, id: \.self) { index in
                let day = frequency.advance(Dates.day(date), by: index)
                VStack(spacing: YubaiSpace.space4) {
                    FixedFlowDot(state: Dates.day(day) <= Dates.day(Date()) ? .due : .upcoming)
                    Text(FixedFlowPresentation.monthDay(day)).yubaiFont(YubaiFont.chartLabel).foregroundStyle(YubaiColor.labelSecondary)
                }.frame(maxWidth: .infinity)
            }
        }.padding(.top, YubaiSpace.space4).accessibilityElement(children: .ignore)
            .accessibilityLabel("接下来\(count)期：" + (0..<count).map { FixedFlowPresentation.monthDay(frequency.advance(Dates.day(date), by: $0)) }.joined(separator: "、"))
    }
    private func save() {
        guard let plan, !plan.title.isEmpty else { return }
        let change = ChangeSet(source: "用户操作", reason: "添加安排「\(plan.title)」", items: [.addPlan(plan)])
        if store.apply(change, label: "添加安排") { dismiss() }
    }
}

private extension View {
    func manualFormChip() -> some View {
        self.yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
            .background(YubaiColor.raised, in: Capsule()).yubaiHitTarget().buttonStyle(PressButtonStyle())
    }
}
