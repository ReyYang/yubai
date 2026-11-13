import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct EntryCategoryChips: View {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let frequent: [String]
    let income: Bool
    let selection: CategoryAssignment
    var suggestionOnly = false
    var allowsDirectionChange = true
    var directionChanged: (Bool) -> Void = { _ in }
    var suggest: () -> String? = { nil }
    let choose: (CategoryAssignment) -> Void
    @State private var picking = false
    @State private var pickerIncome = false
    @State private var suggested: String?
    private var visible: [String] {
        var rows = Array(frequent.prefix(5))
        if !rows.contains(selection.category), !selection.category.isEmpty, !Classification.isPending(selection.category) {
            rows.append(selection.category)
        }
        return rows
    }
    var body: some View {
        EntryCategoryLayout { layout in
            layout {
            ForEach(visible, id: \.self) { name in
                let suggestedChip = suggestionOnly && selection.category == name
                let selected = !suggestionOnly && selection.category == name
                Button { choose(.init(category: name)) } label: {
                    Text(name + ((selected || suggestedChip) ? selection.subcategory.map { " · " + $0 } ?? "" : ""))
                        .yubaiFont(YubaiFont.callout, weight: suggestedChip ? .semibold : selected ? .medium : .regular).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(suggestedChip ? YubaiColor.brandInk : YubaiColor.label)
                        .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                        .background(selected ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
                        .overlay { if selected || suggestedChip { Capsule().strokeBorder(YubaiColor.brand, lineWidth: suggestedChip ? 2 : 1.5) } }
                        .yubaiHitTarget()
                }.chipSelection(selected).accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityLabel(name + ((selected || suggestedChip) ? selection.subcategory.map { " · " + $0 } ?? "" : "") + (suggestedChip ? "（按你以前的记法）" : ""))
                    .accessibilityIdentifier("entryCategory_" + name)
            }
            Button { pickerIncome = income; suggested = suggest(); picking = true } label: {
                Text("更多").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).fixedSize()
                    .padding(.horizontal, YubaiSpace.gapGroup).frame(height: YubaiSize.chipHeight)
                    .overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: YubaiSize.separator) }
                    .yubaiHitTarget()
            }.accessibilityIdentifier("entryCategoryMore")
            }
        }.buttonStyle(PressButtonStyle()).animation(YubaiMotion.control(reduceMotion: reduceMotion), value: selection)
            .sheet(isPresented: $picking) {
                EntryMoreCategorySheet(income: pickerIncome, selection: selection, suggestionOnly: suggestionOnly,
                                       suggested: suggested, choose: { choice in
                    directionChanged(pickerIncome); choose(choice); picking = false
                }, dismiss: { picking = false })
            }
    }
}

/// 「全部」格和「更多」芯片共用的选分类页：常用在上，全部在下，点一颗就选中并回去。
struct EntryMoreCategorySheet: View {
    @Environment(AppStore.self) private var store
    let income: Bool
    let selection: CategoryAssignment
    var suggestionOnly = false
    var suggested: String? = nil
    let choose: (CategoryAssignment) -> Void
    let dismiss: () -> Void
    @State private var managing = false
    private var selected: CategoryAssignment? {
        suggestionOnly || selection.category.isEmpty || Classification.isPending(selection.category) ? nil : selection
    }
    var body: some View {
        NavigationStack {
            Page(topPadding: YubaiSpace.space8) {
                CategoryPicker(income: income, selected: selected, suggested: suggested,
                               identifier: "entryMore", style: .entry) { choice, addition in
                    if let addition, !store.update("添加分类", { try addition.apply(to: &$0) }) { return false }
                    choose(choice); return true
                }
            }.accessibilityIdentifier("entryCategoryPicker").manualSheetNavigation()
                .safeAreaInset(edge: .top) {
                    ManualSheetHeader(title: "选分类", actionTitle: "管理", primary: false, cancelTitle: "返回",
                                      actionIdentifier: "entryMoreManage", cancelIdentifier: "entryMoreCancel",
                                      cancel: dismiss, action: { managing = true }).padding(.horizontal, YubaiSpace.space20)
                }
        }.environment(store).appErrors().presentationDragIndicator(.visible).yubaiSheetBackground()
            .sheet(isPresented: $managing) {
                NavigationStack { CategoriesView().manualSheetHeader("分类", cancelTitle: "关闭", showsAction: false) }
                    .environment(store).appErrors().yubaiSheetBackground()
            }
    }
}

