import SwiftUI
import YubaiCore

enum EntryCalendarFocus: Hashable {
    case timePill, calendar
}

struct EntrySheetOverlay: View {
    let model: EntrySheetViewModel
    let onClose: () -> Void
    let onReceipt: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var motion: EntrySheetMotion
    @State private var displayedMonth: Date
    /// nil until a drag decides; true once the sheet took it over, false when it stays with the content.
    @State private var dragOwned: Bool?
    /// Goes false however the drag ends, including when the system cancels it without `onEnded`.
    @GestureState private var dragging = false
    @FocusState private var calendarFocus: EntryCalendarFocus?
    /// VoiceOver: the pill a list popped out of, so closing the list goes back to it.
    @AccessibilityFocusState private var pillFocus: EntryDrawer?
    /// VoiceOver: the first item of the open list.
    @AccessibilityFocusState private var listFocus: Bool
    /// Only the largest type sizes scroll the form; there a drag belongs to the scroll unless it is at the top.
    @State private var formScroll = EntryFormScroll()

    init(model: EntrySheetViewModel, onClose: @escaping () -> Void, onReceipt: @escaping () -> Void = {}) {
        self.model = model
        self.onClose = onClose
        self.onReceipt = onReceipt
        _motion = State(initialValue: EntrySheetMotion(settled: model.settled))
        _displayedMonth = State(initialValue: DSCalendarPopover.initialMonth(for: model.draft.date, now: model.now))
    }

    var body: some View {
        GeometryReader { geo in
            let bottom = geo.safeAreaInsets.bottom
            let maxHeight = geo.size.height + bottom
            ZStack(alignment: .bottom) {
                EntryScrimView(motion: motion, color: DS.Color.scrim, close: cancel)
                    .ignoresSafeArea()
                if model.drawer == .purpose {
                    // Spec-Redlines 写用途: the sheet's color runs on behind the system keyboard, no seam at its corners.
                    DS.Color.bg.frame(height: DS.Radius.sheet)
                        .offset(y: DS.Radius.sheet)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if model.categoryOnly {
                    EntryCategoryPanelView(model: model, safeBottom: bottom, maxHeight: maxHeight, confirm: save)
                        .modifier(EntrySheetPositionModifier(motion: motion, reduced: reduced, onClose: onClose, fill: DS.Color.bg))
                } else {
                    EntrySheetView(model: model, safeBottom: bottom, maxHeight: maxHeight,
                                   calendarFocus: $calendarFocus, pillFocus: $pillFocus, formScroll: $formScroll,
                                   save: save, receipt: onReceipt)
                        // Once the sheet owns the drag, the key under the finger lets go and the form stops scrolling.
                        // Applied outside the sheet's body, so only the controls see it; the drag below stays live.
                        .disabled(dragOwned == true)
                        // Spec-Gestures: alongside the keys and the scroll. The sheet decides by direction first.
                        .simultaneousGesture(sheetDrag, including: model.drawer == nil ? .all : .subviews)
                        .modifier(EntrySheetPositionModifier(motion: motion, reduced: reduced, onClose: onClose))
                        .accessibilityHidden(model.categoryPanel || model.drawer?.isPopover == true)
                }
                if model.categoryPanel && !model.categoryOnly {
                    DS.Color.scrim
                        .contentShape(Rectangle())
                        .onTapGesture { model.dismissCategoryPanel() }
                        .gesture(closeDrag { model.dismissCategoryPanel() })
                        .accessibilityHidden(true)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    EntryCategoryPanelView(model: model, safeBottom: bottom, maxHeight: maxHeight)
                        .transition(reduced ? .opacity : .move(edge: .bottom))
                }
                if model.managingCategories {
                    EntryCategoryManagerView(model: model, close: { model.managingCategories = false })
                        .transition(reduced ? .opacity : .move(edge: .trailing))
                        .zIndex(1)
                }
            }
            .overlayPreferenceValue(EntryPillAnchors.self) { anchors in
                if let drawer = model.drawer, drawer.isPopover, let anchor = anchors[drawer] {
                    popover(drawer, anchor: anchor, pills: anchors)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.snappyAnimation, value: model.drawer?.isPopover == true ? model.drawer : nil)
            .animation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.smoothAnimation, value: model.categoryPanel)
            .animation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.smoothAnimation, value: model.managingCategories)
        }
        .accessibilityAction(.escape) { closeTopLayer() }
        .onChange(of: dragging) { _, active in
            guard !active else { return }
            // Cleared here, after the touch is fully over, so the key under the finger stays disabled through its release.
            dragOwned = nil
            motion.settleIfDragging(reduced: reduced)
        }
        .onChange(of: model.drawer == .calendar) { wasOpen, isOpen in
            if wasOpen && !isOpen { calendarFocus = .timePill }
        }
        .onChange(of: model.drawer) { old, new in
            guard let old, old.isPopover, new?.isPopover != true else { return }
            pillFocus = old
        }
        .onAppear { model.schedulePreview() }
        .onChange(of: model.draft) { _, _ in model.schedulePreview() }
        .onChange(of: model.ledger.updatedAt) { _, _ in model.schedulePreview() }
        .onDisappear { model.cancelPreview() }
        .alert("这笔没有记下", isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })) {
            Button("好") { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
    }

    /// Spec-Gestures: one layer closes at a time — the list, then the panel, then the sheet.
    private func closeTopLayer() {
        if model.managingCategories { model.managingCategories = false }
        else if model.drawer?.isPopover == true { model.drawer = nil }
        else if model.categoryPanel && !model.categoryOnly { model.dismissCategoryPanel() }
        else { cancel() }
    }

    /// Spec-Gestures 记一笔 · 下拉收起: anywhere on the sheet, once it moves more down than across.
    /// The first 6 pt decide: across stays with the content; up or down takes the sheet, except in the
    /// scrolling form (largest type), where up, or down while not at the top, stays with the scroll.
    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: EntrySpec.dragMinimum, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                if dragOwned == nil {
                    let vertical = abs(value.translation.height) > abs(value.translation.width)
                    let down = value.translation.height > 0
                    let scrollKeeps = formScroll.scrolls && (!down || !formScroll.atTop)
                    dragOwned = vertical && !scrollKeeps && model.drawer == nil && !model.categoryPanel
                }
                if dragOwned == true { motion.drag(value) }
            }
            .onEnded { value in
                guard dragOwned == true else { return }
                if motion.willDismiss(value) { model.retainDraft() }
                motion.release(value, reduced: reduced, onClose: onClose)
            }
    }

    /// Spec-Gestures 一次关一层: pulling down on a list's or panel's backdrop closes that layer only.
    private func closeDrag(_ close: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: EntrySpec.dragMinimum).onEnded { value in
            if value.translation.height > abs(value.translation.width) { close() }
        }
    }

    @ViewBuilder private func popover(_ drawer: EntryDrawer, anchor: Anchor<CGRect>,
                                      pills: [EntryDrawer: Anchor<CGRect>]) -> some View {
        GeometryReader { geometry in
            let pill = geometry[anchor]
            let targets = pills.filter { $0.key.isPopover }.mapValues { geometry[$0] }
            // Spec-Type 弹出列表: at accessibility sizes the list takes the screen width less 16 a side.
            let width = typeSize.isAccessibilitySize ? geometry.size.width - DS.Space.s16 * 2
                : min(popoverWidth(drawer), geometry.size.width - DS.Space.s20 * 2)
            let available = max(0, pill.minY - EntrySpec.popoverGap)
            let margin = typeSize.isAccessibilitySize ? DS.Space.s16 : DS.Space.s20
            let leading = min(max(margin, pill.midX - width * EntrySpec.midpoint),
                              geometry.size.width - margin - width)
            ZStack(alignment: .topLeading) {
                // A tap on another pill switches straight to its list; anywhere else closes this one.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .named(EntrySpec.popoverSpace)) { location in
                        let hit = targets.first { $0.value.contains(location) }?.key
                        model.drawer = hit == drawer ? nil : hit
                    }
                    .gesture(closeDrag { model.drawer = nil })
                    .accessibilityHidden(true)
                    .ignoresSafeArea()
                ViewThatFits(in: .vertical) {
                    popoverContent(drawer)
                    ScrollView { popoverContent(drawer) }.scrollIndicators(.hidden)
                }
                .frame(width: width, height: available, alignment: .bottom)
                .offset(x: leading)
                .transition(reduced ? .opacity : .scale(scale: EntrySpec.popoverScale, anchor: .bottom).combined(with: .opacity))
                .focusable()
                .focusEffectDisabled()
                .focused($calendarFocus, equals: .calendar)
                .onKeyPress(.escape) {
                    model.drawer = nil
                    return .handled
                }
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { model.drawer = nil }
            }
        }
        .coordinateSpace(.named(EntrySpec.popoverSpace))
        // Per list, not per appearance: switching straight from one pill to another reuses this view.
        .task(id: drawer) {
            if drawer == .calendar { displayedMonth = DSCalendarPopover.initialMonth(for: model.draft.date, now: model.now) }
            calendarFocus = .calendar
            listFocus = true
        }
    }

    private func popoverWidth(_ drawer: EntryDrawer) -> CGFloat {
        switch drawer {
        case .calendar: EntrySpec.calendarWidth
        case .more: DS.Size.menuW
        default: EntrySpec.accountListWidth
        }
    }

    @ViewBuilder private func popoverContent(_ drawer: EntryDrawer) -> some View {
        switch drawer {
        case .calendar:
            DSCalendarPopover(date: model.draft.date, now: model.now, displayedMonth: $displayedMonth,
                              repeats: model.draft.repeatMonthly,
                              canRepeat: model.canRepeat && model.draft.exception == nil,
                              onSelect: model.setDate, onRepeat: model.toggleRepeat, titleFocus: $listFocus)
        case .source, .destination:
            EntryAccountList(model: model, destination: drawer == .destination, firstFocus: $listFocus)
        case .more:
            EntryMoreList(model: model, firstFocus: $listFocus)
        default:
            EmptyView()
        }
    }

    private func cancel() {
        guard !motion.closing else { return }
        model.retainDraft()
        motion.close(reduced: reduced, onClose: onClose)
    }

    private func save() {
        guard !motion.closing, model.save() else { return }
        motion.close(reduced: reduced, sealed: true, onClose: onClose)
    }
}

