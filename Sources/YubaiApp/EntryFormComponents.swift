import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct ManualSheetHeader: View {
    let title: String
    var actionTitle = "保存"
    var actionImage: String? = nil
    var primary = true
    var showsAction = true
    var enabled = true
    let cancel: () -> Void
    let action: () -> Void
    var body: some View {
        ZStack {
            Text(title).yubaiFont(YubaiFont.navTitle)
            HStack(spacing: YubaiSpace.gapGroup) {
                Button("取消", action: cancel).yubaiFont(YubaiFont.row)
                    .padding(.horizontal, YubaiSpace.insetCard).frame(height: YubaiSize.rowIcon).background(YubaiColor.card, in: Capsule())
                    .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("cancelManualSheet")
                Spacer()
                if showsAction { Button(action: action) {
                    HStack(spacing: YubaiSpace.space8) {
                        if let actionImage { Image(systemName: actionImage) }
                        Text(actionTitle)
                    }.yubaiFont(YubaiFont.row, weight: primary ? .medium : .regular)
                        .padding(.horizontal, YubaiSpace.gapGroup).frame(height: YubaiSize.rowIcon)
                        .foregroundStyle(primary ? YubaiColor.onBrand : YubaiColor.label)
                        .background(primary ? YubaiColor.brand : YubaiColor.card, in: Capsule())
                }.frame(minHeight: YubaiSize.tapMin).disabled(!enabled).opacity(enabled ? 1 : 0.5)
                    .accessibilityIdentifier(actionTitle == "导入" ? "importFromEntry" : "saveManualSheet")
                }
            }
        }.frame(height: YubaiSize.headerHeight).buttonStyle(PressButtonStyle())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let frequent: [String]
    let all: [String]
    @Binding var selection: String
    var didSelect: () -> Void = {}
    var limit = 5
    @State private var picking = false
    private var visible: [String] {
        var rows = Array(frequent.prefix(limit))
        if !rows.contains(selection), !selection.isEmpty {
            if rows.count == limit { rows.removeLast() }
            rows.append(selection)
        }
        return rows
    }
    var body: some View {
        EntryChipLayout {
            ForEach(visible, id: \.self) { name in
                Button { selection = name; didSelect() } label: {
                    Text(name).yubaiFont(YubaiFont.callout, weight: selection == name ? .medium : .regular)
                        .padding(.horizontal, YubaiSpace.gapGroup).frame(height: YubaiSize.chipHeight)
                        .background(selection == name ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
                        .overlay { if selection == name { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }
                        .yubaiHitTarget()
                }.chipSelection(selection == name).accessibilityAddTraits(selection == name ? .isSelected : [])
            }
            Button { picking = true } label: {
                Text("更多").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
                    .padding(.horizontal, YubaiSpace.gapGroup).frame(height: YubaiSize.chipHeight)
                    .overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: 1) }
                    .yubaiHitTarget()
            }
        }.buttonStyle(PressButtonStyle()).animation(YubaiMotion.control(reduceMotion: reduceMotion), value: selection)
            .sheet(isPresented: $picking) {
                NavigationStack {
                    List(all, id: \.self) { name in
                        Button { selection = name; didSelect(); picking = false } label: {
                            HStack(spacing: YubaiSpace.gapGroup) { Text(name); Spacer(); if name == selection { Image(systemName: "checkmark").foregroundStyle(YubaiColor.brandInk) } }.contentShape(Rectangle())
                        }.listRowBackground(YubaiColor.paperSheet)
                    }.scrollContentBackground(.hidden).navigationTitle("分类").yubaiNavigation()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { picking = false } } }
                }.presentationDragIndicator(.visible).yubaiSheetBackground()
            }
    }
}

