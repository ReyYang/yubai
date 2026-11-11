import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct ManualSheetHeader: View {
    @Environment(\.yubaiSheetSurface) private var inSheet
    let title: String
    var actionTitle = "保存"
    var actionImage: String? = nil
    var primary = true
    var showsAction = true
    var enabled = true
    var cancelTitle = "取消"
    var actionIdentifier: String? = nil
    var cancelIdentifier = "cancelManualSheet"
    let cancel: () -> Void
    let action: () -> Void
    private var titleView: some View {
        Text(title).yubaiFont(["记一笔", "改一笔", "改这笔"].contains(title) ? YubaiFont.entrySheetTitle : YubaiFont.navTitle).fixedSize()
    }
    private var cancelButton: some View {
        Button(action: cancel) {
            Text(cancelTitle).yubaiFont(YubaiFont.body).fixedSize()
                .padding(.horizontal, 16).frame(minHeight: 36).background(YubaiColor.card, in: Capsule())
                .frame(minHeight: 44).contentShape(Capsule())
        }.accessibilityIdentifier(cancelIdentifier == "cancelManualSheet" && cancelTitle != "取消" ? "closeSheet" : cancelIdentifier)
    }
    @ViewBuilder private var actionButton: some View {
        if showsAction {
            Button(action: action) {
                HStack(spacing: 8) { if let actionImage { Image(systemName: actionImage) }; Text(actionTitle).fixedSize() }
                    .yubaiFont(YubaiFont.body, weight: primary ? .medium : .regular)
                    .padding(.horizontal, 12).frame(minHeight: 36)
                    .foregroundStyle(primary ? YubaiColor.onBrand : YubaiColor.label)
                    .background(primary ? YubaiColor.brand : YubaiColor.card, in: Capsule())
                    .contentShape(Capsule())
            }.frame(minHeight: 44).disabled(!enabled).opacity(enabled ? 1 : 0.4)
                .accessibilityIdentifier(actionIdentifier ?? (actionTitle == "导入" ? "importFromEntry" : "saveManualSheet"))
        } else { Color.clear.frame(width: 64, height: 36).accessibilityHidden(true) }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { cancelButton; Spacer(minLength: 0); titleView; Spacer(minLength: 0); actionButton }
            VStack(spacing: 4) {
                titleView
                ViewThatFits(in: .horizontal) {
                    HStack { cancelButton; Spacer(); actionButton }
                    VStack(spacing: 8) { cancelButton; actionButton }
                }
            }
        }.frame(minHeight: 48).padding(.top, inSheet ? YubaiSpace.sheetHeaderTop : 0).buttonStyle(PressButtonStyle())
    }
}

/// Chips wrap at their intrinsic width, including at accessibility text sizes.
struct EntryChipLayout: Layout {
    var spacing: CGFloat = YubaiSpace.space8
    var rowSpacing: CGFloat = YubaiSpace.gapGroup
    private func arrangement(_ subviews: Subviews, width: CGFloat) -> (CGSize, [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            // 32pt chips in 44pt targets already contribute 12pt of visible vertical space.
            let targetOutset = YubaiSize.tapMin - YubaiSize.chipHeight
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + max(YubaiSpace.none, rowSpacing - targetOutset); rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: proposal.width ?? 354).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = arrangement(subviews, width: bounds.width).1
        for (index, view) in subviews.enumerated() { view.place(at: CGPoint(x: bounds.minX + points[index].x, y: bounds.minY + points[index].y), anchor: .topLeading, proposal: .unspecified) }
    }
}

struct EntryCategoryChips: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        EntryChipLayout {
            ForEach(visible, id: \.self) { name in
                let suggestedChip = suggestionOnly && selection.category == name
                let selected = !suggestionOnly && selection.category == name
                Button { choose(.init(category: name)) } label: {
                    Text(name + ((selected || suggestedChip) ? selection.subcategory.map { " · " + $0 } ?? "" : ""))
                        .yubaiFont(YubaiFont.callout, weight: suggestedChip ? .semibold : selected ? .medium : .regular).lineLimit(1).fixedSize()
                        .foregroundStyle(suggestedChip ? YubaiColor.brandInk : YubaiColor.label)
                        .padding(.horizontal, YubaiSpace.gapGroup).frame(height: YubaiSize.chipHeight)
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
                    .overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: 1) }
                    .yubaiHitTarget()
            }.accessibilityIdentifier("entryCategoryMore")
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
                                      cancel: dismiss, action: { managing = true }).padding(.horizontal, 20)
                }
        }.environment(store).appErrors().presentationDragIndicator(.visible).yubaiSheetBackground()
            .sheet(isPresented: $managing) {
                NavigationStack { CategoriesView().manualSheetHeader("分类", cancelTitle: "关闭", showsAction: false) }
                    .environment(store).appErrors().yubaiSheetBackground()
            }
    }
}