/// Whether the form is in its scrolling fallback (largest type) and scrolled to the top.
struct EntryFormScroll: Equatable {
    var scrolls = false
    var atTop = true
}

private struct EntryFormScrollTop: ViewModifier {
    @Binding var formScroll: EntryFormScroll

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top <= 1 } action: { _, top in
                formScroll.atTop = top
            }
        } else {
            content
        }
    }
}

/// Where each pill sits, so its list pops out right above it.
private struct EntryPillAnchors: PreferenceKey {
    static var defaultValue: [EntryDrawer: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [EntryDrawer: Anchor<CGRect>], nextValue: () -> [EntryDrawer: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func entryAnchor(_ drawer: EntryDrawer) -> some View {
        anchorPreference(key: EntryPillAnchors.self, value: .bounds) { [drawer: $0] }
    }
}

/// Spec-Motion 没分类按记下 / 金额 0 按记下: the row says where the problem is.
private struct EntryShake: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduced

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, x in
                view.offset(x: reduced ? .zero : x)
            } keyframes: { _ in
                SpringKeyframe(EntrySpec.shakeOffsets[0], duration: EntrySpec.shakeTimes[0], spring: DSMotion.standard)
                SpringKeyframe(EntrySpec.shakeOffsets[1], duration: EntrySpec.shakeTimes[1], spring: DSMotion.standard)
                SpringKeyframe(EntrySpec.shakeOffsets[2], duration: EntrySpec.shakeTimes[2], spring: DSMotion.standard)
                SpringKeyframe(EntrySpec.shakeOffsets[3], duration: EntrySpec.shakeTimes[3], spring: DSMotion.standard)
                SpringKeyframe(EntrySpec.shakeOffsets[4], duration: EntrySpec.shakeTimes[4], spring: DSMotion.standard)
                SpringKeyframe(EntrySpec.shakeOffsets[5], duration: EntrySpec.shakeTimes[5], spring: DSMotion.standard)
            }
            .sensoryFeedback(.warning, trigger: trigger)
    }
}

