import SwiftUI
import YubaiCore

struct FixedFlowsView: View {
    @Environment(AppStore.self) private var store
    @State private var ending: FixedFlowOccurrence?
    var body: some View {
        let ledger = store.current
        let month = store.fixedFlowMonth
        Page(spacing: 14, topPadding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Dates.calendar.component(.month, from: month.date))月还要付").yubaiFont(YubaiFont.heroLabel)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text("要收").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        AmountLabel(cents: month.remainingInflow, hide: ledger.preferences.hideAmounts, role: .small, sign: .inflow,
                                    fractionDigits: month.remainingInflow % 100 == 0 ? 0 : 2, ink: YubaiColor.brandInk)
                    }
                }
                AmountLabel(cents: month.remainingOutflow, hide: ledger.preferences.hideAmounts, role: .display,
                            fractionDigits: month.remainingOutflow % 100 == 0 ? 0 : 2).accessibilityIdentifier("fixedFlowRemaining")
            }
            calendar(month)
            if month.occurrences.isEmpty {
                Text("这个月还没有固定收付").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            }
            bills(month.occurrences.filter { !$0.inflow })
            let income = month.occurrences.filter(\.inflow)
            if !income.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("要收").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.leading, 4)
                    bills(income)
                }
            }
        }.amountPrivacy(ledger.preferences.hideAmounts).navigationTitle("固定收付").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .primaryAction) {
                Button { store.sheetSource = nil; store.sheet = .addPlan } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加安排").accessibilityIdentifier("addFixedFlow")
            } }
            .confirmationDialog("停掉「\(ending?.title ?? "这个安排")」？", isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }), titleVisibility: .visible) {
                Button("停掉") {
                    if let ending, let id = ending.planID {
                        let change = ChangeSet(source: "用户操作", reason: "从今天起停掉「\(ending.title)」", items: [.endPlan(id, Date())])
                        store.apply(change, label: "停掉安排")
                    }
                    ending = nil
                }
                Button("取消", role: .cancel) { ending = nil }
            } message: { Text("只停以后的，已到期账单和付过的记录保留。") }
    }
    @ViewBuilder private func bills(_ rows: [FixedFlowOccurrence]) -> some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    FixedFlowBillRow(row: row, ending: { ending = row })
                    if row.id != rows.last?.id { EntryFormDivider().padding(.horizontal, 16) }
                }
            }.background(YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.card))
                .clipShape(RoundedRectangle(cornerRadius: YubaiRadius.card))
        }
    }
    private func calendar(_ month: FixedFlowMonth) -> some View {
        let groups = Dictionary(grouping: month.occurrences) { Dates.day($0.date) }
        let days = groups.keys.sorted()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(7, max(1, days.count))), spacing: 12) {
            ForEach(days, id: \.self) { day in
                let rows = groups[day] ?? []
                let row = rows.first { $0.state == .due && !$0.inflow } ?? rows.first { $0.state != .paid } ?? rows[0]
                VStack(spacing: 4) {
                    FixedFlowDot(state: row.state, inflow: row.inflow)
                    Text("\(Dates.calendar.component(.day, from: day))").yubaiFont(YubaiFont.chartValue).foregroundStyle(YubaiColor.labelSecondary)
                }.accessibilityElement(children: .ignore)
                    .accessibilityLabel(FixedFlowPresentation.monthDay(day) + "，" + rows.map { $0.title + " " + FixedFlowPresentation.state($0.state, inflow: $0.inflow) }.joined(separator: "，"))
            }
        }
    }
}