struct EntryFormRow<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text(title).yubaiFont(YubaiFont.body).fixedSize()
                Spacer(minLength: YubaiSpace.none)
                content.fixedSize(horizontal: true, vertical: true)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.body).fixedSize()
                content.frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(.vertical, 8)
        }.frame(minHeight: YubaiSize.rowSingle).yubaiFont(YubaiFont.body)
    }
}

struct EntryFormDivider: View {
    var body: some View { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
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
            HStack(spacing: 6) {
                if inTray { Image(systemName: "creditcard").accessibilityHidden(true) }
                Text((account?.name ?? emptyTitle ?? (optional ? "不指定" : "选择账户")) + (showsBalance && account != nil ? " · 余额 " + balanceText(account!.id) : "")).fixedSize(horizontal: false, vertical: true)
            }.yubaiFont(YubaiFont.callout).fixedSize(horizontal: false, vertical: true).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: inTray ? 34 : YubaiSize.chipHeight)
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

struct EntryDateChip: View {
    @Binding var date: Date
    var time = false
    var iconOnly = false
    var inTray = false
    var allowsFuture = false
    @State private var picking = false
    @State private var latestDate = Date()
    var body: some View {
        Button { latestDate = Date(); picking = true } label: {
            Group {
                if iconOnly { Image(systemName: "calendar").frame(width: 20) }
                else if inTray && !time { Label(ManualBookkeeping.dayLabel(date), systemImage: "calendar").fixedSize() }
                else { Text(time ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : ManualBookkeeping.dayLabel(date)).fixedSize() }
            }
                .yubaiFont(time ? YubaiFont.amountSmall : YubaiFont.callout)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: inTray ? 34 : YubaiSize.chipHeight).background(inTray ? YubaiColor.keyFn : YubaiColor.raised, in: Capsule())
                .yubaiHitTarget()
        }.accessibilityLabel(iconOnly ? "选别的日子" : time ? "时间" : "日期").accessibilityValue(time ? date.formatted(.dateTime.hour().minute()) : ManualBookkeeping.dayLabel(date)).buttonStyle(PressButtonStyle()).popover(isPresented: $picking) {
            VStack(spacing: YubaiSpace.gapGroup) {
                if time {
                    DatePicker("时间", selection: $date, in: ...latestDate, displayedComponents: .hourAndMinute).labelsHidden().frame(width: 240).fixedSize()
                } else {
                    if allowsFuture { DatePicker("日期", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().frame(width: 320, height: 360).fixedSize() }
                    else { DatePicker("日期", selection: $date, in: ...latestDate, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().frame(width: 320, height: 360).fixedSize() }
                }
                Button("完成") { picking = false }.frame(minHeight: YubaiSize.tapMin)
            }.padding(YubaiSpace.insetCard).transaction { $0.animation = nil }
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
        }
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
                        .padding(.horizontal, 12).frame(minHeight: 32).background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
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

/// Shared by quick entry, entry editing and fixed-flow amounts.
struct AmountKeypad: View {
    @Binding var keypad: EntryKeypad
    @Binding var amountSelected: Bool
    let canSave: Bool
    let primaryTitle: String
    let primaryIdentifier: String
    let save: () -> Void
    var saveAnother: (() -> Void)? = nil
    var embedded = false
    @StateObject private var feedback = AmountKeypadFeedback()
    @State private var secondaryTouched = false
    // The keys never grow with Dynamic Type; the amount above them is what scales.
    private let keyHeight: CGFloat = 52
    private let secondaryHeight: CGFloat = 46
    private let rows = [["1", "2", "3", "⌫"], ["4", "5", "6", "+"], ["7", "8", "9", "−"]]

    init(keypad: Binding<EntryKeypad>, amountSelected: Binding<Bool> = .constant(false), canSave: Bool,
         primaryTitle: String, primaryIdentifier: String, save: @escaping () -> Void, saveAnother: (() -> Void)? = nil, embedded: Bool = false) {
        _keypad = keypad; _amountSelected = amountSelected; self.canSave = canSave
        self.primaryTitle = primaryTitle; self.primaryIdentifier = primaryIdentifier; self.save = save; self.saveAnother = saveAnother; self.embedded = embedded
    }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let keyWidth = max(0, (geometry.size.width - 18) / 4)
                VStack(spacing: 6) {
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: 6) { ForEach(rows[row], id: \.self) { key in
                            AmountKeypadKey(key: key, keypad: $keypad, amountSelected: $amountSelected, feedback: feedback, height: keyHeight)
                                .frame(width: keyWidth)
                        } }
                    }
                    HStack(spacing: 6) {
                        AmountKeypadKey(key: ".", keypad: $keypad, amountSelected: $amountSelected, feedback: feedback, height: keyHeight)
                            .frame(width: keyWidth)
                        AmountKeypadKey(key: "0", keypad: $keypad, amountSelected: $amountSelected, feedback: feedback, height: keyHeight)
                            .frame(width: keyWidth)
                        Button(action: save) {
                            Text(primaryTitle).yubaiFont(YubaiFont.keypadAction)
                                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center).frame(maxWidth: .infinity).frame(minHeight: keyHeight)
                        }.buttonStyle(AmountKeyButtonStyle(primary: true, pressing: { if $0 { feedback.press("记下", accepted: true) } }))
                            .frame(width: keyWidth * 2 + 6).opacity(canSave ? 1 : 0.4).disabled(!canSave)
                            .accessibilityIdentifier(primaryIdentifier)
                    }
                }
            }.frame(height: keyHeight * 4 + 6 * 3)
            if let saveAnother {
                Button { if !secondaryTouched { feedback.success() }; secondaryTouched = false; saveAnother() } label: {
                    Label("记下，再记一笔", systemImage: "plus").yubaiFont(YubaiFont.body, weight: .medium)
                        .frame(maxWidth: .infinity).frame(minHeight: secondaryHeight)
                }.buttonStyle(AmountKeyButtonStyle(secondary: true, pressing: { if $0 { secondaryTouched = true; feedback.success() } }))
                    .padding(.top, 6).opacity(canSave ? 1 : 0.4).disabled(!canSave).accessibilityIdentifier("saveAndAddAnother")
            }
        }.padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 8)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .background {
                if !embedded {
                    UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.card, topTrailingRadius: YubaiRadius.card)
                        .fill(YubaiColor.keypadTray).ignoresSafeArea(edges: .bottom)
                }
            }
            .accessibilityElement(children: .contain).accessibilityLabel("数字键盘")
            .onAppear { feedback.prepare() }
    }
}