struct EntrySheetView: View {
    let model: EntrySheetViewModel
    let safeBottom: CGFloat
    let maxHeight: CGFloat
    let calendarFocus: FocusState<EntryCalendarFocus?>.Binding
    let pillFocus: AccessibilityFocusState<EntryDrawer?>.Binding
    @Binding var formScroll: EntryFormScroll
    let save: () -> Void
    let receipt: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.sheetBody)
        ViewThatFits(in: .vertical) {
            VStack(spacing: .zero) {
                form
                footer
            }
            VStack(spacing: .zero) {
                ScrollView { form }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .modifier(EntryFormScrollTop(formScroll: $formScroll))
                    .onAppear { formScroll.scrolls = true }
                    .onDisappear { formScroll = EntryFormScroll() }
                footer
            }
            .frame(maxHeight: maxHeight)
        }
        .background(DS.Color.bg)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.tab)
        .animation(reduced ? nil : DSMotion.smoothAnimation, value: model.drawer == .purpose)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.exception == .split)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.expression.isExpression)
    }

    private var form: some View {
        VStack(spacing: .zero) {
            EntryTopHeaderView(model: model)
            EntryAmountBlockView(model: model)
                .padding(.top, EntrySpec.amountTop)
                .padding(.horizontal, DS.Space.s20)
            typeBody
            EntryPillsRowView(model: model, calendarFocus: calendarFocus, pillFocus: pillFocus)
                .padding(.top, EntrySpec.pillsTop)
                .padding(.horizontal, DS.Space.s20)
            EntryEffectLineView(model: model)
                .padding(.horizontal, DS.Space.s20)
            if model.draft.exception == .split {
                EntryAACardView(model: model)
                    .padding(.horizontal, DS.Space.s20)
                    .padding(.bottom, DS.Space.s8)
            }
            if model.drawer == .currency || model.drawer == .split {
                EntryExpandedPanelView(model: model)
                    .padding(.horizontal, DS.Space.s20)
                    .padding(.bottom, DS.Space.s8)
            }
            if model.hasReceipt {
                EntryPill(title: "截图", icon: .screenshot, hint: "查看原始截图", action: receipt)
            }
        }
        .padding(.bottom, EntrySpec.aboveTray)
    }

    @ViewBuilder private var footer: some View {
        if model.hidesKeypad {
            // The keyboard is the bottom edge now; `safeBottom` already counts it.
            EmptyView()
        } else {
            EntryKeypadTrayView(model: model, safeBottom: safeBottom, save: save)
        }
    }

    @ViewBuilder private var typeBody: some View {
        if model.draft.isRoute {
            EntryTransferRouteView(model: model, pillFocus: pillFocus)
                .padding(.top, EntrySpec.routeTop)
                .padding(.horizontal, DS.Space.s20)
        } else {
            EntryCategoryRowView(model: model)
                .padding(.top, EntrySpec.categoryTop)
                .padding(.horizontal, EntrySpec.categoryInset)
        }
    }
}

