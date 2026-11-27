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
                        // The rate card types on the sheet's keypad, so the sheet stays reachable under it.
                        .accessibilityHidden(model.categoryPanel || (model.drawer?.isPopover == true && model.drawer != .rate))
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
            .overlayPreferenceValue(EntryPillAnchors.self) { frames in
                if let drawer = model.drawer, drawer.isPopover, let anchor = frames.drawn[drawer] {
                    popover(drawer, anchor: anchor, pills: frames.hit, drawn: frames.drawn, keypad: frames.keypad)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            // The rate card types on the sheet's keypad: card and keypad are one modal, so VoiceOver reaches both.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(model.drawer == .rate ? .isModal : [])
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
                                      pills: [EntryDrawer: Anchor<CGRect>], drawn: [EntryDrawer: Anchor<CGRect>],
                                      keypad: Anchor<CGRect>?) -> some View {
        GeometryReader { geometry in
            let pill = geometry[anchor]
            let keys = keypad.map { geometry[$0] }
            let targets = pills.mapValues { geometry[$0] }
            let shapes = drawn.mapValues { geometry[$0] }
            // Spec-Type 弹出列表: at accessibility sizes the list takes the screen width less 16 a side.
            let width = typeSize.isAccessibilitySize ? geometry.size.width - DS.Space.s16 * 2
                : min(popoverWidth(drawer), geometry.size.width - DS.Space.s20 * 2)
            // Lists rise above their pill; 币种 and 汇率 hang under the amount.
            // The rate card stops above the keypad, which types the rate; at large type it scrolls instead.
            let floor = drawer == .rate ? keys.map(\.minY) ?? geometry.size.height : geometry.size.height
            let roomBelow = max(0, floor - pill.maxY - EntrySpec.popoverGap), roomAbove = max(0, pill.minY - EntrySpec.popoverGap)
            // A short screen at large type leaves no room under the rate line: the card rises above it instead.
            let below = drawer.opensBelow && !(drawer == .rate && roomBelow < EntrySpec.rateCardMinHeight && roomAbove > roomBelow)
            let available = below ? roomBelow : roomAbove
            let margin = typeSize.isAccessibilitySize ? DS.Space.s16 : DS.Space.s20
            let leading = min(max(margin, pill.midX - width * EntrySpec.midpoint),
                              geometry.size.width - margin - width)
            ZStack(alignment: .topLeading) {
                // A tap on another pill switches straight to its list; anywhere else closes this one.
                // The rate card's backdrop leaves the keypad free: the keypad types the rate.
                // It covers the safe areas too: a tap up by the status bar closes this list, not the whole sheet.
                let inset = geometry.safeAreaInsets
                Color.clear
                    .contentShape(EntryBackdropShape(hole: drawer == .rate ? keys?.offsetBy(dx: inset.leading, dy: inset.top) : nil), eoFill: true)
                    .onTapGesture(coordinateSpace: .named(EntrySpec.popoverSpace)) { location in
                        // Another pill (¥ included) opens at once; this one, or anywhere else, closes the list.
                        // Where two 44 pt targets overlap (the ≈ line's reaches up to ¥), the one drawn under the
                        // finger wins; between them, this list closes.
                        let hits = targets.filter { $0.value.contains(location) }.map(\.key)
                        let hit = hits.first { shapes[$0]?.contains(location) == true }
                            ?? (hits.contains(drawer) ? drawer : hits.first)
                        model.drawer = hit == drawer ? nil : hit
                    }
                    .gesture(closeDrag { model.drawer = nil })
                    .accessibilityHidden(true)
                    .ignoresSafeArea()
                ViewThatFits(in: .vertical) {
                    // Pulling down from a day or an account row closes the list too; the scrolling
                    // version (largest type) keeps the drag for its scroll.
                    popoverContent(drawer).simultaneousGesture(closeDrag { model.drawer = nil })
                    ScrollView { popoverContent(drawer) }.scrollIndicators(.hidden)
                }
                .frame(width: width, height: available, alignment: below ? .top : .bottom)
                .offset(x: leading, y: below ? pill.maxY + EntrySpec.popoverGap : 0)
                .transition(reduced ? .opacity : .scale(scale: EntrySpec.popoverScale, anchor: below ? .top : .bottom).combined(with: .opacity))
                .focusable()
                .focusEffectDisabled()
                .focused($calendarFocus, equals: .calendar)
                .onKeyPress(.escape) {
                    model.drawer = nil
                    return .handled
                }
                .accessibilityAddTraits(drawer == .rate ? [] : .isModal)
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
        case .currency: EntrySpec.currencyListWidth
        case .rate: EntrySpec.ratePopoverWidth
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
        case .currency:
            EntryCurrencyList(model: model, firstFocus: $listFocus)
        case .rate:
            EntryRatePopover(model: model, firstFocus: $listFocus)
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
            // macOS 14 cannot read the offset: never claim the top, so a drag always stays with the scroll.
            content.onAppear { formScroll.atTop = false }
        }
    }
}

/// Where each pill is drawn (its list pops out right above it) and where it takes a tap
/// (the 44 pt target, so a tap on the backdrop can switch straight to it).
struct EntryPillFrames {
    var drawn: [EntryDrawer: Anchor<CGRect>] = [:]
    var hit: [EntryDrawer: Anchor<CGRect>] = [:]
    /// The keypad tray: the rate card's backdrop leaves it free, because the keypad types the rate.
    var keypad: Anchor<CGRect>?
}

private struct EntryPillAnchors: PreferenceKey {
    static var defaultValue: EntryPillFrames { EntryPillFrames() }
    static func reduce(value: inout EntryPillFrames, nextValue: () -> EntryPillFrames) {
        let next = nextValue()
        value.drawn.merge(next.drawn) { $1 }
        value.hit.merge(next.hit) { $1 }
        value.keypad = next.keypad ?? value.keypad
    }
}

private extension View {
    /// Merged into what the subtree already reported: a plain `anchorPreference` would replace it,
    /// and the hit frame set outside a pill would erase the drawn frame set inside it.
    func entryAnchor(_ drawer: EntryDrawer) -> some View {
        transformAnchorPreference(key: EntryPillAnchors.self, value: .bounds) { $0.drawn[drawer] = $1 }
    }

    /// After the 44 pt frame: the whole target counts as the pill for the backdrop's switch.
    func entryHit(_ drawer: EntryDrawer) -> some View {
        transformAnchorPreference(key: EntryPillAnchors.self, value: .bounds) { $0.hit[drawer] = $1 }
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
        // With the rate card open the card and the keypad are the modal (set on the root); the form waits.
        .accessibilityAddTraits(model.drawer == .rate ? [] : .isModal)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.tab)
        .animation(reduced ? nil : DSMotion.smoothAnimation, value: model.drawer == .purpose)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.exception == .split)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.expression.isExpression)
    }

    private var form: some View {
        VStack(spacing: .zero) {
            EntryTopHeaderView(model: model)
            EntryAmountBlockView(model: model, pillFocus: pillFocus)
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
            if model.drawer == .split {
                EntryExpandedPanelView(model: model)
                    .padding(.horizontal, DS.Space.s20)
                    .padding(.bottom, DS.Space.s8)
            }
            if model.hasReceipt {
                EntryPill(title: "截图", icon: .screenshot, hint: "查看原始截图", action: receipt)
            }
        }
        .padding(.bottom, EntrySpec.aboveTray)
        .accessibilityHidden(model.drawer == .rate)
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
    let pillFocus: AccessibilityFocusState<EntryDrawer?>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.amountBlock)
        VStack(spacing: .zero) {
            HStack(spacing: DS.Space.s8) {
                Button { model.toggleDrawer(.currency) } label: {
                    HStack(spacing: EntrySpec.currencyGap) {
                        Text(model.draft.currency.symbol)
                            .dsText(DS.Font.tBody).fontWeight(.semibold).monospacedDigit()
                        DS.Icon.chevronDown.view(size: EntrySpec.currencyChevron, color: DS.Color.ink3)
                    }
                    .foregroundStyle(DS.Color.ink2)
                    .padding(.leading, EntrySpec.currencyInset)
                    .padding(.trailing, DS.Space.s8)
                    .frame(minHeight: EntrySpec.currencyHeight)
                    .dsPill(model.drawer == .currency ? DS.Color.selected : DS.Color.surface)
                    .entryAnchor(.currency)
                    .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .fixedSize()
                .entryHit(.currency)
                .accessibilityLabel("币种，" + model.draft.currency.unit)
                .accessibilityHint("选择币种")
                .accessibilityFocused(pillFocus, equals: .currency)
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
            // Above the ≈ line, whose 44 pt target reaches up into this row: the currency pill keeps its taps.
            .zIndex(1)
            if model.draft.expression.isExpression {
                Text(model.hidesAmounts ? "••••" : model.draft.expression.formattedDisplay + " = " + Money.text(model.money, currency: false))
                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
                    .frame(minHeight: DS.Space.s20)
                    .transition(.opacity)
            }
            if model.draft.currency != .cny {
                // 20 pt at the default size; grows with the type instead of spilling onto its neighbours.
                EntryRateLine(model: model)
                    .frame(minHeight: DS.Space.s20)
                    .accessibilityFocused(pillFocus, equals: .rate)
                    .modifier(EntryShake(trigger: model.ratePulse))
                    .transition(.opacity)
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
                                    suggested: model.draft.category == nil && model.shownSuggestion?.category == category.name) {
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
        .entryHit(drawer)
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
            .modifier(EntryOptionalAnchor(drawer: anchor, hit: true))
        }
        .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
        .accessibilityLabel(label ?? title ?? "")
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct EntryOptionalAnchor: ViewModifier {
    let drawer: EntryDrawer?
    var hit = false
    func body(content: Content) -> some View {
        if let drawer { if hit { content.entryHit(drawer) } else { content.entryAnchor(drawer) } } else { content }
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
        .entryHit(.more)
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

/// Spec-Currency 记一笔: 「≈ ¥21.68」 under a foreign amount — tap to change this entry's rate. With no rate
/// at all (never synced, none fixed) it is an amber 「填汇率」 and 记下 waits for it (X-entry-norate).
private struct EntryRateLine: View {
    let model: EntrySheetViewModel

    var body: some View {
        Button { model.toggleDrawer(.rate) } label: {
            if model.hasRate, let local = model.localMoney {
                HStack(spacing: DS.Space.s4) {
                    Text(model.hidesAmounts ? "≈ ••••" : "≈ " + Money.text(local)).dsText(DS.Font.tSub).monospacedDigit()
                        .foregroundStyle(DS.Color.ink3)
                    if model.typedRate != nil {
                        Text("手动汇率").dsText(SettingsSpec.tag).foregroundStyle(DS.Color.ink2).fixedSize()
                            .padding(.horizontal, SettingsSpec.tagInset).frame(minHeight: SettingsSpec.tagHeight).dsPill()
                    }
                    DS.Icon.chevron.view(size: EntrySpec.currencyChevron, color: DS.Color.chevron)
                }
                .entryAnchor(.rate)
                .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin)
            } else {
                Text("填汇率").dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.warnInk)
                    .padding(.horizontal, EntrySpec.rateFillInset).frame(minHeight: EntrySpec.rateFillHeight)
                    .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.warn, lineWidth: DS.Stroke.hairline))
                    .entryAnchor(.rate)
                    .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin)
            }
        }
        .buttonStyle(EntryTactileButtonStyle())
        .entryHit(.rate)
        .accessibilityLabel(model.hasRate ? "汇率" : "填汇率")
        .accessibilityValue(model.hasRate && !model.hidesAmounts ? "约 " + Money.text(model.localMoney ?? 0) : "")
        .accessibilityIdentifier("entryRateLine")
    }
}