struct EntryAccountMenu: View {
    let accounts: [Account]
    let balances: [UUID: Int64]
    @Binding var selection: UUID?
    var showsBalance = false
    var optional = false
    var emptyTitle: String? = nil
    var inTray = false
    var identifier = ""
    var body: some View {
        Menu {
            if optional { Button("不指定") { selection = nil } }
            ForEach(accounts) { account in
                Button(account.name + " · 余额 " + balanceText(account.id)) { selection = account.id }
            }
        } label: {
            let account = accounts.first { $0.id == selection }
            let fallback: String = emptyTitle ?? (optional ? "不指定" : "选择账户")
            let name: String = account?.name ?? fallback
            let balance: String = (showsBalance ? account : nil).map { " · 余额 " + balanceText($0.id) } ?? ""
            HStack(spacing: YubaiSpace.space8) {
                if inTray { Image(systemName: "creditcard").accessibilityHidden(true) }
                Text(name + balance).fixedSize(horizontal: false, vertical: true)
            }.yubaiFont(YubaiFont.callout).fixedSize(horizontal: false, vertical: true).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: inTray ? YubaiSize.trayChip : YubaiSize.chipHeight)
                .background(inTray ? YubaiColor.keyFn : YubaiColor.raised, in: Capsule())
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("账户")
            .accessibilityValue(accounts.first { $0.id == selection }?.name ?? emptyTitle ?? (optional ? "不指定" : "选择账户"))
            .accessibilityIdentifier(identifier)
    }
    @Environment(AppStore.self) private var store
    private func balanceText(_ id: UUID) -> String {
        store.preferences.hideAmounts ? "••••" : AmountLabel.text(balances[id] ?? 0)
    }
}

struct RecentPurposeChips: View {
    @Environment(AppStore.self) private var store
    @Binding var selection: String
    var nature: Nature
    var recall: (Entry) -> Void
    @State private var recent: [EntryHistory.Recall] = []
    var body: some View {
        EntryChipLayout {
            ForEach(recent) { item in
                Button { selection = item.purpose; recall(item.entry) } label: {
                    Text(item.purpose).fixedSize().yubaiFont(YubaiFont.callout)
                        .padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.chipHeight).background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("recentPurpose_" + item.purpose)
            }
        }.accessibilityLabel("最近用过的用途")
            .task(id: "\(store.ledgerRevision)-\(nature.rawValue)") {
                let ledger = store.current; let nature = nature
                let values = await Task.detached { EntryHistory.recentPurposes(in: ledger, nature: nature) }.value
                guard !Task.isCancelled else { return }; recent = values
            }
    }
}

private struct EntryDiscardGuard: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let dirty: Bool
    let amount: Int64
    @Binding var confirming: Bool
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(dirty)
            #if os(iOS)
            .background { DismissAttempt(dirty: dirty) { confirming = true }.frame(width: YubaiSpace.none, height: YubaiSpace.none) }
            #endif
            .sheet(isPresented: $confirming) {
                ConfirmationSheet(title: amount == 0 ? "放弃修改？" : "已经填了 \(Money.text(amount, currency: false)) 元") {
                    Button("放弃这笔") { confirming = false; dismiss() }.buttonStyle(DestructiveButtonStyle())
                }
            }
    }
}

#if os(iOS)
private struct DismissAttempt: UIViewControllerRepresentable {
    var dirty: Bool
    var attempt: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.dirty = dirty; controller.attempt = attempt
        DispatchQueue.main.async { controller.install() }
    }
    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var dirty = false
        var attempt: () -> Void = {}
        weak var previousDelegate: UIAdaptivePresentationControllerDelegate?
        weak var attachedPresentation: UIPresentationController?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false; view.accessibilityElementsHidden = true }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        func install() {
            var host: UIViewController? = self
            while let current = host {
                if let presentation = current.presentationController, current.presentingViewController != nil {
                    if presentation.delegate !== self {
                        previousDelegate = presentation.delegate; presentation.delegate = self
                    }
                    attachedPresentation = presentation; break
                }
                host = current.parent
            }
        }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !dirty && (previousDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            previousDelegate?.presentationControllerWillDismiss?(presentationController)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            previousDelegate?.presentationControllerDidDismiss?(presentationController)
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if dirty { attempt() } else { previousDelegate?.presentationControllerDidAttemptToDismiss?(presentationController) }
        }
    }
}
#endif