struct EntryGrabber: View {
    var body: some View {
        Capsule(style: .continuous).fill(DS.Color.grabber)
            .frame(width: EntrySpec.grabberWidth, height: EntrySpec.grabberHeight)
            .padding(.top, DS.Space.s8)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// Spec-Redlines 类型标签: 支出 / 收入 / 转账, three 64 pt columns and a 16 × 3 underline.
struct EntryTopHeaderView: View {
    static let tabs: [EntryType] = [.expense, .income, .transfer]
    let model: EntrySheetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        VStack(spacing: .zero) {
            EntryGrabber()
            tabs.frame(minHeight: DS.Size.tapMin)
        }
    }

    private var tabs: some View {
        HStack(spacing: .zero) {
            ForEach(Self.tabs) { type in
                let selected = model.draft.tab == type
                Button {
                    withAnimation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.standardAnimation) { model.select(type) }
                } label: {
                    Text(type.title).dsText(DS.Font.tBody)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? DS.Color.ink : DS.Color.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(EntrySpec.amountMinimumScale)
                        .frame(minWidth: EntrySpec.tabColumn, minHeight: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
                .accessibilityHint("切换到\(type.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("entryNature_" + type.rawValue)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geo in
                let width = geo.size.width / CGFloat(Self.tabs.count)
                let index = Self.tabs.firstIndex(of: model.draft.tab) ?? 0
                Capsule(style: .continuous).fill(DS.Color.ink)
                    .frame(width: EntrySpec.thumbWidth, height: EntrySpec.thumbHeight)
                    .offset(x: width * (CGFloat(index) + EntrySpec.midpoint) - EntrySpec.thumbWidth * EntrySpec.midpoint)
                    .animation(reduced ? nil : DSMotion.smoothAnimation, value: index)
            }
            .frame(height: EntrySpec.thumbHeight)
            .padding(.bottom, EntrySpec.thumbInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("记账类型")
    }
}

/// Spec-Redlines 金额行 + ≈ 行 + 用途.
private struct EntryAmountBlockView: View {
    @Bindable var model: EntrySheetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.amountBlock)
        VStack(spacing: .zero) {
            HStack(spacing: DS.Space.s8) {
                Button { model.toggleDrawer(.currency) } label: {
                    HStack(spacing: EntrySpec.currencyGap) {
                        Text(model.draft.currency == .cny ? "¥" : model.draft.currency.rawValue)
                            .dsText(DS.Font.tBody).fontWeight(.semibold).monospacedDigit()
                        DS.Icon.chevronDown.view(size: EntrySpec.currencyChevron, color: DS.Color.ink3)
                    }
                    .foregroundStyle(DS.Color.ink2)
                    .padding(.leading, EntrySpec.currencyInset)
                    .padding(.trailing, DS.Space.s8)
                    .frame(minHeight: EntrySpec.currencyHeight)
                    .dsPill()
                    .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .fixedSize()
                .accessibilityLabel("币种，" + model.draft.currency.unit)
                .accessibilityHint("选择外币和汇率")
                Text(amountText)
                    .dsText(DS.Font.nEntry)
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(EntrySpec.amountMinimumScale)
                    .contentTransition(reduced ? .identity : .numericText())
                    .animation(reduced ? nil : DSMotion.standardAnimation, value: model.money)
                    .accessibilityLabel("金额")
                    .accessibilityValue(model.hidesAmounts ? "金额已隐藏" : model.draft.expression.formattedDisplay)
                    .accessibilityHint("用下方键盘输入")
                    .accessibilityIdentifier("entryKeypadAmount")
                EntryAmountCaretView(steady: model.settled || model.drawer == .purpose)
            }
            .frame(minHeight: EntrySpec.amountRow)
            .modifier(EntryShake(trigger: model.amountPulse))
            if model.draft.expression.isExpression {
                Text(model.hidesAmounts ? "••••" : model.draft.expression.formattedDisplay + " = " + Money.text(model.money, currency: false))
                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
                    .frame(height: DS.Space.s20)
                    .transition(.opacity)
            }
            if model.draft.currency != .cny, let rate = model.signedRate, let local = model.localMoney {
                Text(model.hidesAmounts ? "••••" : "≈ \(Money.text(local)) · 1 \(model.draft.currency.rawValue) = \(NSDecimalNumber(decimal: rate).stringValue)")
                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
                    .frame(height: DS.Space.s20)
            }
            purpose
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var purpose: some View {
        if model.drawer == .purpose {
            DSInlineTextField(title: "用途", text: $model.draft.purpose, icon: .edit) { model.drawer = nil }
                .submitLabel(.done)
                .accessibilityIdentifier("entryPurpose")
        } else {
            Button { model.toggleDrawer(.purpose) } label: {
                HStack(spacing: EntrySpec.gap) {
                    DS.Icon.edit.view(size: EntrySpec.purposeIcon, color: DS.Color.ink3)
                    Text(model.draft.purpose.isEmpty ? "用途" : model.draft.purpose)
                        .dsText(DS.Font.tBody)
                        .foregroundStyle(model.draft.purpose.isEmpty ? DS.Color.ink3 : DS.Color.ink2)
                        .lineLimit(1)
                }
                .frame(minHeight: EntrySpec.purposeHeight)
                .padding(.horizontal, DS.Space.s8)
            }
            .buttonStyle(EntryTactileButtonStyle())
            .frame(minHeight: EntrySpec.purposeHeight)
            .accessibilityLabel("用途")
            .accessibilityValue(model.draft.purpose)
            .accessibilityHint("填写这笔账的用途")
            .accessibilityIdentifier("entryPurpose")
        }
    }

    private var amountText: String {
        if model.hidesAmounts { return "••••" }
        let expression = model.draft.expression
        if expression.isExpression { return Money.text(model.money, currency: false) }
        return expression.isEmpty ? "0.00" : expression.formattedDisplay
    }

    private var amountColor: Color {
        if model.draft.expression.isEmpty { return DS.Color.chevron }
        return model.draft.type == .income ? DS.Color.accentInk : DS.Color.ink
    }
}

private struct EntryAmountCaretView: View {
    let steady: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.caret)
        Group {
            if steady || reduced {
                bar
            } else {
                TimelineView(.periodic(from: .now, by: EntrySpec.caretHalfPeriod)) { context in
                    let phase = Int(context.date.timeIntervalSinceReferenceDate / EntrySpec.caretHalfPeriod)
                    bar.opacity(phase.isMultiple(of: 2) ? 1 : 0)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var bar: some View {
        Capsule(style: .continuous).fill(DS.Color.accent)
            .frame(width: EntrySpec.caretWidth, height: EntrySpec.caretHeight)
    }
}

/// Spec-Redlines 分类行: five equal columns — four recent categories and 全部.
private struct EntryCategoryRowView: View {
    let model: EntrySheetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.categoryRow)
        let ring = model.needsCategory && model.draft.category == nil
        HStack(alignment: .top, spacing: .zero) {
            ForEach(model.topCategories) { category in
                let selected = category.name == model.draft.category
                EntryCategoryCircle(name: selected ? model.draft.subcategory ?? category.name : category.name,
                                    icon: category.entryIcon, selected: selected, ring: ring,
                                    suggested: model.draft.category == nil && model.suggestion?.category == category.name) {
                    withAnimation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.standardAnimation) {
                        model.toggle(category: category.name)
                    }
                }
                .accessibilityIdentifier("entryCategory_" + category.name)
            }
            EntryCategoryCircle(name: "全部", icon: .catAll, ring: ring, hint: "展开全部分类") { model.categoryPanel = true }
                .accessibilityIdentifier("entryCategoryMore")
        }
        .modifier(EntryShake(trigger: model.categoryPulse))
        .animation(reduced ? nil : DSMotion.standardAnimation, value: ring)
        .accessibilityElement(children: .contain)
        .accessibilityValue(ring ? "先选分类" : "")
    }
}

private struct EntryCategoryCircle: View {
    let name: String
    let icon: DS.Icon
    var selected = false
    var ring = false
    var suggested = false
    var hint = "选择分类"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: EntrySpec.gap) {
                icon.view(size: EntrySpec.categoryIcon, color: selected ? DS.Color.accentInk : DS.Color.ink2)
                    .frame(width: DS.Size.catCircle, height: DS.Size.catCircle)
                    .dsPill(selected ? DS.Color.accentSoft : DS.Color.surface)
                    .overlay {
                        if ring { Circle().strokeBorder(DS.Color.warn, lineWidth: DS.Stroke.focus) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if suggested && !selected {
                            Circle().fill(DS.Color.accent)
                                .frame(width: DS.Space.s8, height: DS.Space.s8)
                                .padding(EntrySpec.guessRing)
                                .background(DS.Color.bg, in: Circle())
                                .padding(max(0, EntrySpec.guessInset - EntrySpec.guessRing))
                        }
                    }
                Text(name).dsText(DS.Font.tCaption)
                    .foregroundStyle(selected ? DS.Color.accentInk : DS.Color.ink2)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(EntrySpec.amountMinimumScale)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
        .frame(maxWidth: .infinity)
        .accessibilityLabel(name)
        .accessibilityValue(suggested && !selected ? "建议" : "")
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Main.dc.html 从 / 到: two cards; 到 a savings account makes it 存入.
private struct EntryTransferRouteView: View {
    let model: EntrySheetViewModel
    let pillFocus: AccessibilityFocusState<EntryDrawer?>.Binding

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            card(destination: false)
            DS.Icon.arrowRight.view(size: EntrySpec.routeArrow, color: DS.Color.ink3)
                .frame(width: EntrySpec.routeArrowColumn)
                .accessibilityHidden(true)
            card(destination: true)
        }
    }

    private func card(destination: Bool) -> some View {
        let drawer: EntryDrawer = destination ? .destination : .source
        let account = model.account(destination ? model.draft.destinationID : model.draft.accountID)
        let title = account?.name ?? (destination ? "转入账户" : "转出账户")
        return Button { model.toggleDrawer(drawer) } label: {
            VStack(alignment: .leading, spacing: .zero) {
                Text(destination ? "到" : "从").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                HStack(spacing: EntrySpec.gap) {
                    (account?.kind.icon ?? .acctWallet).view(size: EntrySpec.pillIcon, color: DS.Color.ink2)
                    Text(title).dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.ink)
                        .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
                }
            }
            .padding(.horizontal, EntrySpec.pillInset)
            .frame(maxWidth: .infinity, minHeight: EntrySpec.routeCard, alignment: .leading)
            .background(model.drawer == drawer ? DS.Color.selected : DS.Color.surface,
                        in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
            .entryAnchor(drawer)
        }
        .buttonStyle(EntryTactileButtonStyle())
        .accessibilityFocused(pillFocus, equals: drawer)
        .accessibilityLabel((destination ? "到，" : "从，") + title)
        .accessibilityHint(destination ? "选择转入账户" : "选择转出账户")
    }
}

private struct EntryAACardView: View {
    let model: EntrySheetViewModel
    private var names: [String] { model.fixtureSplitNames.isEmpty ? ["我", "TA"] : model.fixtureSplitNames }

    var body: some View {
        Button { model.toggleDrawer(.split) } label: {
            HStack(spacing: EntrySpec.compactPadding) {
                HStack(spacing: EntrySpec.avatarOverlap) {
                    ForEach(names, id: \.self) { name in
                        let mine = name == "我"
                        Text(name).dsText(DS.Font.tCaption).fontWeight(.semibold)
                            .foregroundStyle(mine ? DS.Color.accentInk : DS.Color.ink2)
                            .frame(width: EntrySpec.avatarSize, height: EntrySpec.avatarSize)
                            .background(mine ? DS.Color.accentSoft : DS.Color.raised, in: Circle())
                            .overlay { Circle().strokeBorder(DS.Color.surface, lineWidth: EntrySpec.avatarBorder) }
                    }
                }
                .accessibilityHidden(true)
                Spacer(minLength: .zero)
                Text("我承担").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
                Text(model.hidesAmounts ? "••••" : Money.text(model.myShare, currency: false)).dsText(DS.Font.tLabelStrong)
                    .monospacedDigit().foregroundStyle(DS.Color.ink)
                    .minimumScaleFactor(EntrySpec.amountMinimumScale)
                DS.Icon.chevron.view(size: DS.Font.tCaption.size, color: DS.Color.chevron)
            }
            .lineLimit(1)
            .padding(.leading, EntrySpec.compactPadding)
            .padding(.trailing, EntrySpec.trailingPadding)
            .frame(minHeight: DS.Size.ctaH)
            .dsSurface(DS.Color.surface, radius: DS.Radius.m)
        }
        .buttonStyle(EntryTactileButtonStyle())
        .accessibilityLabel("我承担")
        .accessibilityValue(model.hidesAmounts ? "金额已隐藏" : Money.text(model.myShare))
        .accessibilityHint("平分金额或调整个人实付")
    }
}

/// Spec-Redlines 胶囊: 34 high, 14 each side, surface; the open one turns `selected`.
private struct EntryPill: View {
    let title: String?
    var icon: DS.Icon? = nil
    var suffix: String? = nil
    var selected = false
    var chevron = false
    var label: String? = nil
    var anchor: EntryDrawer? = nil
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EntrySpec.gap) {
                if let icon { icon.view(size: title == nil ? EntrySpec.moreIcon : EntrySpec.pillIcon, color: DS.Color.ink2) }
                if let title {
                    (Text(title) + Text(suffix ?? "").foregroundStyle(DS.Color.ink3))
                        .dsText(DS.Font.tPill).monospacedDigit()
                        .foregroundStyle(DS.Color.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(EntrySpec.amountMinimumScale)
                }
                if chevron { DS.Icon.chevronDown.view(size: EntrySpec.currencyChevron, color: DS.Color.ink3) }
            }
            .padding(.horizontal, title == nil ? .zero : EntrySpec.pillInset)
            .frame(minWidth: title == nil ? EntrySpec.moreWidth : nil, minHeight: DS.Size.pillH)
            .dsPill(selected ? DS.Color.selected : DS.Color.surface)
            .modifier(EntryOptionalAnchor(drawer: anchor))
            .padding(.vertical, EntrySpec.pillHitInset)
            .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin)
        }
        .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
        .accessibilityLabel(label ?? title ?? "")
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct EntryOptionalAnchor: ViewModifier {
    let drawer: EntryDrawer?
    func body(content: Content) -> some View {
        if let drawer { content.entryAnchor(drawer) } else { content }
    }
}

/// Main.dc.html 例外胶囊: 「待报销 ×」 — the label reopens the list, × clears it.
private struct EntryFlagPill: View {
    let title: String
    let pillFocus: AccessibilityFocusState<EntryDrawer?>.Binding
    let open: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: .zero) {
            Button(action: open) {
                Text(title).dsText(DS.Font.tPill).fontWeight(.semibold).foregroundStyle(DS.Color.warnInk)
                    .lineLimit(1)
                    .padding(.leading, EntrySpec.flagLeading).padding(.trailing, EntrySpec.flagGap)
                    .frame(minHeight: DS.Size.tapMin)
            }
            .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
            .accessibilityFocused(pillFocus, equals: .more)
            .accessibilityHint("换一个选项")
            Button(action: clear) {
                DS.Icon.close.view(size: EntrySpec.flagClearIcon, color: DS.Color.warnInk)
                    .frame(width: EntrySpec.flagClear, height: DS.Size.tapMin)
            }
            .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
            .accessibilityLabel("去掉" + title)
        }
        .frame(height: DS.Size.pillH)
        .background(DS.Color.warnSoft, in: DS.Shape.pill)
        .entryAnchor(.more)
        .frame(minHeight: DS.Size.tapMin)
    }
}

private struct EntryPillsRowView: View {
    let model: EntrySheetViewModel
    let calendarFocus: FocusState<EntryCalendarFocus?>.Binding
    let pillFocus: AccessibilityFocusState<EntryDrawer?>.Binding

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.pillsRow)
        FlowLayout {
            if !model.draft.isRoute {
                let account = model.account(model.draft.accountID)
                EntryPill(title: account?.name ?? "账户", icon: account?.kind.icon ?? .acctWallet,
                          selected: model.drawer == .source, chevron: true, anchor: .source,
                          hint: "选择这笔账的账户") { model.toggleDrawer(.source) }
                    .accessibilityFocused(pillFocus, equals: .source)
                    .accessibilityIdentifier("entryAccountPill")
            }
            EntryPill(title: model.dayLabel, icon: .time, suffix: model.draft.repeatMonthly ? " · 每月" : nil,
                      selected: model.drawer == .calendar, chevron: true, anchor: .calendar,
                      hint: model.drawer == .calendar ? "收起日历" : "选择日期和重复选项") { model.toggleDrawer(.calendar) }
                .focused(calendarFocus, equals: .timePill)
                .accessibilityFocused(pillFocus, equals: .calendar)
                .accessibilityIdentifier("entryTimePill")
            if let flag = flagTitle {
                EntryFlagPill(title: flag, pillFocus: pillFocus, open: { model.toggleDrawer(.more) }, clear: clearFlag)
            } else if hasMore {
                EntryPill(title: nil, icon: .more, selected: model.drawer == .more, label: "更多选项", anchor: .more,
                          hint: "列出全部选项") { model.toggleDrawer(.more) }
                    .accessibilityFocused(pillFocus, equals: .more)
                    .accessibilityIdentifier("entryMorePill")
            }
        }
    }

