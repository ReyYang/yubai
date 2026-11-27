import SwiftUI
import YubaiCore

/// A route adapter for surfaces that already own a navigation link to a bill.
struct BillDetailRoute: View {
    let entryID: UUID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DS.Color.bg.ignoresSafeArea()
            .overlay {
                if let entry = store.current.entries.first(where: { $0.id == entryID }) {
                    BillFloatingCardOverlay(entry: entry, onClose: { dismiss() })
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
}

struct BillFloatingCardOverlay: View {
    let entry: Entry
    let onClose: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var shown = false
    @State private var closing = false

    var body: some View {
        ZStack {
            DS.Color.scrim.ignoresSafeArea().opacity(shown ? 1 : 0)
                .onTapGesture { close() }.accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                bill.fixedSize(horizontal: false, vertical: true)
                    .modifier(BillDragPosition(reduced: reduced, enabled: shown && !closing, close: { close() }))
                ScrollView { bill }.scrollBounceBehavior(.basedOnSize)
            }
            .padding(DS.Space.s16)
            .scaleEffect(shown || reduced ? 1 : DSMotion.Role.floatCard.initialScale)
            .opacity(shown ? 1 : 0)
        }.accessibilityAddTraits(.isModal).accessibilityAction(.escape) { close() }
            .onAppear {
                withAnimation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.bouncyAnimation) { shown = true }
            }
    }

    private var bill: some View {
        BillCardContent(entry: entry, ledger: store.current, now: store.financialNow,
                        menuInitiallyOpen: HomeFixture.current?.showBillMenu == true,
                        close: { close() },
                        edit: { openEditor(duplicate: false, categoryOnly: false) },
                        recategorize: { openEditor(duplicate: false, categoryOnly: true) },
                        duplicate: { openEditor(duplicate: true, categoryOnly: false) },
                        delete: delete, receive: receive)
    }

    private func close(then: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        withAnimation(DSMotion.smoothAnimation, completionCriteria: .logicallyComplete) {
            shown = false
        } completion: {
            onClose()
            then?()
        }
    }

    private func openEditor(duplicate: Bool, categoryOnly: Bool) {
        close {
            if duplicate {
                store.openEntrySheet(QuickEntryPrefill(copying: entry, date: store.financialNow))
            } else {
                store.openBillEditor(entry, categoryOnly: categoryOnly)
            }
        }
    }

    private func delete() {
        if store.update("删除", { ledger in
            try EntryRecovery.delete(entry.id, from: &ledger, now: store.financialNow)
        }) { close() }
    }

    private func receive(_ person: UUID?) {
        guard let account = EntryRecovery.defaultAccount(for: entry, in: store.current, now: store.financialNow) else {
            store.error = "请先添加收款账户。"
            return
        }
        _ = store.update(person == nil ? "报销到账了" : "收到") {
            try EntryRecovery.receive(originalID: entry.id, participantID: person, into: account.id, in: &$0, now: store.financialNow)
        }
    }
}

private struct BillDragPosition: ViewModifier {
    let reduced: Bool
    let enabled: Bool
    let close: () -> Void
    @GestureState private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content.offset(y: reduced ? .zero : offset)
            .simultaneousGesture(DragGesture()
                .updating($offset) { value, offset, _ in
                    guard enabled else { return }
                    offset = value.translation.height
                }
                .onEnded { value in
                    guard enabled, abs(value.predictedEndTranslation.height) > HomeSpec.dismissalDistance else { return }
                    close()
                })
    }
}

private struct BillCardContent: View {
    let entry: Entry
    let ledger: Ledger
    let now: Date
    let menuInitiallyOpen: Bool
    let close: () -> Void
    let edit: () -> Void
    let recategorize: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    let receive: (UUID?) -> Void

    var body: some View {
        let _ = HomeRenderCounts.increment("billBody")
        let category = ledger.normalizedCategory(for: entry)
        let source = ledger.accounts.first { $0.id == entry.accountID }
        let destination = ledger.accounts.first { $0.id == entry.otherAccountID }
        let status = EntryRecovery.status(for: entry, in: ledger, now: now)
        let effect = impact(status)
        let labels = metadata(category: category, account: destination == nil ? source?.name : nil)
        let route: (DSFloatingCard.Route, DSFloatingCard.Route)? = if let source, let destination {
            (.init(title: source.name, icon: HomeDisplay.icon(source)),
             .init(title: destination.name, icon: HomeDisplay.icon(destination)))
        } else { nil }
        BillMenuCard(name: entry.displayTitle, amount: HomeDisplay.billAmount(entry, hidden: hide),
                     impact: effect, metadata: labels, note: entry.note, income: entry.nature.inflow,
                     foreign: entry.originalCurrency != nil, route: route, recovery: status.map {
                         AnyView(BillRecoveryCard(status: $0, accounts: ledger.accounts, hidden: hide, receive: receive))
                     }, canRecategorize: !entry.nature.paired && entry.relatedEntryID == nil, menuInitiallyOpen: menuInitiallyOpen,
                     close: close, edit: edit, recategorize: recategorize, duplicate: duplicate, delete: delete)
    }