extension View {
    func entryDiscardGuard(dirty: Bool, amount: Int64, confirming: Binding<Bool>) -> some View {
        modifier(EntryDiscardGuard(dirty: dirty, amount: amount, confirming: confirming))
    }
    func manualSheetNavigation() -> some View {
        self.paperBackground().environment(\.yubaiFormSurface, true)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
}

private struct RootTabScroll: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let tab: Destination
    #if os(iOS)
    @State private var position = ScrollPosition(edge: .top)
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
        content.scrollPosition($position).onChange(of: store.rootScrollRequest[tab]) { _, _ in
            withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { position.scrollTo(edge: .top) }
        }
        #else
        content
        #endif
    }
}
extension View {
    func rootTabScroll(_ tab: Destination) -> some View { modifier(RootTabScroll(tab: tab)) }
}

struct EntryFormFields<Trailing: View>: View {
    @Binding var purpose: String
    var purposeTitle = "用途"
    var purposeIdentifier = "entryPurpose"
    var purposeError: String? = nil
    var nature: Nature
    let accounts: [Account]
    let balances: [UUID: Int64]
    @Binding var accountID: UUID?
    @Binding var otherAccountID: UUID?
    @Binding var date: Date
    var showsTime = false
    var showsBalance = false
    var showsRecent = true
    var showsDate = true
    var optionalAccount = false
    var accountTitle: String? = nil
    var beforeAccount: AnyView? = nil
    var transferFallback: AnyView? = nil
    var focus: FocusState<Bool>.Binding
    var recall: (Entry) -> Void = { _ in }
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            InlineFieldError(message: purposeError)
            if showsRecent { RecentPurposeChips(selection: $purpose, nature: nature, recall: recall) }
            if nature == .transfer || (nature.paired && otherAccountID != nil) {
                Card(style: .list) {
                    EntryFormRow(title: "转入") {
                        if accounts.filter({ $0.id != accountID }).isEmpty, let transferFallback { transferFallback }
                        else {
                            EntryAccountMenu(accounts: accounts.filter { $0.id != accountID }, balances: balances, selection: $otherAccountID, showsBalance: showsBalance)
                                .accessibilityIdentifier("transferDestinationAccount")
                        }
                    }
                }
            }
            trailing()
        }
    }
}

struct EntryKeyboardTray<Controls: View, Keys: View>: View {
    @Binding var purpose: String
    var purposeTitle: String = "用途"
    var purposeIdentifier = "entryPurpose"
    var focus: FocusState<Bool>.Binding
    var compact = false
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let keys: () -> Keys
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            CardTextFieldRow(title: purposeTitle, text: $purpose, identifier: purposeIdentifier, focus: focus).padding(.horizontal, YubaiSpace.space8).padding(.top, YubaiSpace.space12)
            controls().padding(.horizontal, YubaiSpace.space8).padding(.top, compact ? YubaiSpace.none : YubaiSpace.space8)
            if !focus.wrappedValue { keys() }
        }.padding(.bottom, focus.wrappedValue ? YubaiSpace.space8 : YubaiSpace.none)
            .background { UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.card, topTrailingRadius: YubaiRadius.card).fill(YubaiColor.keypadTray).ignoresSafeArea(edges: .bottom) }
    }
}

struct EntryFixedSavingsChip: View {
    @Binding var selected: Bool
    var action: () -> Void = {}
    var body: some View {
        Button { action(); selected.toggle() } label: {
            Label("存下的钱", systemImage: "lock").yubaiFont(YubaiFont.caption)
                .foregroundStyle(selected ? YubaiColor.onBrand : YubaiColor.label)
                .padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.pillHeight)
                .background(selected ? YubaiColor.brand : YubaiColor.raised, in: Capsule())
                .fixedSize(horizontal: true, vertical: false).yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("entryIntoFixedSavings")
    }
}

// MARK: - Round 45 entry components