    private var hasMore: Bool {
        model.draft.type == .expense || (model.draft.type == .income && model.draft.originalNature == nil)
    }

    private var flagTitle: String? {
        if model.draft.type == .expense { return model.draft.exception?.title }
        if model.draft.type == .income && model.draft.incomeNextCycle { return EntryMoreList.nextCycle }
        return nil
    }

    private func clearFlag() {
        if model.draft.type == .income { model.draft.incomeNextCycle = false } else { model.clearException() }
    }
}

/// Spec-Redlines 弹出列表 · 账户: name, balance, a check on the current one. Picking closes it.
private struct EntryAccountList: View {
    let model: EntrySheetViewModel
    let destination: Bool
    let firstFocus: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        let accounts = model.accounts(destination: destination)
        let selectedID = destination ? model.draft.destinationID : model.draft.accountID
        VStack(spacing: .zero) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                Button { model.selectAccount(account.id, destination: destination) } label: {
                    HStack(spacing: DS.Space.s12) {
                        account.kind.icon.view(size: DS.Size.icon, color: DS.Color.iconQuiet)
                        Text(account.name).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink)
                            .lineLimit(1).dsFillWidth()
                        Text(model.hidesAmounts ? "••••" : Money.text(Finance.balance(account, in: model.ledger, at: model.now), currency: false))
                            .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3).fixedSize()
                        DS.Icon.done.view(size: EntrySpec.checkIcon, color: DS.Color.accentInk)
                            .opacity(account.id == selectedID ? 1 : 0)
                    }
                    .padding(.horizontal, DS.Space.s16)
                    .frame(minHeight: EntrySpec.accountRow)
                    .overlay(alignment: .bottom) {
                        if index < accounts.count - 1 {
                            DS.Color.separator.frame(height: DS.Stroke.hairline)
                                .padding(.leading, DS.Size.icon + DS.Space.s12)
                                .padding(.leading, DS.Space.s16)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
                .accessibilityAddTraits(account.id == selectedID ? .isSelected : [])
                .dsAccessibilityFocus(index == 0 ? firstFocus : nil)
            }
        }
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .dsShadow(DS.Shadow.float)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(destination ? "转入账户" : "账户")
    }
}

