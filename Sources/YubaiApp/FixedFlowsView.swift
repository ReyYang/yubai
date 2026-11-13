import SwiftUI
import YubaiCore

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

/// The calendar menu and detail page share the stop confirmation.
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
        content.sheet(isPresented: $isPresented) {
            ConfirmationSheet(title: "停掉「\(title)」", consequence: message, cancelIdentifier: "fixedFlowStopCancel") {
                if pending.isEmpty {
                    Button("停掉") { performStop() }.buttonStyle(DestructiveButtonStyle())
                        .accessibilityIdentifier("fixedFlowStopConfirm").accessibilityHint("只停以后的，已到期账单和付过的记录保留")
                } else {
                    Button(inflow ? "这期收到了，记一笔再停" : "这期付了，记一笔再停") { performStop(.settle) }.buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("fixedFlowStopConfirm")
                    Button(inflow ? "这期没收到，直接停" : "这期没付，直接停") { performStop(.skip) }.buttonStyle(DestructiveButtonStyle())
                        .accessibilityIdentifier("fixedFlowStopSkip")
                }
            }.environment(store)
        }
    }
    private func performStop(_ resolution: FixedFlowStopResolution? = nil) {
        guard let planID else { return }
        do {
            let change = try FixedFlows.stop(planID: planID, resolution: resolution, in: store.current)
            if store.apply(change, label: "停掉安排") {
                store.cancelEntrySaveMotion(); store.toast = "已停掉"; isPresented = false; onStopped()
            }
        } catch { store.error = error.localizedDescription }
    }
}

enum FixedFlowCheck {
    @MainActor @discardableResult static func record(planID: UUID, occurrence: Date, title: String, amount: Int64, inflow: Bool, store: AppStore, override: Int64? = nil) -> Bool {
        do {
            let now = Date()
            let label = (inflow ? "收到了 " : "付了 ") + title
            if var pending = store.current.activeEntries.first(where: { $0.planID == planID && $0.occurrence.map(Dates.day) == Dates.day(occurrence) && $0.date > now }) {
                pending.date = now; pending.amount = override ?? pending.amount
                guard store.update(label, {
                    try ManualBookkeeping.edit(pending, in: &$0, now: now)
                    try FixedFlows.confirmRecordedPayment(planID: planID, occurrence: occurrence, in: &$0, now: now)
                }) else { return false }
            } else {
                let change = try FixedFlows.confirmPayment(planID: planID, occurrence: occurrence, amount: override, in: store.current, now: now)
                guard store.apply(change, label: label) else { return false }
            }
            store.cancelEntrySaveMotion(); store.fixedFlowSettleTrigger &+= 1
            store.toast = "已记下 1 笔"
            return true
        } catch { store.error = error.localizedDescription; return false }
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
        if let amount = store.formula.bills.first(where: { $0.planID == planID && Dates.day($0.date) == day && $0.state != .paid })?.amount { return amount }
        return YearlyBillReserves.rows(in: store.current, now: store.financialNow).first { $0.id == planID && Dates.day($0.due) == day }?.reserved ?? 0
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
                                               intoFixedSavings: edit.intoFixedSavings, currency: edit.currency, monthlyDay: edit.monthlyDay)
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
        let amount = FixedFlows.expectedAmount(planID: planID, in: store.current, now: store.financialNow) ?? plan?.amount ?? 0
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
        if store.update("改到别的日子", entryMotion: false, showToast: false, { ledger in
            try FixedFlows.moveOccurrence(planID: planID, occurrence: occurrence, to: date, in: &ledger, now: Date())
        }) { store.toast = "已改到 " + FixedFlowPresentation.monthDay(date); dismiss() }
    }
    private func clear() {
        let planID = planID, occurrence = occurrence
        let date = original ?? occurrence
        if store.update("改到别的日子", entryMotion: false, showToast: false, { ledger in
            try FixedFlows.clearOccurrenceMove(planID: planID, occurrence: occurrence, in: &ledger, now: Date())
        }) { store.toast = "已改到 " + FixedFlowPresentation.monthDay(date); dismiss() }
    }
}

private struct BillRowMenuModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var confirmingStop = false
    let planID: UUID
    let occurrence: Date
    var enabled = true
    func body(content: Content) -> some View {
        let plan = store.plans.first { $0.id == planID }
        content.contextMenu { if enabled { BillRowMenu(planID: planID, occurrence: occurrence, stop: { confirmingStop = true }) } }
            .modifier(FixedFlowStopConfirmation(planID: planID, title: plan?.title ?? "", inflow: plan?.inflow ?? false, isPresented: $confirmingStop))
    }
}