struct EntryFormRow<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text(title).yubaiFont(YubaiFont.row).fixedSize()
            Spacer(minLength: YubaiSpace.none)
            content
        }.frame(minHeight: YubaiSize.rowSingle).yubaiFont(YubaiFont.row)
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
    var body: some View {
        Menu {
            if optional { Button("不指定") { selection = nil } }
            ForEach(accounts) { account in
                Button(account.name + " · 余额 " + balanceText(account.id)) { selection = account.id }
            }
        } label: {
            let account = accounts.first { $0.id == selection }
            Text((account?.name ?? emptyTitle ?? (optional ? "不指定" : "选择账户")) + (showsBalance && account != nil ? " · 余额 " + balanceText(account!.id) : ""))
                .yubaiFont(YubaiFont.callout).lineLimit(1).padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                .background(YubaiColor.raised, in: Capsule())
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("账户")
            .accessibilityValue(accounts.first { $0.id == selection }?.name ?? emptyTitle ?? (optional ? "不指定" : "选择账户"))
    }
    @Environment(AppStore.self) private var store
    private func balanceText(_ id: UUID) -> String {
        store.current.preferences.hideAmounts ? "••••" : AmountLabel.text(balances[id] ?? 0)
    }
}

struct EntryDateChip: View {
    @Binding var date: Date
    var time = false
    @State private var picking = false
    @State private var latestDate = Date()
    var body: some View {
        Button { latestDate = Date(); picking = true } label: {
            Text(time ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : ManualBookkeeping.dayLabel(date))
                .yubaiFont(time ? YubaiFont.amountSmall : YubaiFont.callout)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight).background(YubaiColor.raised, in: Capsule())
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).popover(isPresented: $picking) {
            VStack(spacing: YubaiSpace.gapGroup) {
                if time {
                    DatePicker("时间", selection: $date, in: ...latestDate, displayedComponents: .hourAndMinute).labelsHidden().frame(width: 240).fixedSize()
                } else {
                    DatePicker("日期", selection: $date, in: ...latestDate, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().frame(width: 320, height: 360).fixedSize()
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
    @State private var recent: [String] = []
    var body: some View {
        VStack(spacing: 0) {
            if !recent.isEmpty {
                SuggestionChips(values: recent, selected: selection, identifierPrefix: "recentPurpose_", singleLine: true) { selection = $0 }
                    .padding(.vertical, YubaiSpace.space8).accessibilityLabel("最近用过的用途")
            }
        }
        // Cache at the ledger boundary, never scan history on a keypad frame.
        .task(id: store.current.updatedAt) {
            recent = ManualBookkeeping.recentPurposes(sortedEntries: store.sortedEntries, categories: store.current.categories)
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
    @StateObject private var feedback = AmountKeypadFeedback()
    private let rows = [["1", "2", "3", "⌫"], ["4", "5", "6", "+"], ["7", "8", "9", "−"]]

    init(keypad: Binding<EntryKeypad>, amountSelected: Binding<Bool> = .constant(false), canSave: Bool,
         primaryTitle: String, primaryIdentifier: String, save: @escaping () -> Void, saveAnother: (() -> Void)? = nil) {
        _keypad = keypad; _amountSelected = amountSelected; self.canSave = canSave
        self.primaryTitle = primaryTitle; self.primaryIdentifier = primaryIdentifier; self.save = save; self.saveAnother = saveAnother
    }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let keyWidth = max(0, (geometry.size.width - 18) / 4)
                VStack(spacing: 6) {
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: 6) { ForEach(rows[row], id: \.self) { key in
                            AmountKeypadKey(key: key, keypad: $keypad, amountSelected: $amountSelected, feedback: feedback)
                                .frame(width: keyWidth)
                        } }
                    }
                    HStack(spacing: 6) {
                        AmountKeypadKey(key: ".", keypad: $keypad, amountSelected: $amountSelected, feedback: feedback)
                            .frame(width: keyWidth)
                        AmountKeypadKey(key: "0", keypad: $keypad, amountSelected: $amountSelected, feedback: feedback)
                            .frame(width: keyWidth)
                        Button(action: save) {
                            Text(primaryTitle).yubaiFont(YubaiFont.keypadAction)
                                .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity).frame(height: 52)
                        }.buttonStyle(AmountKeyButtonStyle(primary: true))
                            .frame(width: keyWidth * 2 + 6).opacity(canSave ? 1 : 0.4).disabled(!canSave)
                            .accessibilityIdentifier(primaryIdentifier)
                    }
                }
            }.frame(height: 52 * 4 + 6 * 3)
            if let saveAnother {
                Button("记下，再记一笔", action: saveAnother).yubaiFont(YubaiFont.body)
                    .foregroundStyle(YubaiColor.labelMuted).frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain).disabled(!canSave).accessibilityIdentifier("saveAndAddAnother")
            }
        }.padding(.horizontal, 8).padding(.top, 10).padding(.bottom, saveAnother == nil ? 8 : 0)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.card, topTrailingRadius: YubaiRadius.card)
                    .fill(YubaiColor.keypadTray).ignoresSafeArea(edges: .bottom)
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
    @State private var holdTask: Task<Void, Never>?
    @State private var clearedOnHold = false
    private var selected: Bool { keypad.pendingOperator == key }
    var body: some View {
        Button {
            guard !clearedOnHold else { return }
            keypad.press(key, replacingAmount: amountSelected); amountSelected = false
        } label: {
            Group {
                if key == "⌫" { Image(systemName: "delete.left") }
                else { Text(key) }
            }.yubaiFont(YubaiFont.amountAccount, weight: .regular)
                .frame(maxWidth: .infinity).frame(height: 52)
        }.buttonStyle(AmountKeyButtonStyle(function: ["⌫", "+", "−"].contains(key), selected: selected, pressing: pressChanged))
            .accessibilityLabel(key == "⌫" ? "删除一位" : key == "+" ? "加" : key == "−" ? "减" : key == "." ? "小数点" : key)
            .accessibilityIdentifier("keypad_" + key).accessibilityAddTraits(selected ? .isSelected : [])
            .onDisappear { holdTask?.cancel() }
    }
    private func pressChanged(_ pressed: Bool) {
        holdTask?.cancel()
        guard pressed else { return }
        clearedOnHold = false
        var next = keypad; next.press(key, replacingAmount: amountSelected)
        feedback.press(key, accepted: next != keypad)
        guard key == "⌫" else { return }
        holdTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled else { return }
            clearedOnHold = true; keypad.reset(); amountSelected = false; feedback.clear()
        }
    }
}