/// Spec-Redlines 弹出列表 · ···: every option at once, the current one checked.
private struct EntryMoreList: View {
    static let nextCycle = "计入下周期"
    let model: EntrySheetViewModel
    let firstFocus: AccessibilityFocusState<Bool>.Binding

    private struct Option: Identifiable {
        let id: String
        let icon: DS.Icon
        let selected: Bool
        let pick: () -> Void
    }

    private var options: [Option] {
        if model.draft.type == .income {
            return [Option(id: Self.nextCycle, icon: .cycle, selected: model.draft.incomeNextCycle) {
                model.draft.incomeNextCycle.toggle()
                model.drawer = nil
            }]
        }
        let icons: [EntryException: DS.Icon] = [.reserve: .saveFirst, .reimbursement: .reimburse, .split: .split]
        return EntryException.allCases.map { exception in
            Option(id: exception.title, icon: icons[exception] ?? .more, selected: model.draft.exception == exception) {
                model.choose(exception)
            }
        }
    }

    var body: some View {
        let options = options
        VStack(spacing: .zero) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button(action: option.pick) {
                    HStack(spacing: DS.Space.s12) {
                        option.icon.view(size: EntrySpec.checkIcon, color: DS.Color.ink2)
                        Text(option.id).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink).dsFillWidth()
                        DS.Icon.done.view(size: EntrySpec.checkIcon, color: DS.Color.accentInk)
                            .opacity(option.selected ? 1 : 0)
                    }
                    .padding(.horizontal, DS.Space.s16)
                    .frame(minHeight: EntrySpec.listRow)
                    .overlay(alignment: .bottom) {
                        if index < options.count - 1 {
                            DS.Color.separator.frame(height: DS.Stroke.hairline)
                                .padding(.leading, DS.Size.icon + DS.Space.s12)
                                .padding(.leading, DS.Space.s16)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
                .accessibilityAddTraits(option.selected ? .isSelected : [])
                .accessibilityIdentifier("entryMore_" + option.id)
                .dsAccessibilityFocus(index == 0 ? firstFocus : nil)
            }
        }
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .dsShadow(DS.Shadow.float)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("更多选项")
    }
}

private struct EntryExpandedPanelView: View {
    @Bindable var model: EntrySheetViewModel