/// 记一笔的分类：两排五格带图标，顺序是用户自己排的，最后一格是「全部」。
/// 不预选；`hint` 只描边，由用户点一下才选中。最大字号时排成一行左右滑。
struct EntryCategoryGrid: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let nature: Nature
    let selection: CategoryAssignment
    var hint: String? = nil
    let choose: (CategoryAssignment?) -> Void
    let more: () -> Void
    private enum Slot: Identifiable {
        case category(YubaiCore.Category), all
        var id: String { switch self { case .category(let value): value.id; case .all: "all" } }
    }
    private var income: Bool { nature != .refund && nature.inflow }
    private var slots: [Slot] {
        let ordered = store.current.orderedCategories(income: income)
        var shown = Array(ordered.prefix(9))
        let name = selection.category
        if !name.isEmpty, !shown.contains(where: { $0.name == name }), let picked = ordered.first(where: { $0.name == name }) {
            if shown.count == 9 { shown[8] = picked } else { shown.append(picked) }
        }
        return shown.map { Slot.category($0) } + [Slot.all]
    }
    var body: some View {
        let items = slots
        Group {
            if textSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: YubaiSpace.space8) {
                        ForEach(Array(items.prefix(4)) + [Slot.all]) { slot in largeCell(slot) }
                    }
                }.frame(height: YubaiSize.tapMin + YubaiSpace.space8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: YubaiSpace.space8), count: 5), spacing: YubaiSpace.space8) {
                    ForEach(items) { slot in cell(slot) }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("分类").accessibilityIdentifier("entryCategoryGrid")
    }
    @ViewBuilder private func largeCell(_ slot: Slot) -> some View {
        switch slot {
        case .category(let category):
            CategoryChoiceChip(title: category.name, selected: selection.category == category.name,
                               outlined: hint == category.name && selection.category != category.name) {
                choose(selection.category == category.name ? nil : .init(category: category.name))
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).accessibilityIdentifier("entryCategory_" + category.name)
        case .all:
            CategoryChoiceChip(title: "更多", action: more).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityIdentifier("entryCategoryMore")
        }
    }
    @ViewBuilder private func cell(_ slot: Slot) -> some View {
        switch slot {
        case .category(let category):
            let selected = selection.category == category.name
            let mode: IconGridCell.Mode = selected ? .selected : (hint == category.name ? .outlined : .normal)
            IconGridCell(title: category.name, symbol: category.symbol, mode: mode,
                         identifier: "entryCategory_" + category.name) {
                choose(selected ? nil : CategoryAssignment(category: category.name))
            }
        case .all:
            IconGridCell(title: "全部", symbol: "ellipsis", mode: .normal, identifier: "entryCategoryMore", action: more)
        }
    }
}

/// 今天 / 昨天 / 前天 三颗；长按这一排升起月历。选了更早的日子，多出一颗显示那一天。
struct EntryDayChips: View {
    @Binding var date: Date
    let pick: () -> Void
    private func day(_ offset: Int) -> Date { Dates.addDays(offset, to: Date()) }
    private var isStandard: Bool { [0, -1, -2].contains { Dates.calendar.isDate(date, inSameDayAs: day($0)) } }
    var body: some View {
        HStack(spacing: YubaiSpace.space8) {
            chip("今天", id: "entryDate_today", offset: 0)
            chip("昨天", id: "entryDate_yesterday", offset: -1)
            chip("前天", id: "entryDate_before", offset: -2)
            if !isStandard {
                Button(action: pick) {
                    Text(ManualBookkeeping.dayLabel(date)).yubaiFont(YubaiFont.callout, weight: .medium).fixedSize()
                        .foregroundStyle(YubaiColor.canvas).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.trayChip)
                        .background(YubaiColor.label, in: Capsule()).yubaiHitTarget()
                }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(.isSelected).accessibilityIdentifier("entryDate_other")
            }
        }.simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in pick() })
            .accessibilityElement(children: .contain).accessibilityAction(named: "选别的日子", pick)
    }
    private func chip(_ title: String, id: String, offset: Int) -> some View {
        let target = day(offset)
        let selected = Dates.calendar.isDate(date, inSameDayAs: target)
        return Button {
            let c = Dates.calendar
            date = c.date(bySettingHour: c.component(.hour, from: date), minute: c.component(.minute, from: date),
                          second: c.component(.second, from: date), of: target) ?? target
        } label: {
            Text(title).yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular).fixedSize()
                .foregroundStyle(selected ? YubaiColor.canvas : YubaiColor.label)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.trayChip)
                .background(selected ? YubaiColor.label : YubaiColor.keyFn, in: Capsule()).yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(id)
    }
}