    private var hide: Bool { ledger.preferences.hideAmounts }

    private func money(_ amount: Int64) -> String { HomeDisplay.money(amount, hidden: hide) }

    private func metadata(category: CategoryAssignment, account: String?) -> String {
        let label = Classification.displayCategory(category.category)
        let components = Dates.calendar.dateComponents([.hour, .minute], from: entry.date)
        let time = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        let day = ManualBookkeeping.dayLabel(entry.date, now: now)
        let monthlyDay = entry.planID.flatMap { id in
            ledger.plans.first { $0.id == id && $0.frequency == .monthly }.map {
                "每月 \($0.monthlyDay ?? Dates.calendar.component(.day, from: $0.dueDate)) 日"
            }
        }
        var parts: [String?] = [entry.nature.paired ? monthlyDay : label, category.subcategory,
                               day + ((components.hour == 0 && components.minute == 0) ? "" : " " + time), account]
        if !hide, let currency = entry.originalCurrency, let original = entry.originalAmount, original > 0 {
            let rate = Decimal(entry.amount) / Decimal(original)
            parts.append("1 \(currency.rawValue) = " + rate.formatted(.number.precision(.fractionLength(0...4))))
        }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func impact(_ status: EntryRecovery?) -> BillImpact {
        if entry.originalCurrency != nil { return BillImpact(label: "≈ " + HomeDisplay.money(entry.amount, hidden: hide, currency: true)) }
        if status?.kind == .split, let personal = entry.personalExpense {
            return BillImpact(label: "你实际承担", value: money(personal),
                              tail: status.map { $0.people.isEmpty ? "" : "· \($0.people.count + 1) 人" } ?? "")
        }
        if entry.fromReserve { return BillImpact(label: "走机动余钱 · 还剩", value: money(ledger.fixedSavingsTotal(now: now))) }
        if entry.intoFixedSavings || entry.nature == .investBuy {
            return BillImpact(label: "本期已攒", value: money(Finance.spendableBreakdown(ledger, now: now).savingSetAside))
        }
        if entry.nature.paired { return BillImpact(label: "还能花", value: "不变") }
        if let next = entry.countsFromCycleStart {
            let end = Finance.cycle(in: ledger, now: next).end
            return BillImpact(label: "算进", value: "\(BudgetPageDate.text(next)) – \(BudgetPageDate.text(end))")
        }
        if entry.nature == .expense, let budget = HomeBudgets(in: ledger, now: now).ordered.first(where: {
            $0.id == entry.partID || $0.categories.contains(ledger.normalizedCategory(for: entry).category)
        }) {
            return BillImpact(label: budget.name + (budget.over > 0 ? "超" : "还剩"),
                              value: money(budget.over > 0 ? budget.over : budget.remaining), tail: "/ " + money(budget.amount))
        }
        let available = Finance.spendableBreakdown(ledger, now: now).available
        return BillImpact(label: "还能花", value: money(available))
    }
}

private struct BillImpact {
    let label: String
    var value = ""
    var tail = ""
}

private struct BillMenuCard: View {
    let name: String
    let amount: String
    let impact: BillImpact
    let metadata: String
    let note: String
    let income: Bool
    let foreign: Bool
    let route: (DSFloatingCard.Route, DSFloatingCard.Route)?
    let recovery: AnyView?
    let canRecategorize: Bool
    let menuInitiallyOpen: Bool
    let close: () -> Void
    let edit: () -> Void
    let recategorize: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @State private var menu = false