private struct AmountKeypadKey: View {
    let key: String
    @Binding var keypad: EntryKeypad
    @Binding var amountSelected: Bool
    let feedback: AmountKeypadFeedback
    var height: CGFloat = 52
    @State private var holdTask: Task<Void, Never>?
    @State private var deletedOnTouch = false
    private var selected: Bool { keypad.pendingOperator == key }
    var body: some View {
        Button {
            if deletedOnTouch { deletedOnTouch = false; return }
            keypad.press(key, replacingAmount: amountSelected); amountSelected = false
        } label: {
            Group {
                if key == "⌫" { Image(systemName: "delete.left") }
                else { Text(key) }
            }.yubaiFont(YubaiFont.amountAccount, weight: .regular)
                .frame(maxWidth: .infinity).frame(height: height)
        }.buttonStyle(AmountKeyButtonStyle(function: ["⌫", "+", "−"].contains(key), selected: selected, pressing: pressChanged))
            .accessibilityLabel(key == "⌫" ? "删除一位" : key == "+" ? "加" : key == "−" ? "减" : key == "." ? "小数点" : key)
            .accessibilityIdentifier("keypad_" + key).accessibilityAddTraits(selected ? .isSelected : [])
            .onDisappear { holdTask?.cancel() }
    }
    private func pressChanged(_ pressed: Bool) {
        holdTask?.cancel()
        guard pressed else { DispatchQueue.main.async { deletedOnTouch = false }; return }
        deletedOnTouch = false
        var next = keypad; next.press(key, replacingAmount: amountSelected)
        feedback.press(key, accepted: next != keypad)
        guard key == "⌫" else { return }
        deletedOnTouch = true; keypad = next; amountSelected = false
        guard keypad.expression != "0" else { return }
        holdTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            var count = 0
            while !Task.isCancelled {
                keypad.press("⌫"); feedback.deletion(); count += 1
                if keypad.expression == "0" { break }
                do { try await Task.sleep(for: .milliseconds(max(45, 150 - count * 15))) } catch { return }
            }
        }
    }
}