private struct AmountKeyButtonStyle: ButtonStyle {
    var primary = false
    var function = false
    var selected = false
    var pressing: (Bool) -> Void = { _ in }
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = primary ? (pressed ? YubaiColor.brandInk : YubaiColor.brand)
            : pressed ? (function ? YubaiColor.keyFnPressed : YubaiColor.keyPressed)
            : selected ? YubaiColor.brandTint : (function ? YubaiColor.keyFn : YubaiColor.key)
        return configuration.label
            .foregroundStyle(primary ? YubaiColor.onBrand : selected ? YubaiColor.brandInk : YubaiColor.label)
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
    #endif
    func prepare() {
        #if os(iOS)
        light.prepare(); medium.prepare(); rigid.prepare()
        #endif
    }
    func press(_ key: String, accepted: Bool) {
        #if os(iOS)
        if !accepted { rigid.impactOccurred(intensity: 0.5); rigid.prepare() }
        else if key == "+" || key == "−" { medium.impactOccurred(); medium.prepare() }
        else { light.impactOccurred(); light.prepare() }
        #endif
    }
    func clear() {
        #if os(iOS)
        medium.impactOccurred(); prepare()
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
                if presented, let expression = keypad.expressionText {
                    Text(expression).yubaiFont(YubaiFont.amount).foregroundStyle(YubaiColor.labelSecondary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                    Text(presented ? keypad.displayText : ((try? Money.parse(amount)).map { EntryKeypad(amount: $0).resultText } ?? "0.00"))
                        .yubaiFont(YubaiFont.amountDisplay).lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 6)
                        .background(selected ? YubaiColor.brandTint : .clear, in: RoundedRectangle(cornerRadius: 10))
                    Spacer(minLength: 0)
                }.frame(minHeight: YubaiSize.rowDouble)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(YubaiColor.label)
            .accessibilityLabel("金额").accessibilityValue(presented ? keypad.resultText : amount)
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
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(value + (opensPlan ? " ›" : "")).yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(height: YubaiSize.chipHeight)
                .background(selected ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
                .overlay { if selected { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("entryRepeat")
            .accessibilityLabel("重复").accessibilityValue(value).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