/// Canvas S-Entry-Ccy: the nine currencies, the main one marked; picking closes the list.
private struct EntryCurrencyList: View {
    let model: EntrySheetViewModel
    let firstFocus: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        let main = model.ledger.preferences.mainCurrency ?? .cny
        let all = BillCurrency.allCases
        VStack(spacing: .zero) {
            ForEach(Array(all.enumerated()), id: \.element) { index, currency in
                Button { model.pickCurrency(currency) } label: {
                    HStack(spacing: .zero) {
                        Text(currency.symbol).dsText(DS.Font.tLabelStrong).monospacedDigit().foregroundStyle(DS.Color.ink2)
                            .fixedSize().padding(.trailing, DS.Space.s8).frame(minWidth: EntrySpec.currencySymbolColumn, alignment: .leading)
                        HStack(alignment: .firstTextBaseline, spacing: HomeSpec.gap6) {
                            Text(currency.unit).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink)
                            if currency == main {
                                Text("主币种").dsText(SettingsSpec.tag).foregroundStyle(DS.Color.ink3)
                            }
                        }.dsFillWidth()
                        DS.Icon.done.view(size: EntrySpec.checkIcon, color: DS.Color.accentInk)
                            .opacity(currency == model.draft.currency ? 1 : 0)
                    }
                    .padding(.horizontal, DS.Space.s16)
                    .frame(minHeight: EntrySpec.listRow)
                    .overlay(alignment: .bottom) {
                        if index < all.count - 1 {
                            DS.Color.separator.frame(height: DS.Stroke.hairline).padding(.leading, DS.Space.s16)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
                .accessibilityAddTraits(currency == model.draft.currency ? .isSelected : [])
                .accessibilityIdentifier("entryCurrency_" + currency.rawValue)
                .dsAccessibilityFocus(index == 0 ? firstFocus : nil)
            }
        }
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .dsShadow(DS.Shadow.float)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("币种")
    }
}

/// Canvas S-Entry-Rate: 「1 C$ = [5.1012] ¥」, where the rate comes from, and 用同步的 after typing one.
private struct EntryRatePopover: View {
    @Bindable var model: EntrySheetViewModel
    let firstFocus: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            HStack(spacing: DS.Space.s8) {
                Text("1 " + model.draft.currency.symbol + " =").dsText(DS.Font.tLabel).monospacedDigit().foregroundStyle(DS.Color.ink2)
                    .fixedSize()
                    .dsAccessibilityFocus(firstFocus)
                // Typed on the sheet's keypad. The rate in use shows quietly until one is typed (手动, this entry only).
                HStack(spacing: DS.Space.s4) {
                    Spacer(minLength: .zero)
                    Text(model.draft.exchangeRate.isEmpty ? (model.autoRate.map(CurrencySettings.rateText) ?? "0") : model.draft.exchangeRate)
                        .dsText(EntrySpec.rateField).monospacedDigit()
                        .foregroundStyle(model.draft.exchangeRate.isEmpty ? DS.Color.ink3 : DS.Color.ink)
                        .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
                    Capsule(style: .continuous).fill(DS.Color.accent)
                        .frame(width: EntrySpec.caretWidth, height: EntrySpec.rateCaret).accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("汇率")
                .accessibilityValue(model.draft.exchangeRate.isEmpty ? (model.autoRate.map(CurrencySettings.rateText) ?? "") : model.draft.exchangeRate)
                .accessibilityHint("用下方键盘输入")
                .padding(.horizontal, DS.Space.s12)
                .frame(minHeight: DS.Size.tapMin)
                .background(DS.Color.bg, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).strokeBorder(DS.Color.accent, lineWidth: DS.Stroke.focus))
                .accessibilityIdentifier("entryRateField")
                Text("¥").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2).fixedSize()
            }
            HStack(spacing: DS.Space.s8) {
                if !model.rateSource.isEmpty {
                    Text(model.rateSource).dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                }
                Spacer(minLength: .zero)
                if model.typedRate != nil, model.autoRate != nil {
                    Button { model.draft.exchangeRate = "" } label: {
                        Text(model.rateResetTitle).dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.accentInk)
                            .frame(minHeight: DS.Size.tapMin)
                    }.buttonStyle(EntryTactileButtonStyle()).accessibilityIdentifier("entryRateReset")
                }
            }
        }
        .padding(DS.Space.s16)
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .dsShadow(DS.Shadow.float)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("汇率")
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
            .transformAnchorPreference(key: EntryPillAnchors.self, value: .bounds) { $0.keypad = $1 }
            .padding(.bottom, safeBottom)
            .background(DS.Color.tray)
    }
}

