import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct EntryCategoryChips: View {
    @Environment(AppStore.self) private var store
    @Environment(\.surfacePresentations) private var presentations
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let frequent: [String]
    let income: Bool
    let selection: CategoryAssignment
    var suggestionOnly = false
    var allowsDirectionChange = true
    var directionChanged: (Bool) -> Void = { _ in }
    var suggest: () -> String? = { nil }
    let choose: (CategoryAssignment) -> Void
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
            Button {
                let suggested = suggest()
                presentations.presentSheet {
                    EntryMoreCategorySheet(income: income, selection: selection, suggestionOnly: suggestionOnly,
                                           suggested: suggested, choose: { choice in
                        directionChanged(income); choose(choice); presentations.dismissSheet()
                    }, dismiss: { presentations.dismissSheet() })
                }
            } label: {
                Text("更多").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).fixedSize()
                    .padding(.horizontal, YubaiSpace.gapGroup).frame(height: YubaiSize.chipHeight)
                    .overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: YubaiSize.separator) }
                    .yubaiHitTarget()
            }.accessibilityIdentifier("entryCategoryMore")
            }
        }.buttonStyle(PressButtonStyle()).animation(YubaiMotion.control(reduceMotion: reduceMotion), value: selection)
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
            .accessibilityAction(.escape) {
                if dirty { confirming = true } else { dismiss() }
            }
            #if os(iOS)
            .background { DismissAttempt(dirty: dirty) { confirming = true }.frame(width: YubaiSpace.none, height: YubaiSpace.none) }
            #elseif os(macOS)
            .onExitCommand { if dirty { confirming = true } else { dismiss() } }
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
    @ViewBuilder func rootTabScroll(_ tab: Destination?) -> some View {
        if let tab { modifier(RootTabScroll(tab: tab)) }
        else { self }
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
            CardTextFieldRow(title: purposeTitle, text: $purpose, identifier: purposeIdentifier, focus: focus)
                .padding(.horizontal, YubaiSpace.gapGroup)
                .background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous).strokeBorder(YubaiColor.separator, lineWidth: YubaiSize.separator) }
                .padding(.horizontal, YubaiSpace.space8).padding(.top, YubaiSpace.space12)
            controls().padding(.horizontal, YubaiSpace.space8).padding(.top, compact ? YubaiSpace.space4 : YubaiSpace.space8)
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
                }.fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: YubaiSize.tapMin + YubaiSpace.space8)
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
            }.accessibilityIdentifier("entryCategory_" + category.name)
        case .all:
            CategoryChoiceChip(title: "更多", action: more)
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