private struct AmountKeyButtonStyle: ButtonStyle {
    var primary = false
    var secondary = false
    var function = false
    var selected = false
    var pressing: (Bool) -> Void = { _ in }
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = primary ? (pressed ? YubaiColor.brandInk : YubaiColor.brand)
            : pressed ? (function ? YubaiColor.keyFnPressed : YubaiColor.keyPressed)
            : selected ? YubaiColor.brandTint : (function ? YubaiColor.keyFn : YubaiColor.key)
        return configuration.label
            .foregroundStyle(primary ? YubaiColor.onBrand : (selected || secondary) ? YubaiColor.brandInk : YubaiColor.label)
            .background(fill, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: YubaiRadius.control).strokeBorder(YubaiColor.brand, lineWidth: 1.5) }
            }
            .shadow(color: primary || selected || pressed ? .clear : YubaiColor.shadowKey, radius: 0, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
            .animation(pressed ? nil : .easeOut(duration: YubaiMotion.durationQuick), value: pressed)
            .onChange(of: pressed) { _, value in pressing(value) }
    }
}

@MainActor private final class AmountKeypadFeedback: ObservableObject {
    #if os(iOS)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let completion = UINotificationFeedbackGenerator()
    #endif
    func prepare() {
        #if os(iOS)
        light.prepare(); medium.prepare(); rigid.prepare(); completion.prepare()
        #endif
    }
    func press(_ key: String, accepted: Bool) {
        #if os(iOS)
        if !accepted { rigid.impactOccurred(intensity: 0.5); rigid.prepare() }
        else if key == "+" || key == "−" { medium.impactOccurred(); medium.prepare() }
        else { light.impactOccurred(); light.prepare() }
        #endif
    }
    func success() {
        #if os(iOS)
        completion.notificationOccurred(.success); completion.prepare()
        #endif
    }
    func deletion() {
        #if os(iOS)
        light.impactOccurred(); light.prepare()
        #endif
    }
}

/// A single button keeps the entire amount accessible and avoids decimalPad.
struct EditableAmountDisplay: View {
    let amount: String
    let keypad: EntryKeypad
    let presented: Bool
    let selected: Bool
    let identifier: String
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                Text(presented ? keypad.expressionText ?? "" : "").yubaiFont(YubaiFont.amount).foregroundStyle(YubaiColor.labelSecondary)
                    .lineLimit(1).minimumScaleFactor(0.5).frame(height: 20)
                    .accessibilityIdentifier("entryKeypadExpression").accessibilityHidden(!presented || keypad.expressionText == nil)
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                    Text(presented ? keypad.resultText : ((try? Money.parse(amount)).map { EntryKeypad(amount: $0).resultText } ?? "0.00"))
                        .yubaiFont(YubaiFont.entryAmount).lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 6)
                        .background(selected ? YubaiColor.brandTint : .clear, in: RoundedRectangle(cornerRadius: 10))
                    if presented { EntryAmountCursor() }
                    Spacer(minLength: 0)
                }.frame(minHeight: YubaiSize.rowDouble)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(YubaiColor.label)
            .accessibilityLabel("金额").accessibilityValue(presented ? keypad.resultText : EntryKeypad(amount: (try? Money.parse(amount)) ?? 0).resultText)
            .accessibilityIdentifier(identifier)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: AmountEditorFrame.self, value: proxy.frame(in: .named("amountEditor")))
                }
            }
    }
}

private struct AmountEditorFrame: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct AmountEditorOutsideTap: ViewModifier {
    let presented: Bool
    let finish: () -> Void
    @State private var amountFrame = CGRect.zero
    func body(content: Content) -> some View {
        content.contentShape(Rectangle()).coordinateSpace(name: "amountEditor")
            .onPreferenceChange(AmountEditorFrame.self) { amountFrame = $0 }
            .simultaneousGesture(SpatialTapGesture().onEnded { event in
                if presented && !amountFrame.contains(event.location) { finish() }
            })
    }
}

extension View {
    func finishAmountOnOutsideTap(presented: Bool, finish: @escaping () -> Void) -> some View {
        modifier(AmountEditorOutsideTap(presented: presented, finish: finish))
    }
}

struct EntryRepeatChip: View {
    var selected: Bool
    var value: String
    var opensPlan = false
    var inTray = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(value + (opensPlan ? " ›" : "")).yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: inTray ? 34 : YubaiSize.chipHeight)
                .background(inTray ? YubaiColor.keyFn : selected ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
                .overlay { if selected { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("entryRepeat")
            .accessibilityLabel("重复").accessibilityValue(value).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The four entry surfaces use this form; their state and commit operations stay with their owners.
struct EntryForm<Content: View>: View {
    let title: String
    var actionTitle = "好"
    var actionImage: String? = nil
    var primary = true
    var showsAction = true
    var enabled = true
    var actionIdentifier: String? = nil
    var scrollIdentifier = "entryFormScroll"
    var cancelTitle = "取消"
    let cancel: () -> Void
    let save: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            ManualSheetHeader(title: title, actionTitle: actionTitle, actionImage: actionImage, primary: primary,
                              showsAction: showsAction, enabled: enabled, cancelTitle: cancelTitle, actionIdentifier: actionIdentifier,
                              cancel: cancel, action: save).padding(.horizontal, YubaiSpace.insetPage)
            ScrollView {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup, content: content)
                    .padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.gapGroup).padding(.bottom, YubaiSpace.gapSection)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier(scrollIdentifier)
        }
    }
}