    var body: some View {
        Group {
            switch model.drawer {
            case .currency:
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    Text("外币").dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    FlowLayout(centered: false) {
                        ForEach(BillCurrency.allCases) { currency in
                            EntryPill(title: currency.rawValue, selected: currency == model.draft.currency,
                                      label: currency.unit, hint: "切换记账币种") {
                                if model.draft.currency != currency { model.draft.exchangeRate = "" }
                                model.draft.currency = currency
                                if currency == .cny { model.drawer = nil }
                            }
                        }
                    }
                    if model.draft.currency != .cny {
                        HStack(spacing: DS.Space.s8) {
                            Text("汇率").dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink2)
                            DSInlineTextField(title: "汇率", text: $model.draft.exchangeRate, decimal: true,
                                              autoFocus: false) { model.drawer = nil }
                            EntryPill(title: nil, icon: .done, label: "完成汇率", hint: "保留币种和汇率") {
                                model.drawer = nil
                            }
                        }
                    }
                }
            case .split:
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    HStack {
                        Text("总金额").dsText(DS.Font.tPill)
                        Spacer()
                        Text(model.hidesAmounts ? "••••" : Money.text(model.localMoney ?? 0)).dsText(DS.Font.tLabelStrong).monospacedDigit()
                        EntryPill(title: "平分", hint: "按\(model.splitCount) 人平均计算") {
                            model.draft.personalShare = ""
                            model.drawer = nil
                        }
                    }
                    HStack {
                        Text("个人实付").dsText(DS.Font.tPill)
                        DSInlineTextField(title: "个人实付", text: $model.draft.personalShare, decimal: true,
                                          autoFocus: false, secure: model.hidesAmounts) { model.drawer = nil }
                        EntryPill(title: nil, icon: .done, label: "完成分摊", hint: "保留个人实付") { model.drawer = nil }
                    }
                }
                .foregroundStyle(DS.Color.ink)
            default: EmptyView()
            }
        }
    }
}

/// Spec-Redlines 副作用行: 30 high when there is one, otherwise nothing.
private struct EntryEffectLineView: View {
    let model: EntrySheetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.effectLine)
        Group {
            if let deposited = model.depositedThisCycle {
                Text(model.hidesAmounts ? "算作存入" : "算作存入 · 本期已存 " + Money.text(deposited, currency: false))
                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: EntrySpec.effectHeight)
                    .transition(.opacity)
            } else if let effect = model.effect {
                DSEffectLine(effect: effect, hidesAmount: model.hidesAmounts)
                    .frame(minHeight: EntrySpec.effectHeight)
                    .transition(.opacity)
            }
        }
        .animation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.standardAnimation, value: model.effect != nil || model.depositedThisCycle != nil)
    }
}

private struct EntryKeypadTrayView: View {
    let model: EntrySheetViewModel
    let safeBottom: CGFloat
    let save: () -> Void
    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.keypad)
        DSKeypad(saveReady: model.canSave, onKey: model.pressAmountKey, onSave: save)
            .padding(.bottom, safeBottom)
            .background(DS.Color.tray)
    }
}

struct DSKeypad: View {
    enum Variant { case entry, digits }
    var pressedKey: String?
    var canSave = true
    /// When set, 记下 always answers: ready shows accent, not ready shows the quiet key and the press explains why.
    var saveReady: Bool? = nil
    var onKey: (String) -> Void = { _ in }
    var variant: Variant = .entry
    var onSave: () -> Void = {}
    private var keys: [String] {
        switch variant {
        case .entry: ["1", "2", "3", "⌫", "4", "5", "6", "+", "7", "8", "9", "−", ".", "0", "00", "记下"]
        case .digits: ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"]
        }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s8), count: variant == .entry ? DSLayout.keypadColumns : DSLayout.digitKeypadColumns), spacing: DS.Space.s8) {
            ForEach(keys, id: \.self) { key in
                if key == "⌫" {
                    EntryBackspaceKey { onKey(key) }
                } else {
                    Button {
                        if key == "记下" { onSave() } else { onKey(key) }
                    } label: {
                        EntryKeyLabel(key: key, ready: saveReady ?? true).scaleEffect(key == pressedKey ? DSMotion.Press.scale : 1)
                    }
                    .buttonStyle(EntryTactileButtonStyle())
                    .accessibilityLabel(spoken(key))
                    .accessibilityHint(key == "记下" ? "保存并关闭录入面板" : "输入" + spoken(key))
                    .accessibilityIdentifier(key == "记下" ? "saveQuickEntry" : "keypad_" + (key == "−" ? "-" : key))
                    .disabled(key == "记下" && saveReady == nil && !canSave)
                }
            }
        }
        .padding(DS.Space.s8)
        .background(DS.Color.tray)
    }

    private func spoken(_ key: String) -> String {
        switch key {
        case "记下": "记下这一笔"
        case "+": "加"
        case "−": "减"
        case ".": "小数点"
        case "00": "两个零"
        default: key
        }
    }
}

private struct EntryBackspaceKey: View {
    let remove: () -> Void

    var body: some View {
        Button(action: remove) { EntryKeyLabel(key: "⌫") }
            .buttonStyle(EntryBackspaceStyle())
            .accessibilityLabel("删除")
            .accessibilityHint("删除最后一位，按住连续删除")
            .accessibilityIdentifier("keypad_⌫")
    }
}

private struct EntryBackspaceStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        EntryBackspacePress(configuration: configuration)
    }
}

private struct EntryBackspacePress: View {
    let configuration: PrimitiveButtonStyle.Configuration
    @GestureState private var fingerDown = false
    @State private var withinKey = true
    @State private var didRepeat = false

    var body: some View {
        configuration.label
            .modifier(EntryPressEffect(pressed: fingerDown && withinKey, haptic: DSMotion.Press.haptic))
            .gesture(DragGesture(minimumDistance: .zero)
                .updating($fingerDown) { _, pressed, _ in pressed = true }
                .onChanged { value in
                    let travel = hypot(value.translation.width, value.translation.height)
                    if travel > EntrySpec.keyHoldTravel { withinKey = false }
                }
                .onEnded { _ in
                    if withinKey && !didRepeat { configuration.trigger() }
                    withinKey = true
                    didRepeat = false
                })
            .onChange(of: fingerDown) { _, pressed in
                if pressed { didRepeat = false }
                else { withinKey = true }
            }
            .task(id: fingerDown && withinKey) {
                guard fingerDown, withinKey else { return }
                do {
                    try await Task.sleep(for: EntrySpec.backspaceDelay)
                    while !Task.isCancelled {
                        didRepeat = true
                        configuration.trigger()
                        try await Task.sleep(for: EntrySpec.backspaceInterval)
                    }
                } catch {}
            }
            .accessibilityAction { configuration.trigger() }
    }
}