/// The popover backdrop: everything, less an optional hole (the keypad under the rate card).
private struct EntryBackdropShape: Shape {
    let hole: CGRect?
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let hole { path.addRect(hole) }
        return path
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
    /// False once the sheet takes the drag: this press is void, no repeat and no release delete.
    @Environment(\.isEnabled) private var isEnabled
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
                    if withinKey && !didRepeat && isEnabled { configuration.trigger() }
                    withinKey = true
                    didRepeat = false
                })
            .onChange(of: isEnabled) { _, enabled in if !enabled { withinKey = false } }
            .onChange(of: fingerDown) { _, pressed in
                if pressed { didRepeat = false }
                else { withinKey = true }
            }
            .task(id: fingerDown && withinKey) {
                guard fingerDown, withinKey, isEnabled else { return }
                do {
                    try await Task.sleep(for: EntrySpec.backspaceDelay)
                    while !Task.isCancelled && isEnabled {
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
    /// The circles are scrolled to the top: a pull down there closes the panel rather than scrolling.
    @State private var scroll = EntryFormScroll()

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
            .modifier(EntryFormScrollTop(formScroll: $scroll))
            .simultaneousGesture(DragGesture(minimumDistance: EntrySpec.dragMinimum).onEnded { value in
                if confirm == nil, scroll.atTop, value.translation.height > abs(value.translation.width) {
                    model.dismissCategoryPanel()
                }
            })
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
    /// This category's icon in the open ledger (no two alike), else what its name or symbol means.
    var entryIcon: DS.Icon {
        CategoryIcons.current[DS.Icon.CategoryKey(name: name, income: income)] ?? DS.Icon(category: name, symbol: symbol, income: income, icon: icon)
    }
}