struct EntryDateRow: View {
    @Binding var date: Date
    var showsTime = false
    private var today: Date { Date() }
    private func choose(_ day: Date) {
        let c = Dates.calendar
        date = c.date(bySettingHour: c.component(.hour, from: date), minute: c.component(.minute, from: date), second: c.component(.second, from: date), of: day)!
    }
    var body: some View {
        EntryFormRow(title: showsTime ? "时间" : "日期") {
            EntryChipLayout(spacing: 6, rowSpacing: 6) {
                dayChip("今天", day: today)
                dayChip("昨天", day: Dates.addDays(-1, to: today))
                EntryDateChip(date: $date, iconOnly: true)
                if showsTime { EntryDateChip(date: $date, time: true) }
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: 300, alignment: .trailing)
        }
    }
    private func dayChip(_ title: String, day: Date) -> some View {
        let selected = Dates.calendar.isDate(date, inSameDayAs: day)
        return Button { choose(day) } label: {
            Text(title).fixedSize().yubaiFont(YubaiFont.callout)
                .padding(.horizontal, 12).frame(height: 32)
                .background(selected ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
                .overlay { if selected { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }.yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct EntryAmountCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    var body: some View {
        Rectangle().fill(YubaiColor.brand).frame(width: 2, height: 34)
            .opacity(visible || reduceMotion ? 1 : 0).accessibilityHidden(true)
            .task(id: reduceMotion) {
                visible = true; guard !reduceMotion else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    visible.toggle()
                }
            }
    }
}

struct InlineFieldError: View {
    let message: String?
    var body: some View {
        if let message {
            Text(message).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.amberInk)
                .padding(.leading, 16).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("inlineFieldError")
        }
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.destructiveAction)
            .foregroundStyle(YubaiColor.amberInk).frame(maxWidth: .infinity, minHeight: 52)
            .background(configuration.isPressed ? YubaiColor.keyPressed : YubaiColor.card, in: Capsule())
            .contentShape(Capsule())
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
            .background { DismissAttempt(dirty: dirty) { confirming = true }.frame(width: 0, height: 0) }
            #endif
            .confirmationDialog(amount == 0 ? "放弃修改？" : "已经填了 \(Money.text(amount, currency: false)) 元", isPresented: $confirming, titleVisibility: .visible) {
                Button("放弃这笔", role: .destructive) { dismiss() }.foregroundStyle(YubaiColor.amberInk)
                Button("继续记", role: .cancel) {}
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

private struct NativeRowsHeight: PreferenceKey {
    static let defaultValue: [AnyHashable: CGFloat] = [:]
    static func reduce(value: inout [AnyHashable: CGFloat], nextValue: () -> [AnyHashable: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
/// A self-sizing native List provides swipe actions inside an existing paper card.
struct NativeCardRows<Item: Identifiable, Row: View>: View where Item.ID: Hashable {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row
    @State private var heights: [AnyHashable: CGFloat] = [:]
    @ScaledMetric private var estimatedHeight: CGFloat = 76
    init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) { self.items = items; self.row = row }
    var body: some View {
        List(items) { item in
            row(item).fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
                .background { GeometryReader { geometry in Color.clear.preference(key: NativeRowsHeight.self, value: [AnyHashable(item.id): geometry.size.height]) } }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(YubaiColor.paperSheet).listRowSeparatorTint(YubaiColor.separator)
        }.listStyle(.plain).scrollContentBackground(.hidden).scrollDisabled(true)
            .frame(height: items.reduce(CGFloat(0)) { $0 + max(44, heights[AnyHashable($1.id)] ?? estimatedHeight) })
            .clipShape(RoundedRectangle(cornerRadius: YubaiRadius.card))
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
            .onPreferenceChange(NativeRowsHeight.self) { value in if value != heights { heights = value } }
    }
}

private struct ManualSheetTop: ViewModifier {
    @Environment(\.yubaiSheetSurface) private var inSheet
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionTitle: String
    let enabled: Bool
    let primary: Bool
    let cancelTitle: String
    let showsAction: Bool
    let actionIdentifier: String?
    let cancelAction: (() -> Void)?
    let action: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if !inSheet && !showsAction { content }
        else { content.manualSheetNavigation().safeAreaInset(edge: .top, spacing: 0) {
            ManualSheetHeader(title: title, actionTitle: actionTitle, primary: primary, showsAction: showsAction, enabled: enabled,
                              cancelTitle: cancelTitle, actionIdentifier: actionIdentifier,
                              cancel: { if let cancelAction { cancelAction() } else { dismiss() } }, action: action)
                .padding(.horizontal, YubaiSpace.insetPage)
        } }
    }
}
extension View {
    func manualSheetHeader(_ title: String, actionTitle: String = "好", primary: Bool = true, enabled: Bool = true, cancelTitle: String = "取消",
                           showsAction: Bool = true, actionIdentifier: String? = nil, cancel: (() -> Void)? = nil,
                           action: @escaping () -> Void = {}) -> some View {
        modifier(ManualSheetTop(title: title, actionTitle: actionTitle, enabled: enabled, primary: primary, cancelTitle: cancelTitle,
                                showsAction: showsAction, actionIdentifier: actionIdentifier, cancelAction: cancel, action: action))
    }
}

/// Common entry fields for manual entry, editing and Ask drafts. Arrangement-specific schedule rows use the same trailing slot.
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
        VStack(alignment: .leading, spacing: 12) {
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
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let keys: () -> Keys
    var body: some View {
        VStack(spacing: 0) {
            EntryPurposeWell(purpose: $purpose, title: purposeTitle, identifier: purposeIdentifier, focus: focus).padding(.horizontal, 8).padding(.top, 10)
            controls().padding(.horizontal, 8).padding(.top, 8)
            if !focus.wrappedValue { keys() }
        }.padding(.bottom, focus.wrappedValue ? 8 : 0)
            .background { UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.card, topTrailingRadius: YubaiRadius.card).fill(YubaiColor.keypadTray).ignoresSafeArea(edges: .bottom) }
    }
}

struct EntryFixedSavingsChip: View {
    @Binding var selected: Bool
    var action: () -> Void = {}
    var body: some View {
        Button { action(); selected.toggle() } label: {
            Label("存着不动", systemImage: "lock").yubaiFont(YubaiFont.caption)
                .foregroundStyle(selected ? YubaiColor.onBrand : YubaiColor.label)
                .padding(.horizontal, 10).frame(minHeight: 28)
                .background(selected ? YubaiColor.brand : YubaiColor.raised, in: Capsule())
                .fixedSize(horizontal: true, vertical: false).yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("entryIntoFixedSavings")
    }
}

struct EntrySavingHintBar: View {
    @Environment(AppStore.self) private var store
    let hint: EntryHint
    var fixedSavingsTotals: (current: Int64, new: Int64)?
    var afterOverride: Int64? = nil
    var category = ""
    var ledgerOverride: Ledger? = nil
    var allowsPartSelection = false
    var allowsRememberPart = true
    @Binding var partID: UUID?
    @Binding var rememberPart: Bool
    @State private var pickingPart = false
    init(hint: EntryHint, afterOverride: Int64? = nil, category: String = "", ledgerOverride: Ledger? = nil, allowsPartSelection: Bool = false, allowsRememberPart: Bool = true, fixedSavingsTotals: (current: Int64, new: Int64)? = nil,
         partID: Binding<UUID?> = .constant(nil), rememberPart: Binding<Bool> = .constant(false)) {
        self.fixedSavingsTotals = fixedSavingsTotals
        self.hint = hint; self.afterOverride = afterOverride; self.category = category; self.ledgerOverride = ledgerOverride
        self.allowsPartSelection = allowsPartSelection
        self.allowsRememberPart = allowsRememberPart
        _partID = partID; _rememberPart = rememberPart
    }
    private var part: SpendingPartHint? {
        if case .normal(_, _, _, let part) = hint { return part }
        return nil
    }
    private var amber: Bool {
        if fixedSavingsTotals != nil { return false }
        if let part, part.overBy > 0 { return true }
        if let afterOverride, afterOverride < 0 { return true }
        switch hint { case .restrain, .big: return true; case .normal(_, _, let over, _): return over }
    }
    private var selectionName: String? {
        if let part { return part.name }
        let ledger = ledgerOverride ?? store.current
        guard allowsPartSelection, !ledger.spendingParts.isEmpty else { return nil }
        var sample = Entry(amount: 0, accountID: UUID(), title: category, category: category)
        sample.partID = partID
        return SpendingParts.part(for: sample, in: ledger)?.name ?? "没分的"
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { labels; Spacer(minLength: 0); amount }
            VStack(alignment: .leading, spacing: 2) { labels; amount }
        }.padding(.leading, selectionName == nil ? 14 : 4).padding(.trailing, 14).frame(minHeight: 36)
            .background(amber ? YubaiColor.amberTint : YubaiColor.brandTint, in: Capsule())
            .foregroundStyle(amber ? YubaiColor.amberInk : YubaiColor.brandInk).accessibilityIdentifier("entrySavingHint")
            .sheet(isPresented: $pickingPart) {
                SpendingPartPicker(ledger: ledgerOverride ?? store.current, category: category, partID: $partID, remember: $rememberPart, allowsRemember: allowsRememberPart)
                    .environment(store)
            }
    }
    @ViewBuilder private var labels: some View {
        if fixedSavingsTotals != nil { Label("存着不动", systemImage: "lock").yubaiFont(YubaiFont.caption).fixedSize() }
        else if let selectionName {
            HStack(spacing: 8) {
                Button { pickingPart = true } label: {
                    HStack(spacing: 4) { Text(selectionName); Image(systemName: "chevron.down").font(.system(size: 10)) }
                        .padding(.horizontal, 10).frame(height: 28).background(YubaiColor.raised, in: Capsule())
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("花在哪一份，当前" + selectionName)
                    .accessibilityIdentifier("pickEntryPart")
                if let part { Text(part.overBy > 0 ? "记下后" : "记下后还剩") }
                else { priorityLabel }
            }.yubaiFont(YubaiFont.caption)
        } else { priorityLabel }
    }
    @ViewBuilder private var priorityLabel: some View {
        switch hint {
        case .normal, .big: Text("记下后还能花").yubaiFont(YubaiFont.caption)
        case .restrain(let title, let count, let limit, _):
            Text(title + " · 本周第 \(count) 次" + (limit.map { " · 你写的最多 \($0) 次" } ?? "")).yubaiFont(YubaiFont.caption)
        }
    }
    @ViewBuilder private var amount: some View {
        if let totals = fixedSavingsTotals {
            Text(store.preferences.hideAmounts ? "•••• → ••••" : Money.text(totals.current, currency: false) + " → " + Money.text(totals.new, currency: false))
                .yubaiFont(YubaiFont.amountSmall).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier("afterEntryFixedSavings")
        } else if let part {
            let total: Int64 = { if case .normal(let after, _, _, _) = hint { return afterOverride ?? after }; return 0 }()
            Text(store.preferences.hideAmounts ? "••••" : part.overBy > 0 ? "超 " + savingNumber(part.overBy) + " · 从没分的扣" :
                 Money.text(part.after, currency: false) + " · 共 " + Money.text(total, currency: false))
                .yubaiFont(YubaiFont.amountSmall, weight: .semibold).accessibilityIdentifier("afterEntryAvailable")
        } else {
            switch hint {
            case .normal(let after, let daily, _, _), .big(let after, let daily, _):
                let value = afterOverride ?? after
                let days = max(1, (Dates.calendar.dateComponents([.day], from: Dates.day(Date()), to: store.funds.cycleEnd).day ?? 0) + 1)
                let allowance = afterOverride == nil ? daily : max(0, value) / Int64(days)
                Text(store.preferences.hideAmounts ? "••••" : Money.text(value, currency: false) + " · 每天 " + savingDaily(allowance))
                    .yubaiFont(YubaiFont.amountSmall).accessibilityIdentifier("afterEntryAvailable")
            case .restrain(_, _, _, let spent):
                Text(store.preferences.hideAmounts ? "••••" : "这周 " + Money.text(spent, currency: false)).yubaiFont(YubaiFont.amountSmall)
            }
        }
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
                        ForEach(items) { slot in cell(slot).frame(width: 88) }
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: YubaiSpace.space8), count: 5), spacing: YubaiSpace.space8) {
                    ForEach(items) { slot in cell(slot) }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("分类")
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
    var allowsFuture = false
    @State private var picking = false
    @State private var latest = Date()
    private func day(_ offset: Int) -> Date { Dates.addDays(offset, to: Date()) }
    private func choose(_ day: Date) {
        let c = Dates.calendar
        date = c.date(bySettingHour: c.component(.hour, from: date), minute: c.component(.minute, from: date),
                      second: c.component(.second, from: date), of: day) ?? day
    }
    private var isStandard: Bool { [0, -1, -2].contains { Dates.calendar.isDate(date, inSameDayAs: day($0)) } }
    var body: some View {
        HStack(spacing: YubaiSpace.space8) {
            chip("今天", id: "entryDate_today", offset: 0)
            chip("昨天", id: "entryDate_yesterday", offset: -1)
            chip("前天", id: "entryDate_before", offset: -2)
            if !isStandard {
                Text(ManualBookkeeping.dayLabel(date)).yubaiFont(YubaiFont.callout, weight: .medium).fixedSize()
                    .foregroundStyle(YubaiColor.canvas).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: 34)
                    .background(YubaiColor.label, in: Capsule()).yubaiHitTarget()
                    .accessibilityAddTraits(.isSelected).accessibilityIdentifier("entryDate_other")
            }
        }.simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in latest = Date(); picking = true })
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "选别的日子") { latest = Date(); picking = true }
            .sheet(isPresented: $picking) { calendar }
    }
    private func chip(_ title: String, id: String, offset: Int) -> some View {
        let target = day(offset)
        let selected = Dates.calendar.isDate(date, inSameDayAs: target)
        return Button { choose(target) } label: {
            Text(title).yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular).fixedSize()
                .foregroundStyle(selected ? YubaiColor.canvas : YubaiColor.label)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: 34)
                .background(selected ? YubaiColor.label : YubaiColor.keyFn, in: Capsule())
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(id)
    }
    private var calendar: some View {
        VStack(alignment: .trailing, spacing: YubaiSpace.space8) {
            Button { picking = false } label: {
                Text("好").yubaiFont(YubaiFont.body, weight: .medium).foregroundStyle(YubaiColor.onBrand)
                    .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).background(YubaiColor.brand, in: Circle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("entryDateDone")
            if allowsFuture { DatePicker("日期", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden() }
            else { DatePicker("日期", selection: $date, in: ...latest, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden() }
            Spacer(minLength: YubaiSpace.none)
        }.padding(YubaiSpace.insetPage).yubaiSheetBackground()
            #if os(iOS)
            .presentationDetents([.medium]).presentationDragIndicator(.visible)
            #endif
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
        return Menu {
            ForEach(list) { item in
                Button(item.name + " · " + amount2(balances[item.id] ?? 0, hide: hide)) { selection.wrappedValue = item.id }
            }
        } label: {
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Text(account?.name ?? "选择账户").yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(balance).yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.labelSecondary)
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
    let recalls: [EntryHistory.Recall]
    let choose: (EntryHistory.Recall) -> Void
    var body: some View {
        VStack(spacing: YubaiSpace.space8) {
            ForEach(recalls) { item in
                Button { choose(item) } label: {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text(item.purpose).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).lineLimit(1)
                        Spacer(minLength: YubaiSpace.space8)
                        Text(Classification.displayCategory(item.entry.category)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        AmountLabel(cents: item.entry.amount, hide: store.preferences.hideAmounts, role: .summary).fixedSize()
                    }.padding(.horizontal, YubaiSpace.gapGroup).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble)
                        .background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                        .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("recentPurpose_" + item.purpose)
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("记过的用途")
    }
}

struct EntryAddedRow: Identifiable, Equatable {
    var id: UUID
    var title: String
    var category: String
    var amount: Int64
}

/// 补账时顶部列出刚补的几笔：「昨天 · 已记 2 笔」加合计，下面是每一笔。
struct EntryAddedList: View {
    @Environment(AppStore.self) private var store
    let dayTitle: String
    let rows: [EntryAddedRow]
    var body: some View {
        let hide = store.preferences.hideAmounts
        let total = rows.reduce(Int64(0)) { $0 + $1.amount }
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            HStack {
                Text(dayTitle + " · 已记 \(rows.count) 笔").yubaiFont(YubaiFont.caption, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                Spacer(minLength: YubaiSpace.space8)
                AmountLabel(cents: total, hide: hide, role: .small, sign: .outflow, ink: YubaiColor.labelSecondary)
            }.padding(.horizontal, YubaiSpace.space4)
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    ForEach(rows) { row in
                        HStack(spacing: YubaiSpace.gapGroup) {
                            Text(row.title).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                            Text(row.category).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).lineLimit(1)
                            Spacer(minLength: YubaiSpace.space8)
                            AmountLabel(cents: row.amount, hide: hide, role: .amount, sign: .outflow).fixedSize()
                        }.frame(minHeight: YubaiSize.rowSingle)
                        if row.id != rows.last?.id { EntryFormDivider() }
                    }
                }
            }
        }.accessibilityIdentifier("entryAddedList")
    }
}