enum FixedFlowPresentation {
    static func monthDay(_ date: Date) -> String { date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN"))) }
    static func state(_ state: FixedFlowState, inflow: Bool) -> String {
        switch state { case .paid: inflow ? "已收到" : "已付"; case .due: "已到期"; case .upcoming: "还没到" }
    }
    static func detail(_ row: FixedFlowOccurrence, in ledger: Ledger) -> String {
        var parts = [Dates.day(row.date) == Dates.day(Date()) ? "今天" : "\(Dates.calendar.component(.day, from: row.date))日"]
        let account = ledger.plans.first { $0.id == row.planID }?.accountID ?? ledger.rents.first { $0.id == row.rentID }?.accountID
        if let account { parts.append(ledger.accountName(account)) }
        if row.autoPay { parts.append("自动") }
        if let installment = row.installment { parts.append("\(installment.index)/\(installment.total) 期") }
        if row.estimated { parts.append("大约") }
        if row.state == .paid { parts.append("已记") }
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
    @GestureState private var dragging = false
    @State private var horizontal: Bool?
    @State private var offset: CGFloat = 0
    @State private var resting: CGFloat = 0
    let row: FixedFlowOccurrence
    let ending: () -> Void
    private var canEnd: Bool { store.current.plans.contains { $0.id == row.planID && $0.active && $0.endDate == nil } }
    var body: some View {
        Group {
            if canEnd {
                content.offset(x: offset).background(alignment: .trailing) {
                    Button("停掉", action: stop).yubaiFont(YubaiFont.callout, weight: .medium)
                        .frame(width: 84).frame(maxHeight: .infinity).background(YubaiColor.neutralStrong)
                        .opacity(offset < 0 ? 1 : 0).allowsHitTesting(offset < 0).accessibilityHidden(offset == 0)
                }.clipped().contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 18)
                        .updating($dragging) { _, state, _ in state = true }
                        .onChanged { value in
                            if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.3 }
                            guard horizontal == true else { return }
                            offset = max(-84, min(0, resting + value.translation.width))
                        }.onEnded { _ in
                            guard horizontal == true else { return }
                            resting = offset < -36 ? -84 : 0; reset()
                        })
                    .onChange(of: dragging) { _, active in if !active { reset() } }
                    .onChange(of: canEnd) { _, value in if !value { resting = 0; reset() } }
                    .accessibilityAction(named: "停掉", stop)
            } else { content }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("fixedFlow_" + row.id)
            .accessibilityValue(FixedFlowPresentation.state(row.state, inflow: row.inflow))
    }
    private var content: some View {
        HStack(spacing: 12) {
            FixedFlowDot(state: row.state, inflow: row.inflow)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).yubaiFont(YubaiFont.rowTitle)
                Text(FixedFlowPresentation.detail(row, in: store.current)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                if row.estimated { Text("~").yubaiFont(YubaiFont.amount) }
                AmountLabel(cents: row.amount, hide: store.current.preferences.hideAmounts, sign: row.inflow ? .inflow : .none,
                            fractionDigits: row.amount % 100 == 0 ? 0 : 2, ink: row.inflow ? YubaiColor.brandInk : YubaiColor.label)
            }.foregroundStyle(row.inflow ? YubaiColor.brandInk : YubaiColor.label).fixedSize(horizontal: true, vertical: false)
            if let id = row.planID {
                FixedFlowCheck(planID: id, occurrence: row.date, title: row.title, amount: row.amount, inflow: row.inflow, state: row.state)
            }
        }.padding(.horizontal, 16).padding(.vertical, 6).frame(minHeight: 60)
            .opacity(row.state == .paid ? 0.6 : 1).background(YubaiColor.card)
            .animation(YubaiMotion.control(reduceMotion: reduceMotion), value: row.state)
    }
    private func reset() { horizontal = nil; withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { offset = resting } }
    private func stop() { resting = 0; reset(); ending() }
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
    private var filled: Bool { state == .due && !inflow }
    var body: some View {
        Button { settle() } label: {
            Image(systemName: "checkmark").yubaiFont(YubaiFont.row, weight: .semibold)
                .foregroundStyle(state == .paid || inflow ? YubaiColor.brandInk : filled ? YubaiColor.onBrand : YubaiColor.labelSecondary)
                .frame(width: 40, height: 40)
                .background(state == .paid ? YubaiColor.brandTint : filled ? YubaiColor.amberDot : YubaiColor.card.opacity(0), in: Circle())
                .overlay { if state == .upcoming || (inflow && state != .paid) { Circle().strokeBorder(inflow ? YubaiColor.brand : YubaiColor.neutralStrong, lineWidth: 1.5) } }
                .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
        }.buttonStyle(PressButtonStyle()).disabled(state == .paid).accessibilityLabel(label)
            .accessibilityValue(FixedFlowPresentation.state(state, inflow: inflow))
            .accessibilityIdentifier("settleFixedFlow_" + planID.uuidString + "_" + Dates.text(occurrence))
            .highPriorityGesture(LongPressGesture(minimumDuration: YubaiMotion.durationDismiss).onEnded { _ in edit() })
            .accessibilityAction(named: "改金额再记", edit)
            .sheet(isPresented: $editing) {
                NavigationStack {
                    Page(topPadding: 12) {
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
        do {
            let change = try FixedFlows.settle(planID: planID, occurrence: occurrence, amount: override, in: store.current)
            guard store.apply(change, label: label) else { return false }
            store.cancelEntrySaveMotion(); store.fixedFlowSettleTrigger &+= 1
            let cents = override ?? amount
            let value = store.current.preferences.hideAmounts ? "••••" : AmountLabel.text(cents, decimals: cents % 100 == 0 ? 0 : 2)
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
        Page(spacing: 12, topPadding: 12) {
            ManualSheetHeader(title: "添加", actionTitle: "好", enabled: plan != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              cancel: { dismiss() }, action: save)
            Segmented(choices: [(false, "要付"), (true, "要收")], selection: $inflow)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                TextField("0", text: $amount).numericInput().yubaiFont(YubaiFont.amountDisplay).accessibilityLabel("金额")
            }.frame(minHeight: 60).padding(.horizontal, 4)
            Card(style: .list) {
                VStack(spacing: 0) {
                    EntryFormRow(title: "名字") { TextField("", text: $title).multilineTextAlignment(.trailing).accessibilityLabel("名字") }.frame(minHeight: 52)
                    EntryFormDivider()
                    EntryFormRow(title: frequency == .monthly ? "每月几号" : "多久一次") {
                        Button(FixedFlowArrangement.schedule(frequency, date: date).replacingOccurrences(of: " 日", with: " 号")) { pickingSchedule = true }
                            .manualFormChip().accessibilityIdentifier("fixedFlowSchedule")
                    }.frame(minHeight: 52)
                    EntryFormDivider()
                    EntryFormRow(title: inflow ? "收到哪里" : "从哪里付") {
                        EntryAccountMenu(accounts: accounts, balances: balances, selection: $accountID, optional: true, emptyTitle: "选账户后可自动记")
                    }.frame(minHeight: 52)
                    EntryFormDivider()
                    EntryFormRow(title: "共几期") {
                        Menu {
                            Button("一直") { installments = nil }
                            ForEach(2...60, id: \.self) { count in Button("\(count) 期") { installments = count } }
                        } label: { Text(installments.map { "\($0) 期" } ?? "一直") }.manualFormChip()
                            .disabled(frequency == .once).accessibilityIdentifier("fixedFlowInstallments")
                    }.frame(minHeight: 52)
                }
            }
            Card(style: .list) {
                VStack(spacing: 0) {
                    Toggle("到日子自动记", isOn: $autoPay).disabled(!hasAccount).accessibilityIdentifier("fixedFlowAutoPay").frame(minHeight: 52)
                    EntryFormDivider()
                    Toggle("金额会变", isOn: $estimated).accessibilityIdentifier("fixedFlowEstimated").frame(minHeight: 52)
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
                VStack(spacing: 12) {
                    Picker("多久一次", selection: $frequency) { ForEach(Frequency.allCases) { Text($0.label).tag($0) } }.frame(width: 320)
                    DatePicker("第一次", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).frame(width: 320, height: 360).fixedSize()
                    Button("完成") { pickingSchedule = false }.frame(minHeight: 44)
                }.padding(18).frame(minWidth: 300).transaction { $0.animation = nil }
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
    }
    private var preview: some View {
        let count = frequency == .once ? 1 : min(4, installments ?? 4)
        return HStack {
            ForEach(0..<count, id: \.self) { index in
                let day = frequency.advance(Dates.day(date), by: index)
                VStack(spacing: 4) {
                    FixedFlowDot(state: Dates.day(day) <= Dates.day(Date()) ? .due : .upcoming)
                    Text(FixedFlowPresentation.monthDay(day)).yubaiFont(YubaiFont.chartLabel).foregroundStyle(YubaiColor.labelSecondary)
                }.frame(maxWidth: .infinity)
            }
        }.padding(.top, 2).accessibilityElement(children: .ignore)
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
        self.yubaiFont(YubaiFont.callout).padding(.horizontal, 12).frame(minHeight: YubaiSize.chipHeight)
            .background(YubaiColor.raised, in: Capsule()).buttonStyle(PressButtonStyle())
    }
}