extension View {
    /// 长按出 `BillRowMenu`；停掉要确认。
    func billRowMenu(planID: UUID, occurrence: Date, enabled: Bool = true) -> some View {
        modifier(BillRowMenuModifier(planID: planID, occurrence: occurrence, enabled: enabled))
    }
}

/// 账单弹窗的标题行：名字、一个小数、取消。
private struct BillSheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String? = nil
    var body: some View { AmountSheetHeader(title: title, subtitle: subtitle, cancel: { dismiss() }) }
}

/// 账本里的一笔：品牌／分类图标、名字、日期·账户·来源、金额。
private struct BillEntryRow: View {
    @Environment(AppStore.self) private var store
    let entry: Entry
    var body: some View {
        let outflow = entry.nature == .expense
        let detail = FixedFlowPresentation.monthDay(entry.date) + " · " + store.accountName(entry.accountID) + (entry.batchID != nil ? " · 导入" : "")
        ViewThatFits(in: .horizontal) {
            entryContent(detail: detail, outflow: outflow, vertical: false)
            entryContent(detail: detail, outflow: outflow, vertical: true)
        }
    }
    private func entryContent(detail: String, outflow: Bool, vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return layout {
            BillBrandIcon(title: entry.displayTitle, category: entry.category, inflow: entry.nature.inflow, size: YubaiSize.rowIcon + YubaiSpace.space4)
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(entry.displayTitle).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).lineLimit(1)
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
        let available = FixedFlows.availableAfterPayment(planID: plan.id, occurrence: occurrence, amount: amount, in: store.current, now: store.financialNow) ?? store.funds.available
        if diff == 0 { return [AmountSheetRow(label: "还能花", value: amount2(available, hide: hide))] }
        let label = (diff > 0 ? "比留出的少 " : "比留出的多 ") + amount2(abs(diff), hide: hide)
        return [AmountSheetRow(label: label, value: "还能花 " + amount2(available, hide: hide), amber: diff < 0)]
    }

    var body: some View {
        AmountEntrySheet(title: plan.title, subtitle: "上次 " + amount2(expected, hide: store.preferences.hideAmounts),
                         keypad: $keypad, rows: rows, primaryTitle: plan.inflow ? "收到了" : "付了", canSave: valid, save: save)
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
        let preview = FixedFlows.availableAfterPayment(planID: plan.id, occurrence: occurrence, amount: entry.amount, matchedEntryID: entry.id, in: store.current, now: store.financialNow) ?? store.funds.available
        let available = amount2(preview, hide: hide)
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
                    EmptyState("list.bullet", "没有可选的账", action: "记一笔", onAction: { store.requestCaptureSheet(.addEntry) })
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
                MonthDayChoices(selection: .constant(current), identifier: "billDay_") { value in pick(value); dismiss() }
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
    @State private var editingDay = false
    @State private var confirmingStop = false
    private var plan: Plan? { store.plans.first { $0.id == planID } }

    var body: some View {
        Group {
            if let plan { content(plan) } else { Color.clear.onAppear { dismiss() } }
        }.navigationTitle(plan?.title ?? "").yubaiNavigation()
            .task(id: "\(store.ledgerRevision)-\(store.financialNow)") { await refreshHistory() }
    }

    private func content(_ plan: Plan) -> some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            if plan.title.count > 12 { Text(plan.title).yubaiFont(YubaiFont.cardTitle).fixedSize(horizontal: false, vertical: true) }
            settingsCard(plan)
            if let history, !history.entries.isEmpty { historyBlock(plan, history) }
            if plan.active && plan.endDate == nil && plan.stoppedAt == nil { stopButton }
        }.amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("billDetailPage")
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
        Rectangle().fill(YubaiColor.separator).frame(height: YubaiSize.separator).accessibilityHidden(true)
    }
    private func detailRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        EntryFormRow(title: title, content: value).frame(minHeight: YubaiSize.rowDouble)
    }
    private func amountRow(_ plan: Plan) -> some View {
        let value = amount2(expected(plan), hide: store.preferences.hideAmounts)
        let text = plan.currency != .cny ? plan.currency.amountText(plan.amount, hidden: store.preferences.hideAmounts) + " · 约 ¥" + value : (plan.estimated ? "每月不一样 · 约 " + value : value)
        return Button {
            store.sheetSource = nil; store.sheet = .editPlan(plan.id)
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
        parts.day = 1
        guard let month = calendar.date(from: parts) else { return }
        let last = calendar.range(of: .day, in: .month, for: month)!.count
        let date = Dates.addDays(min(day, last) - 1, to: month)
        BillEditing.change(planID: planID, store: store, label: plan?.title ?? "") { $0.date = Dates.day(date); $0.monthlyDay = day }
    }
}
