import SwiftUI
import YubaiCore

struct FixedFlowsView: View {
    @Environment(AppStore.self) private var store
    @State private var ending: FixedFlowArrangement?
    var body: some View {
        let ledger = store.current
        let occurrences = FixedFlows.occurrences(in: ledger)
        let outflow = occurrences.filter { !$0.inflow }.reduce(Int64(0)) { $0 + $1.amount }
        let inflow = occurrences.filter(\.inflow).reduce(Int64(0)) { $0 + $1.amount }
        let rows = FixedFlowArrangement.rows(in: ledger)
        Page(spacing: YubaiSpace.space12) {
            Text("接下来 90 天要付").yubaiFont(YubaiFont.heroLabel)
            AmountLabel(cents: outflow, hide: ledger.preferences.hideAmounts, role: .display)
            HStack(spacing: 4) {
                Text("要收").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: inflow, hide: ledger.preferences.hideAmounts, role: .small, sign: .inflow, fractionDigits: inflow % 100 == 0 ? 0 : 2)
            }
            CardRows(rows) { row in
                Menu {
                    if row.canEnd { Button("结束这个安排", role: .destructive) { ending = row } }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).yubaiFont(YubaiFont.rowTitle)
                            Text(row.detail).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        }
                        Spacer(minLength: 6)
                        AmountLabel(cents: row.amount, hide: ledger.preferences.hideAmounts, sign: row.inflow ? .inflow : .outflow)
                    }.frame(minHeight: 54).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("fixedFlow_" + row.id.uuidString)
            }
        }.amountPrivacy(ledger.preferences.hideAmounts).navigationTitle("固定收付").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .primaryAction) {
                Button { store.sheetSource = nil; store.sheet = .addPlan } label: {
                    Image(systemName: "plus").frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton).floatingSurface(in: Circle())
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("添加安排").accessibilityIdentifier("addFixedFlow")
            } }
            .confirmationDialog("结束「\(ending?.title ?? "这个安排")」？", isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } }), titleVisibility: .visible) {
                Button("结束这个安排", role: .destructive) {
                    if let ending {
                        let change = ChangeSet(source: "用户操作", reason: "从现在起结束「\(ending.title)」", items: [.endPlan(ending.id, Date())])
                        store.apply(change, label: "结束安排")
                    }
                    ending = nil
                }
                Button("取消", role: .cancel) { ending = nil }
            }
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
    @State private var endDate: Date?
    @State private var pickingSchedule = false
    @State private var pickingEnd = false
    @State private var balances: [UUID: Int64] = [:]
    private var accounts: [Account] { store.current.accounts.filter { !$0.archived } }
    private var plan: Plan? {
        guard let cents = try? Money.parse(amount), cents > 0, endDate.map({ Dates.day($0) >= Dates.day(date) }) ?? true else { return nil }
        var plan = Plan(title: title.trimmingCharacters(in: .whitespacesAndNewlines), amount: cents, dueDate: Dates.day(date),
                        frequency: frequency, inflow: inflow, category: inflow ? "其他收入" : "其他支出", nature: inflow ? .income : .expense)
        plan.accountID = accountID; plan.endDate = endDate.map(Dates.day); return plan
    }
    var body: some View {
        Page(spacing: 12, topPadding: 12) {
            ManualSheetHeader(title: "添加安排", enabled: plan != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              cancel: { dismiss() }, action: save)
            Segmented(choices: [(false, "要付"), (true, "要收")], selection: $inflow)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                TextField("0", text: $amount).numericInput().yubaiFont(YubaiFont.amountDisplay).accessibilityLabel("金额")
            }.frame(minHeight: 60).padding(.horizontal, 4)
            Card(style: .list) {
                VStack(spacing: 0) {
                    EntryFormRow(title: "名字") { TextField("", text: $title).multilineTextAlignment(.trailing).accessibilityLabel("名字") }
                    EntryFormDivider()
                    EntryFormRow(title: "多久一次") {
                        Button(FixedFlowArrangement.schedule(frequency, date: date)) { pickingSchedule = true }.manualFormChip()
                    }
                    EntryFormDivider()
                    EntryFormRow(title: inflow ? "收到哪里" : "从哪里付") {
                        EntryAccountMenu(accounts: accounts, balances: balances, selection: $accountID, optional: true)
                    }
                    EntryFormDivider()
                    EntryFormRow(title: "到什么时候") {
                        Button(endDate.map { ManualBookkeeping.dayLabel($0) } ?? "一直") { pickingEnd = true }.manualFormChip()
                    }
                }
            }
            preview
        }
            #if os(iOS)
            .presentationDetents([.large])
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear { balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) }) }
            .popover(isPresented: $pickingSchedule) {
                VStack(spacing: 12) {
                    Picker("多久一次", selection: $frequency) { ForEach(Frequency.allCases) { Text($0.label).tag($0) } }
                    DatePicker("第一次", selection: $date, displayedComponents: .date).datePickerStyle(.graphical)
                    Button("完成") { pickingSchedule = false }.frame(minHeight: 44)
                }.padding(18).frame(minWidth: 300)
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
            .popover(isPresented: $pickingEnd) {
                VStack(spacing: 12) {
                    Toggle("一直", isOn: Binding(get: { endDate == nil }, set: { endDate = $0 ? nil : max(date, Date()) })).tint(YubaiColor.toggleOn)
                    if endDate != nil {
                        DatePicker("结束日期", selection: Binding(get: { endDate ?? date }, set: { endDate = $0 }), in: Dates.day(date)..., displayedComponents: .date).datePickerStyle(.graphical)
                    }
                    Button("完成") { pickingEnd = false }.frame(minHeight: 44)
                }.padding(18).frame(minWidth: 300)
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
            .onChange(of: date) { _, value in if let endDate, endDate < value { self.endDate = value } }
    }
    private var preview: some View {
        let plan = plan
        let rows = plan.map { plan in FixedFlows.occurrences(in: store.current, adding: plan).filter { $0.planID == plan.id } } ?? []
        let total = rows.reduce(Int64(0)) { $0 + $1.amount }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("90 天里会先留出").yubaiFont(YubaiFont.rowTitle); Spacer()
                    AmountLabel(cents: total, hide: store.current.preferences.hideAmounts, role: .amount, fractionDigits: total % 100 == 0 ? 0 : 2)
                }
                if !rows.isEmpty {
                    HStack {
                        ForEach(Array(rows.prefix(4))) { row in
                            VStack(spacing: 6) {
                                Circle().fill(YubaiColor.brand).frame(width: 8, height: 8)
                                Text(row.date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN")))).yubaiFont(YubaiFont.chartLabel)
                                    .foregroundStyle(YubaiColor.labelSecondary)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
    private func save() {
        guard let plan, !plan.title.isEmpty else { return }
        let change = ChangeSet(source: "用户操作", reason: "添加安排「\(plan.title)」", items: [.addPlan(plan)])
        if store.apply(change, label: "添加安排") { dismiss() }
    }
}

private extension View {
    func manualFormChip() -> some View {
        self.yubaiFont(YubaiFont.callout).padding(.horizontal, 12).frame(minHeight: 30)
            .background(YubaiColor.raised, in: Capsule()).buttonStyle(PressButtonStyle())
    }
}