private struct EntryKeyLabel: View {
    let key: String
    var ready = true
    private var isSave: Bool { key == "记下" }
    private var fill: Color {
        if isSave { return ready ? DS.Color.accent : DS.Color.keyFn }
        return ["⌫", "+", "−"].contains(key) ? DS.Color.keyFn : DS.Color.key
    }

    var body: some View {
        Group {
            if key == "⌫" {
                DS.Icon.backspace.view(size: EntrySpec.backspaceIcon, color: DS.Color.ink)
            } else {
                Text(key).dsText(isSave ? DS.Font.tTitle : DS.Font.nKey)
                    .foregroundStyle(isSave ? (ready ? DS.Color.onAccent : DS.Color.ink3) : DS.Color.ink)
                    .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DS.Size.keyH)
        .dsSurface(fill, radius: DS.Radius.s)
        .dsShadow(DS.Shadow.key)
        .animation(DSMotion.standardAnimation, value: ready)
    }
}

/// Main.dc.html 全部分类: only for picking. A category with subcategories opens them in place;
/// 编辑 › pushes 分类管理.
struct EntryCategoryPanelView: View {
    @Bindable var model: EntrySheetViewModel
    let safeBottom: CGFloat
    let maxHeight: CGFloat
    var confirm: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.categoryPanel)
        let rows = stride(from: 0, to: model.categories.count, by: EntrySpec.categoryColumns).map {
            Array(model.categories[$0..<min($0 + EntrySpec.categoryColumns, model.categories.count)])
        }
        VStack(spacing: .zero) {
            EntryGrabber()
            HStack {
                Text("分类").dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { model.managingCategories = true } label: {
                    HStack(spacing: DS.Space.s4) {
                        Text("编辑").dsText(DS.Font.tLabelStrong)
                        DS.Icon.chevron.view(size: EntrySpec.flagClearIcon, color: DS.Color.accentInk)
                    }
                    .foregroundStyle(DS.Color.accentInk)
                    .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin, alignment: .trailing)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .accessibilityIdentifier("entryCategoryManage")
            }
            .frame(height: EntrySpec.panelHeader)
            .padding(.horizontal, DS.Space.s20)
            .contentShape(Rectangle())
            // Pulling the panel's top down closes the panel only; the sheet under it stays.
            .gesture(DragGesture(minimumDistance: EntrySpec.dragMinimum).onEnded { value in
                if confirm == nil, value.translation.height > abs(value.translation.width) { model.dismissCategoryPanel() }
            })
            ScrollView {
                VStack(spacing: .zero) {
                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        HStack(alignment: .top, spacing: .zero) {
                            ForEach(row) { category in
                                EntryCategoryCircle(name: category.name, icon: category.entryIcon,
                                                    selected: model.draft.category == category.name) { pick(category) }
                            }
                            ForEach(row.count..<EntrySpec.categoryColumns, id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: DS.Stroke.hairline).accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, EntrySpec.panelRowInset)
                        .padding(.horizontal, EntrySpec.categoryInset)
                        if let open = row.first(where: { $0.name == model.expandedCategory }) {
                            chips(open)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .padding(.bottom, safeBottom + DS.Space.s8)
        }
        .frame(maxHeight: min(maxHeight, EntrySpec.categoryPanelHeight), alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(DS.Color.bg)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous))
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.expandedCategory)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("entryCategoryPicker")
        .accessibilityAction(.escape) {
            if confirm == nil { model.dismissCategoryPanel() }
        }
        .onKeyPress(.escape) {
            guard confirm == nil else { return .ignored }
            model.dismissCategoryPanel()
            return .handled
        }
    }

    private func pick(_ category: YubaiCore.Category) {
        model.pickInPanel(category)
        if category.subcategories.isEmpty { confirm?() }
    }

    private func chips(_ category: YubaiCore.Category) -> some View {
        FlowLayout(centered: false) {
            chip("不分小类", selected: model.draft.category == category.name && model.draft.subcategory == nil) {
                model.pickInPanel(category.name, subcategory: nil)
                confirm?()
            }
            ForEach(category.subcategories, id: \.self) { name in
                chip(name, selected: model.draft.category == category.name && model.draft.subcategory == name) {
                    model.pickInPanel(category.name, subcategory: name)
                    confirm?()
                }
            }
        }
        .padding(DS.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .padding(.horizontal, EntrySpec.panelChipsMargin)
        .padding(.top, EntrySpec.panelChipsTop)
        .padding(.bottom, EntrySpec.panelBottom)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).dsText(DS.Font.tPill)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? DS.Color.accentInk : DS.Color.ink2)
                .fixedSize()
                .padding(.horizontal, EntrySpec.panelChipInset)
                .frame(height: DS.Size.chipH)
                .dsPill(selected ? DS.Color.accentSoft : DS.Color.surface)
                .frame(minHeight: DS.Size.tapMin)
        }
        .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FlowLayout: Layout {
    var centered = true

    private struct Row {
        var cells: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height }
        let gaps = DS.Space.s8 * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height + gaps)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = centered ? bounds.midX - row.width * EntrySpec.midpoint : bounds.minX
            for cell in row.cells {
                subviews[cell.index].place(at: CGPoint(x: x, y: y + (row.height - cell.size.height) * EntrySpec.midpoint),
                                           anchor: .topLeading, proposal: ProposedViewSize(cell.size))
                x += cell.size.width + DS.Space.s8
            }
            y += row.height + DS.Space.s8
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: min(width, ideal.width), height: nil))
            if !row.cells.isEmpty && row.width + DS.Space.s8 + size.width > width {
                rows.append(row)
                row = Row()
            }
            if !row.cells.isEmpty { row.width += DS.Space.s8 }
            row.cells.append((index, size))
            row.width += size.width
            row.height = max(row.height, size.height)
        }
        if !row.cells.isEmpty { rows.append(row) }
        return rows
    }
}

extension YubaiCore.Category {
    var entryIcon: DS.Icon { DS.Icon(category: name, symbol: symbol, income: income) }
}