    var body: some View {
        DSFloatingCard(name: name, amount: amount, impact: impact.label, metadata: metadata, note: note,
                       showsMenu: menu, onMore: { menu.toggle() }, onDone: close, onEdit: edit,
                       onRecategorize: recategorize, onDuplicate: duplicate, onDelete: delete,
                       amountColor: income ? DS.Color.accentInk : DS.Color.ink, effectValue: impact.value,
                       effectTail: impact.tail, foreign: foreign, route: route, recovery: recovery,
                       recategorizationEnabled: canRecategorize)
            .onAppear { menu = menuInitiallyOpen }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("billFloatingCard")
    }
}

private struct BillRecoveryCard: View {
    let status: EntryRecovery
    let accounts: [Account]
    let hidden: Bool
    let receive: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack {
                Text(title).dsText(DS.Font.tLabelStrong)
                Spacer(minLength: DS.Space.s8)
                Text(HomeDisplay.money(status.remaining, hidden: hidden)).dsText(HomeSpec.receiptAmount).fixedSize()
            }.foregroundStyle(DS.Color.warnInk)
            if status.people.isEmpty {
                if status.remaining > 0 {
                    action(status.kind == .reimbursement ? "报销到账了" : "收到", height: DS.Size.tapMin, fullWidth: true) { receive(nil) }
                        .padding(.top, DS.Space.s12)
                } else if let receipt = status.receipts.last {
                    Text(receiptLabel(receipt)).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.accentInk)
                        .padding(.top, DS.Space.s8)
                }
            } else {
                ForEach(status.people) { person in
                    if person.id != status.people.first?.id { DS.Color.warnTrack.frame(height: DS.Stroke.hairline) }
                    personRow(person)
                }.padding(.top, DS.Space.s4)
            }
        }.padding(DS.Space.s16).dsSurface(DS.Color.warnSoft, radius: DS.Radius.m)
    }

    private var title: String {
        if status.remaining == 0 { return status.kind == .split ? "已收回" : "报销到账了" }
        if status.kind == .reimbursement { return "待报销" }
        let outstanding = status.people.filter { $0.receipt == nil }.count
        if status.people.isEmpty { return "待 AA" }
        return outstanding == status.people.count ? "待收回 · \(outstanding) 人" : "还差 \(outstanding) 人"
    }

    private func receiptLabel(_ receipt: Entry) -> String {
        let account = accounts.first { $0.id == receipt.accountID }?.name
        return Dates.monthDay(receipt.date) + " 收到" + (account.map { " · " + $0 } ?? "")
    }

    private func personRow(_ person: EntryRecovery.Person) -> some View {
        let pending = person.receipt == nil && !status.isSettled
        return HStack(spacing: DS.Space.s8) {
            Text(person.participant.name).dsText(DS.Font.tSubStrong).lineLimit(1)
                .foregroundStyle(pending ? DS.Color.warnInk : DS.Color.accentInk)
                .frame(width: HomeSpec.tile32, height: HomeSpec.tile32)
                .dsPill(pending ? DS.Color.raised : DS.Color.accentSoft)
            VStack(alignment: .leading, spacing: HomeSpec.heroLabelGap) {
                Text(HomeDisplay.money(person.participant.amount, hidden: hidden))
                    .dsText(DS.Font.tBody).fontWeight(.semibold).monospacedDigit().foregroundStyle(DS.Color.ink)
                Text(person.receipt.map(receiptLabel) ?? (pending ? "待收回" : "已收回")).dsText(DS.Font.tCaption)
                    .foregroundStyle(pending ? DS.Color.warnInk : DS.Color.accentInk)
            }.dsFillWidth()
            if pending {
                action("收到", height: DS.Size.iconTile) { receive(person.id) }
                    .accessibilityLabel(person.participant.name + " 收到")
            } else {
                DSIconView(icon: .done, size: DS.Size.icon, color: DS.Color.accentInk)
                    .accessibilityLabel(person.participant.name + " 已收回")
            }
        }.frame(minHeight: HomeSpec.personHeight)
    }

    private func action(_ title: String, height: CGFloat, fullWidth: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).dsText(fullWidth ? DS.Font.tLabelStrong : HomeSpec.routeName).foregroundStyle(DS.Color.ink)
                .padding(.horizontal, DS.Space.s16)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
                .dsSurface(DS.Color.raised, radius: DS.Radius.s)
                .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin).contentShape(Rectangle())
        }.buttonStyle(EntryTactileButtonStyle())
    }
}

#if DEBUG
#Preview("账单") {
    let fixture = HomeFixture.bill(.partial, menu: false)
    let sample = fixture.makeLedger()
    ZStack {
        DS.Color.bg.ignoresSafeArea()
        DS.Color.scrim.ignoresSafeArea()
        if let entry = sample.ledger.entries.first(where: { $0.id == sample.billID }) {
            BillCardContent(entry: entry, ledger: sample.ledger, now: fixture.now, menuInitiallyOpen: false,
                            close: {}, edit: {}, recategorize: {}, duplicate: {}, delete: {}, receive: { _ in })
                .padding(DS.Space.s16)
        }
    }
}
#endif
