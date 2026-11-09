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
                NavigationStack {
                    Page(topPadding: YubaiSpace.space8) {
                        if allowsDirectionChange { Segmented(choices: [(false, "支出"), (true, "收入")], selection: $pickerIncome) }
                        CategoryPicker(income: pickerIncome, selected: suggestionOnly || pickerIncome != income ? nil : selection, suggested: pickerIncome == income ? suggested : nil,
                                       identifier: "entryMore", style: .sections) { choice, addition in
                            if let addition, !store.update("添加分类", { try addition.apply(to: &$0) }) { return false }
                            directionChanged(pickerIncome); choose(choice); picking = false; return true
                        }
                    }.accessibilityIdentifier("entryCategoryPicker").manualSheetNavigation()
                        .safeAreaInset(edge: .top) {
                            ManualSheetHeader(title: "分类", showsAction: false, cancelIdentifier: "entryMoreCancel", cancel: { picking = false }, action: {}).padding(.horizontal, 20)
                        }

                }.environment(store).appErrors().presentationDragIndicator(.visible).yubaiSheetBackground()
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
                Text((account?.name ?? emptyTitle ?? (optional ? "不指定" : "选择账户")) + (showsBalance && account != nil ? " · 余额 " + balanceText(account!.id) : "")).lineLimit(1)
            }.yubaiFont(YubaiFont.callout).fixedSize(horizontal: !inTray, vertical: true).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: inTray ? 34 : YubaiSize.chipHeight)
                .background(inTray ? YubaiColor.keyFn : YubaiColor.raised, in: Capsule())
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("账户")
            .accessibilityValue(accounts.first { $0.id == selection }?.name ?? emptyTitle ?? (optional ? "不指定" : "选择账户"))
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
    @ScaledMetric(relativeTo: .title2) private var keyHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var secondaryHeight: CGFloat = 46
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
                .padding(.horizontal, YubaiSpace.gapGroup).frame(height: inTray ? 34 : YubaiSize.chipHeight)
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
    let cancel: () -> Void
    let save: () -> Void
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            ManualSheetHeader(title: title, actionTitle: actionTitle, actionImage: actionImage, primary: primary,
                              showsAction: showsAction, enabled: enabled, actionIdentifier: actionIdentifier,
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
    var purposeIdentifier = "entryPurpose"
    var focus: FocusState<Bool>.Binding
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let keys: () -> Keys
    var body: some View {
        VStack(spacing: 0) {
            EntryPurposeWell(purpose: $purpose, identifier: purposeIdentifier, focus: focus).padding(.horizontal, 8).padding(.top, 10)
            controls().padding(.horizontal, 8).padding(.top, 8)
            if !focus.wrappedValue { keys() }
        }.padding(.bottom, focus.wrappedValue ? 8 : 0)
            .background { UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.card, topTrailingRadius: YubaiRadius.card).fill(YubaiColor.keypadTray).ignoresSafeArea(edges: .bottom) }
    }
}

struct EntrySavingHintBar: View {
    @Environment(AppStore.self) private var store
    let hint: EntryHint
    var afterOverride: Int64? = nil
    private var amber: Bool {
        if let afterOverride, afterOverride < 0 { return true }
        switch hint { case .restrain, .big: return true; case .normal(_, _, let over): return over }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { labels; Spacer(minLength: 0); amount }
            VStack(alignment: .leading, spacing: 2) { labels; amount }
        }.padding(.horizontal, 14).frame(minHeight: 36)
            .background(amber ? YubaiColor.amberTint : YubaiColor.brandTint, in: Capsule())
            .foregroundStyle(amber ? YubaiColor.amberInk : YubaiColor.brandInk).accessibilityIdentifier("entrySavingHint")
    }
    @ViewBuilder private var labels: some View {
        switch hint {
        case .normal, .big: Text("记下后还能花").yubaiFont(YubaiFont.caption)
        case .restrain(let title, let count, let limit, _):
            Text(title + " · 本周第 \(count) 次" + (limit.map { " · 你写的最多 \($0) 次" } ?? "")).yubaiFont(YubaiFont.caption)
        }
    }
    @ViewBuilder private var amount: some View {
        switch hint {
        case .normal(let after, let daily, _), .big(let after, let daily, _):
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