/// 转账：从哪到哪，两个账户并排，各带当前余额。
struct EntryTransferCards: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let accounts: [Account]
    let balances: [UUID: Int64]
    @Binding var from: UUID?
    @Binding var to: UUID?
    var fallback: AnyView? = nil
    let selectAccount: (Bool) -> Void
    private var destinations: [Account] { accounts.filter { $0.id != from } }
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
        layout {
            card(title: "从", list: accounts, selection: $from, identifier: "transferSourceAccount")
            if !textSize.isAccessibilitySize {
                Image(systemName: "arrow.right").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            }
            if destinations.isEmpty, let fallback { fallback.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble) }
            else { card(title: "到", list: destinations, selection: $to, identifier: "transferDestinationAccount") }
        }
    }
    private func card(title: String, list: [Account], selection: Binding<UUID?>, identifier: String) -> some View {
        let account = list.first { $0.id == selection.wrappedValue }
        let hide = store.preferences.hideAmounts
        let balance = account.map { amount2(balances[$0.id] ?? 0, hide: hide) } ?? ""
        return Button { selectAccount(identifier == "transferDestinationAccount") } label: {
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Text(account?.name ?? "选择账户").yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label).lineLimit(1)
                Text(balance).yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.labelSecondary).fixedSize(horizontal: false, vertical: true)
            }.padding(YubaiSpace.gapGroup).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading)
                .background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(title).accessibilityValue((account?.name ?? "") + " " + balance)
            .accessibilityIdentifier(identifier)
    }
}

/// 输用途时列出记过的同名账目，连分类和金额一起带出来。
struct EntryRecallList: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let recalls: [EntryHistory.Recall]
    let choose: (EntryHistory.Recall) -> Void
    var body: some View {
        VStack(spacing: YubaiSpace.space8) {
            ForEach(recalls) { item in
                Button { choose(item) } label: {
                    let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
                    layout {
                        Text(item.purpose).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: YubaiSpace.space8) {
                            Text(Classification.displayCategory(item.entry.category)).yubaiFont(YubaiFont.caption)
                                .foregroundStyle(YubaiColor.labelSecondary).lineLimit(1)
                            AmountLabel(cents: item.entry.amount, hide: store.preferences.hideAmounts, role: .summary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.horizontal, YubaiSpace.gapGroup).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble)
                        .background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                        .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("recentPurpose_" + item.purpose)
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("记过的用途")
    }
}

/// The session title opens these ledger-backed rows inside the current sheet.
struct EntryAddedList: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let entries: [Entry]
    let edit: (Entry) -> Void
    let remove: (Entry) -> Void
    var body: some View {
        ScrollView {
            NativeCardRows(entries) { entry in
                Button { edit(entry) } label: {
                    let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
                    layout {
                        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                            Text(entry.displayTitle).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).lineLimit(1)
                            Text(Classification.displayCategory(entry.category) + " · " + ManualBookkeeping.dayLabel(entry.date))
                                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: YubaiSpace.space8) {
                            AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts, sign: entry.nature.inflow ? .inflow : .outflow).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        }
                    }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("editSessionEntry_" + entry.id.uuidString)
                    .swipeActions(edge: .trailing) {
                        Button("删掉") { remove(entry) }.tint(YubaiColor.amberInk)
                            .accessibilityIdentifier("deleteSessionEntry_" + entry.id.uuidString)
                    }.accessibilityAction(named: "删掉") { remove(entry) }
            }
        }.scrollDisabled(entries.count < 4).accessibilityIdentifier("entryAddedList")
    }
}

/// Keep category choices to one horizontal row at accessibility sizes.
private struct EntryCategoryLayout<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ViewBuilder let content: (AnyLayout) -> Content
    var body: some View {
        if textSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) {
                content(AnyLayout(HStackLayout(spacing: YubaiSpace.space8)))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }.frame(height: YubaiSize.buttonHeight).accessibilityIdentifier("entryCategoryStrip")
        } else { content(AnyLayout(EntryChipLayout())) }
    }
}
