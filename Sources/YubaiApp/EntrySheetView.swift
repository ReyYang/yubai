import SwiftUI
import YubaiCore

struct EntrySheetOverlay: View {
    let model: EntrySheetViewModel
    let onClose: () -> Void
    let onReceipt: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var motion: EntrySheetMotion

    init(model: EntrySheetViewModel, onClose: @escaping () -> Void, onReceipt: @escaping () -> Void = {}) {
        self.model = model
        self.onClose = onClose
        self.onReceipt = onReceipt
        _motion = State(initialValue: EntrySheetMotion(settled: model.settled))
    }

    var body: some View {
        GeometryReader { geo in
            let bottom = geo.safeAreaInsets.bottom
            let maxHeight = geo.size.height + bottom
            ZStack(alignment: .bottom) {
                EntryScrimView(motion: motion, color: DS.Color.scrim, close: cancel)
                    .ignoresSafeArea()
                EntrySheetView(model: model, safeBottom: bottom, maxHeight: maxHeight,
                               drag: drag, close: cancel, save: save, receipt: onReceipt)
                    .modifier(EntrySheetPositionModifier(motion: motion, reduced: reduced, onClose: onClose))
                    .accessibilityHidden(model.categoryPanel)
                if model.categoryPanel {
                    DS.Color.scrim
                        .contentShape(Rectangle())
                        .onTapGesture { model.dismissCategoryPanel() }
                        .accessibilityHidden(true)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    EntryCategoryPanelView(model: model, safeBottom: bottom, maxHeight: maxHeight)
                        .transition(reduced ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.smoothAnimation, value: model.categoryPanel)
        }
        .accessibilityAction(.escape) {
            if model.categoryPanel { model.dismissCategoryPanel() } else { cancel() }
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

    private var drag: EntryHeaderDrag {
        EntryHeaderDrag(move: { motion.drag($0) }, end: { value in
            if motion.willDismiss(value) { model.retainDraft() }
            motion.release(value, reduced: reduced, onClose: onClose)
        })
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

struct EntryHeaderDrag {
    let move: (DragGesture.Value) -> Void
    let end: (DragGesture.Value) -> Void
}

struct EntrySheetView: View {
    let model: EntrySheetViewModel
    let safeBottom: CGFloat
    let maxHeight: CGFloat
    let drag: EntryHeaderDrag
    let close: () -> Void
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
                footer
            }
            .frame(maxHeight: maxHeight)
        }
        .background(DS.Color.bg)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.type)
        .animation(reduced ? nil : DSMotion.smoothAnimation, value: model.drawer)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.category != nil)
        .animation(reduced ? nil : DSMotion.standardAnimation, value: model.draft.exception == .split)
    }

    private var form: some View {
        let calendarOpen = model.drawer == .calendar
        return VStack(spacing: .zero) {
            EntryTopHeaderView(model: model, close: close, drag: drag)
            VStack(spacing: .zero) {
                EntryAmountBlockView(model: model)
                    .padding(.bottom, calendarOpen ? DS.Space.s12 : EntrySpec.amountBottom)
                typeBody
                    .transition(.opacity)
                EntryPillsRowView(model: model)
                if model.drawer != nil { EntryExpandedPanelView(model: model) }
                if model.hasReceipt {
                    EntryPill(title: "截图", icon: .screenshot, hint: "查看原始截图", action: receipt)
                }
            }
            .padding(.top, calendarOpen ? DS.Space.s8 : DS.Space.s20)
            .padding(.horizontal, DS.Space.s20)
            .padding(.bottom, calendarOpen ? .zero : EntrySpec.bodyBottom)
        }
    }

    private var footer: some View {
        VStack(spacing: .zero) {
            EntryResultStripView(model: model)
                .padding(.top, model.drawer == .calendar ? DS.Space.s12 : .zero)
                .padding(.horizontal, DS.Space.s16)
                .padding(.bottom, DS.Space.s12)
            if model.hidesKeypad {
                DS.Color.tray.frame(height: safeBottom)
            } else {
                EntryKeypadTrayView(model: model, safeBottom: safeBottom, save: save)
            }
        }
    }

    @ViewBuilder private var typeBody: some View {
        if model.draft.isRoute {
            EntryTransferRouteView(model: model)
                .padding(.bottom, DS.Space.s20)
        } else {
            EntryCategoryRowView(model: model)
                .padding(.bottom, DS.Space.s12)
            if model.draft.category != nil {
                EntrySubcategoryRowView(model: model)
                    .padding(.bottom, model.drawer == .calendar ? DS.Space.s8 : EntrySpec.bodyBottom)
            }
            if model.draft.exception == .split {
                EntryAACardView(model: model)
                    .padding(.bottom, DS.Space.s12)
            }
        }
    }
}

private struct EntryGrabber: View {
    var body: some View {
        Capsule(style: .continuous).fill(DS.Color.grabber)
            .frame(width: EntrySpec.grabberWidth, height: EntrySpec.grabberHeight)
            .padding(.top, DS.Space.s8)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

private struct EntryTopHeaderView: View {
    let model: EntrySheetViewModel
    let close: () -> Void
    let drag: EntryHeaderDrag
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        VStack(spacing: .zero) {
            EntryGrabber()
                .contentShape(Rectangle())
                .gesture(dragGesture)
            HStack(spacing: .zero) {
                Button(action: close) {
                    DS.Icon.close.view(size: DS.Size.icon, color: DS.Color.ink3)
                        .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .accessibilityLabel("关闭记一笔")
                .accessibilityHint("保留尚未记下的草稿")
                .accessibilityIdentifier("cancelManualSheet")
                .frame(maxWidth: EntrySpec.headerSide, alignment: .leading)
                Spacer(minLength: .zero)
                tabs
                Spacer(minLength: .zero)
                Color.clear
                    .frame(width: EntrySpec.headerSide, height: DS.Size.tapMin)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .accessibilityHidden(true)
            }
            .frame(height: DS.Size.tapMin)
            .padding(.horizontal, DS.Space.s4)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: EntrySpec.dragMinimum, coordinateSpace: .global)
            .onChanged(drag.move)
            .onEnded(drag.end)
    }

    private var tabs: some View {
        ViewThatFits(in: .horizontal) {
            tabGroup(fixed: true)
            tabGroup(fixed: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("记账类型")
    }

    private func tabGroup(fixed: Bool) -> some View {
        HStack(spacing: .zero) {
            ForEach(EntryType.allCases) { type in
                let selected = model.draft.type == type
                Button {
                    withAnimation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.standardAnimation) { model.select(type) }
                } label: {
                    Text(type.title).dsText(DS.Font.tBody)
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? DS.Color.ink : DS.Color.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(EntrySpec.amountMinimumScale)
                        .frame(width: fixed ? EntrySpec.tabWidth : nil)
                        .frame(minWidth: DS.Size.tapMin, maxWidth: .infinity, minHeight: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
                .accessibilityHint("切换到\(type.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("entryNature_" + type.rawValue)
            }
        }
        .fixedSize(horizontal: fixed, vertical: false)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geo in
                let width = geo.size.width / CGFloat(EntryType.allCases.count)
                let index = EntryType.allCases.firstIndex(of: model.draft.type) ?? 0
                Capsule(style: .continuous).fill(DS.Color.ink)
                    .frame(width: EntrySpec.thumbWidth, height: EntrySpec.thumbHeight)
                    .offset(x: width * (CGFloat(index) + EntrySpec.midpoint) - EntrySpec.thumbWidth * EntrySpec.midpoint)
                    .animation(reduced ? nil : DSMotion.smoothAnimation, value: index)
            }
            .frame(height: EntrySpec.thumbHeight)
            .padding(.bottom, EntrySpec.thumbBottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct EntryAmountBlockView: View {
    @Bindable var model: EntrySheetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.amountBlock)
        VStack(spacing: EntrySpec.gap) {
            HStack(spacing: EntrySpec.gap) {
                Button { model.toggleDrawer(.currency) } label: {
                    HStack(spacing: EntrySpec.currencyGap) {
                        Text(model.draft.currency == .cny ? "¥" : model.draft.currency.rawValue)
                            .dsText(DS.Font.tBody).fontWeight(.semibold).monospacedDigit()
                        DS.Icon.chevronDown.view(size: EntrySpec.currencyChevron, color: DS.Color.ink3)
                    }
                    .foregroundStyle(DS.Color.ink2)
                    .padding(.leading, EntrySpec.compactPadding)
                    .padding(.trailing, DS.Space.s8)
                    .frame(minHeight: EntrySpec.currencyHeight)
                    .dsPill()
                    .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .fixedSize()
                .accessibilityLabel("币种，" + model.draft.currency.unit)
                .accessibilityHint("选择外币和汇率")
                Text(model.draft.expression.isExpression ? Money.text(model.money, currency: false)
                     : model.draft.expression.isEmpty ? "0.00" : model.draft.expression.formattedDisplay)
                    .dsText(DS.Font.nEntry)
                    .foregroundStyle(model.draft.type == .income ? DS.Color.accentInk : DS.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(EntrySpec.amountMinimumScale)
                    .contentTransition(reduced ? .identity : .numericText())
                    .animation(reduced ? nil : DSMotion.snappyAnimation, value: model.money)
                    .accessibilityLabel("金额")
                    .accessibilityValue(model.draft.expression.formattedDisplay)
                    .accessibilityHint("用下方键盘输入")
                    .accessibilityIdentifier("entryKeypadAmount")
                EntryAmountCaretView(steady: model.settled)
            }
            .frame(minHeight: EntrySpec.amountHeight)
            if model.draft.expression.isExpression {
                Text(model.draft.expression.formattedDisplay + " = " + Money.text(model.money, currency: false))
                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
            }
            if model.draft.currency != .cny, let rate = model.signedRate, let local = model.localMoney {
                Text("≈ \(Money.text(local)) · 1 \(model.draft.currency.rawValue) = \(NSDecimalNumber(decimal: rate).stringValue)")
                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
            }
            if model.drawer == .purpose {
                HStack(spacing: DS.Space.s8) {
                    DSInlineTextField(title: "用途", text: $model.draft.purpose) { model.drawer = nil }
                        .accessibilityIdentifier("entryPurpose")
                    EntryPill(title: nil, icon: .done, label: "完成用途", hint: "收起键盘") { model.drawer = nil }
                }
            } else {
                Button { model.toggleDrawer(.purpose) } label: {
                    HStack(spacing: EntrySpec.gap) {
                        DS.Icon.edit.view(size: DS.Font.tLabel.size, color: DS.Color.ink3)
                        Text(model.draft.purpose.isEmpty ? "用途" : model.draft.purpose)
                            .dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).lineLimit(1)
                    }
                    .frame(minHeight: EntrySpec.currencyHeight)
                    .padding(.horizontal, DS.Space.s8)
                    .padding(.vertical, DS.Space.s4)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .accessibilityLabel("用途")
                .accessibilityValue(model.draft.purpose)
                .accessibilityHint("填写这笔账的用途")
                .accessibilityIdentifier("entryPurpose")
            }
        }
        .frame(maxWidth: .infinity)
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
        Capsule(style: .continuous).fill(DS.Color.ink3)
            .frame(width: EntrySpec.caretWidth, height: EntrySpec.caretHeight)
            .opacity(EntrySpec.caretOpacity)
    }
}

private struct EntryCategoryRowView: View {
    let model: EntrySheetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.categoryRow)
        HStack(alignment: .top, spacing: .zero) {
            ForEach(model.topCategories) { category in
                EntryCategoryCircle(name: category.name, icon: category.entryIcon,
                   selected: category.name == model.draft.category,
                   suggested: model.draft.category == nil && model.suggestion?.category == category.name) {
                    withAnimation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.snappyAnimation) {
                        model.select(category: category.name)
                    }
                }
                .frame(width: EntrySpec.categoryWidth)
                .accessibilityIdentifier("entryCategory_" + category.name)
                Spacer(minLength: .zero)
            }
            EntryCategoryCircle(name: "全部", icon: .catAll, hint: "展开全部分类") { model.categoryPanel = true }
                .frame(width: EntrySpec.categoryWidth)
                .accessibilityIdentifier("entryCategoryMore")
        }
        .keyframeAnimator(initialValue: CGFloat(1), trigger: model.categoryPulse) { content, scale in
            content.scaleEffect(reduced ? 1 : scale)
        } keyframes: { _ in
            SpringKeyframe(DSMotion.Press.scale, spring: DSMotion.snappy)
            SpringKeyframe(1, spring: DSMotion.snappy)
        }
    }
}

private struct EntryCategoryCircle: View {
    let name: String
    let icon: DS.Icon
    var selected = false
    var suggested = false
    var hint = "选择分类"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: EntrySpec.gap) {
                icon.view(size: EntrySpec.categoryIcon, color: selected ? DS.Color.accentInk : DS.Color.ink2)
                    .frame(width: DS.Size.catCircle, height: DS.Size.catCircle)
                    .dsPill(selected ? DS.Color.accentSoft : DS.Color.surface)
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
                    .foregroundStyle(selected ? DS.Color.ink : DS.Color.ink2)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(EntrySpec.amountMinimumScale)
            }
            .frame(maxWidth: EntrySpec.categoryWidth)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
        .accessibilityLabel(name)
        .accessibilityValue(suggested && !selected ? "建议" : "")
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct EntrySubcategoryRowView: View {
    let model: EntrySheetViewModel

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.subRow)
        HStack(spacing: EntrySpec.gap) {
            Text("小类").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                .frame(width: EntrySpec.subcategoryLabelWidth, alignment: .leading)
            ScrollView(.horizontal) {
                HStack(spacing: EntrySpec.gap) {
                    ForEach(model.subcategories, id: \.self) { name in
                        EntrySubcategoryChip(name: name, selected: name == model.draft.subcategory) {
                            model.draft.subcategory = model.draft.subcategory == name ? nil : name
                        }
                    }
                    Button { model.toggleDrawer(.subcategory) } label: {
                        DS.Icon.add.view(size: DS.Font.tCaption.size, color: DS.Color.ink3)
                            .frame(width: DS.Size.chipH, height: DS.Size.chipH)
                            .dsPill()
                            .frame(minHeight: DS.Size.tapMin)
                    }
                    .buttonStyle(EntryTactileButtonStyle())
                    .accessibilityLabel("新子类")
                    .accessibilityHint("在当前分类内添加小类")
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct EntrySubcategoryChip: View {
    let name: String
    let selected: Bool
    var raised = false
    var neutral = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .dsText(raised ? DS.Font.tPill : DS.Font.tSub)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? DS.Color.accentInk : neutral ? DS.Color.ink3 : DS.Color.ink2)
                .fixedSize()
                .padding(.horizontal, DS.Space.s12)
                .frame(minHeight: raised ? DS.Size.pillH : DS.Size.chipH)
                .dsPill(selected ? DS.Color.accentSoft : raised ? DS.Color.raised : DS.Color.surface)
                .frame(minHeight: DS.Size.tapMin)
        }
        .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
        .accessibilityLabel(name)
        .accessibilityHint("选择小类")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct EntryTransferRouteView: View {
    let model: EntrySheetViewModel

    var body: some View {
        VStack(spacing: DS.Space.s8) {
            if model.draft.type == .transfer && model.draft.originalNature == nil {
                FlowLayout {
                    ForEach(EntryTransferMode.allCases) { mode in
                        EntryPill(title: mode.rawValue, selected: model.draft.transferMode == mode, hint: "切换转账方式") {
                            model.select(transferMode: mode)
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: EntrySpec.compactPadding) {
                accountPill(destination: false)
                DS.Icon.chevron.view(size: EntrySpec.routeIcon, color: DS.Color.ink3)
                    .padding(.top, EntrySpec.pillLeading)
                accountPill(destination: true)
            }
        }
    }

    private func accountPill(destination: Bool) -> some View {
        let account = model.account(destination ? model.draft.destinationID : model.draft.accountID)
        let title = account?.name ?? (destination ? "转入账户" : "转出账户")
        let ink = destination ? DS.Color.accentInk : DS.Color.ink2
        return VStack(spacing: DS.Space.s4) {
            Button { model.toggleDrawer(destination ? .destination : .source) } label: {
                HStack(spacing: DS.Space.s8) {
                    (account?.kind.entryIcon ?? .acctWallet).view(size: EntrySpec.routeIcon, color: ink)
                    Text(title).dsText(DS.Font.tLabelStrong)
                        .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
                }
                .foregroundStyle(ink)
                .padding(.leading, DS.Space.s12)
                .padding(.trailing, DS.Space.s16)
                .frame(minHeight: EntrySpec.routeHeight)
                .dsPill(destination ? DS.Color.accentSoft : DS.Color.surface)
                .frame(minHeight: DS.Size.tapMin)
            }
            .buttonStyle(EntryTactileButtonStyle())
            .accessibilityLabel((destination ? "转入，" : "转出，") + title)
            .accessibilityHint(destination ? "选择目标账户" : "选择来源账户")
            if model.routeShowsBalance, let account {
                Text("余 " + (model.hidesAmounts ? "••••" : Money.text(Finance.balance(account, in: model.ledger, at: model.now), currency: false)))
                    .dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3)
            }
        }
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
                Text(Money.text(model.myShare, currency: false)).dsText(DS.Font.tLabelStrong)
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
        .accessibilityLabel("我承担 " + Money.text(model.myShare))
        .accessibilityHint("平分金额或调整个人实付")
    }
}

private struct EntryPill: View {
    let title: String?
    var icon: DS.Icon? = nil
    var selected = false
    var strong = false
    var label: String? = nil
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: EntrySpec.gap) {
                if let icon { icon.view(size: DS.Font.tLabel.size, color: DS.Color.ink3) }
                if let title {
                    Text(title).dsText(DS.Font.tPill).monospacedDigit()
                        .fontWeight(selected || strong ? .semibold : .regular)
                        .foregroundStyle(selected || strong ? DS.Color.ink : DS.Color.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(EntrySpec.amountMinimumScale)
                }
            }
            .padding(.leading, title == nil ? EntrySpec.iconOnlyPadding : EntrySpec.pillLeading)
            .padding(.trailing, title == nil ? EntrySpec.iconOnlyPadding : EntrySpec.trailingPadding)
            .frame(minWidth: DS.Size.pillH, minHeight: DS.Size.pillH)
            .dsPill(selected ? DS.Color.selected : DS.Color.surface)
            .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin)
        }
        .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
        .accessibilityLabel(label ?? title ?? "")
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct EntryPillsRowView: View {
    let model: EntrySheetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.pillsRow)
        let calendarOpen = model.drawer == .calendar
        FlowLayout {
            if model.drawer == .time || calendarOpen {
                day("今天", offset: 0)
                day("昨天", offset: -1)
                day("前天", offset: -2)
                EntryPill(title: nil, icon: .cycle, selected: calendarOpen, label: "日历",
                          hint: calendarOpen ? "收起日历" : "选择日期和时间") {
                    model.toggleDrawer(.calendar)
                }
                if model.canRepeat && model.draft.exception == nil {
                    EntryPill(title: "每月", icon: .subscription, selected: model.draft.repeatMonthly, hint: "切换每月重复") {
                        model.toggleRepeat()
                    }
                }
            } else {
                if !model.draft.isRoute {
                    let account = model.account(model.draft.accountID)
                    EntryPill(title: account?.name ?? "账户", icon: account?.kind.entryIcon ?? .acctWallet,
                              hint: "选择这笔账的账户") { model.toggleDrawer(.source) }
                }
                EntryPill(title: time, icon: model.draft.repeatMonthly ? .subscription : .time,
                          strong: model.draft.repeatMonthly, hint: "展开日期和重复选项") { model.toggleDrawer(.time) }
                if model.draft.type == .expense {
                    EntryPill(title: model.draft.exception?.title, icon: .more, strong: model.draft.exception != nil,
                              label: model.draft.exception?.title ?? "更多选项", hint: "切换机动余钱、待报销和待 AA") {
                        model.cycleException()
                    }
                }
                if model.draft.type == .income && model.draft.originalNature == nil {
                    EntryPill(title: model.draft.incomeNextCycle ? "算进 下周期" : "算进 本期", icon: .cycle,
                              strong: true, hint: "切换收入计入的周期") { model.draft.incomeNextCycle.toggle() }
                }
            }
        }
        .animation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.smoothAnimation, value: model.drawer)
    }

    private var time: String {
        guard model.draft.repeatMonthly else { return model.dayLabel }
        let day = model.fixtureRepeatDay ?? Dates.calendar.component(.day, from: model.draft.date)
        return "\(model.dayLabel) · 每月 \(day) 日"
    }

    private func day(_ title: String, offset: Int) -> some View {
        EntryPill(title: title, selected: Dates.day(model.draft.date) == Dates.day(Dates.addDays(offset, to: model.now)),
                  hint: "选择" + title) { model.setDay(offset) }
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
            case .source, .destination:
                let destination = model.drawer == .destination
                FlowLayout {
                    ForEach(model.accounts(destination: destination)) { account in
                        EntryPill(title: account.name, icon: account.kind.entryIcon,
                                  selected: account.id == (destination ? model.draft.destinationID : model.draft.accountID),
                                  hint: "选择账户") { model.selectAccount(account.id, destination: destination) }
                    }
                }
            case .calendar:
                DSDatePickerPanel(date: Binding(get: { model.draft.date }, set: { model.setDate($0) }))
            case .subcategory where !model.categoryPanel:
                HStack(spacing: DS.Space.s8) {
                    EntryInlineAddView(title: "新子类", text: $model.inputText,
                                       autoFocus: model.autoFocusSubcategory, action: model.addSubcategory)
                    EntryPill(title: nil, icon: .close, label: "关闭新子类", hint: "收起小类输入") {
                        model.toggleDrawer(.subcategory)
                    }
                }
            case .split:
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    HStack {
                        Text("总金额").dsText(DS.Font.tPill)
                        Spacer()
                        Text(Money.text(model.localMoney ?? 0)).dsText(DS.Font.tLabelStrong).monospacedDigit()
                        EntryPill(title: "平分", hint: "按\(model.splitCount) 人平均计算") {
                            model.draft.personalShare = ""
                            model.drawer = nil
                        }
                    }
                    HStack {
                        Text("个人实付").dsText(DS.Font.tPill)
                        DSInlineTextField(title: "个人实付", text: $model.draft.personalShare, decimal: true,
                                          autoFocus: false) { model.drawer = nil }
                        EntryPill(title: nil, icon: .done, label: "完成分摊", hint: "保留个人实付") { model.drawer = nil }
                    }
                }
                .foregroundStyle(DS.Color.ink)
            default: EmptyView()
            }
        }
    }
}

private struct EntryInlineAddView: View {
    let title: String
    @Binding var text: String
    var button = "添加"
    var autoFocus = true
    let action: () -> Void

    var body: some View {
        let previewCaret = autoFocus ? nil : CGSize(width: EntrySpec.caretWidth, height: EntrySpec.panelAddCaretHeight)
        HStack(spacing: EntrySpec.gap) {
            DSInlineTextField(title: title, text: $text, autoFocus: autoFocus, embedded: true,
                              previewCaretSize: previewCaret, onSubmit: action)
                .frame(minWidth: EntrySpec.panelAddFieldWidth, minHeight: DS.Size.pillH)
            Button(action: action) {
                Text(button).dsText(DS.Font.tCaption).fontWeight(.semibold)
                    .foregroundStyle(DS.Color.onAccent)
                    .padding(.horizontal, DS.Space.s8)
                    .frame(minHeight: EntrySpec.panelAddHeight)
                    .dsPill(DS.Color.accent)
                    .frame(minWidth: DS.Size.tapMin)
            }
            .buttonStyle(EntryTactileButtonStyle())
            .accessibilityHint(title)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.leading, DS.Space.s12)
        .padding(.trailing, EntrySpec.gap)
        .frame(minHeight: DS.Size.pillH)
        .background(DS.Color.raised, in: DS.Shape.pill)
        .overlay { DS.Shape.pill.strokeBorder(DS.Color.accent, lineWidth: DS.Stroke.focus).allowsHitTesting(false) }
        .frame(minHeight: DS.Size.tapMin)
    }
}

private struct EntryResultStripView: View {
    let model: EntrySheetViewModel
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.resultStrip)
        let result = model.result
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                title(result)
                note(result)
                value(result)
            }
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                title(result)
                note(result)
                value(result)
            }
        }
        .frame(maxWidth: .infinity, minHeight: EntrySpec.resultHeight, alignment: .leading)
        .padding(.horizontal, DS.Space.s16)
        .padding(.vertical, EntrySpec.compactPadding)
        .dsSurface(DS.Color.surface, radius: DS.Radius.m)
        .accessibilityElement(children: .combine)
        .accessibilityHint(result.fraction.map { "已用额度 " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
        .accessibilityIdentifier("entrySavingHint")
    }

    private func title(_ result: EntryResult) -> some View {
        Text(result.title).dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink2).fixedSize(horizontal: true, vertical: false)
    }
    private func note(_ result: EntryResult) -> some View {
        Text(model.hidesAmounts && !result.note.isEmpty ? "••••" : result.note)
            .dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(result.warning ? DS.Color.warnInk : DS.Color.ink3)
            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func value(_ result: EntryResult) -> some View {
        Text(model.hidesAmounts && result.value != "不变" ? "••••" : result.value)
            .dsText(EntrySpec.resultNumber)
            .foregroundStyle(result.warning ? DS.Color.warnInk : result.value == "不变" ? DS.Color.ink : DS.Color.accentInk)
            .fixedSize(horizontal: true, vertical: false)
            .contentTransition(reduced ? .identity : .numericText())
            .animation(reduced ? nil : DSMotion.standardAnimation, value: result.value)
    }
}

private struct EntryKeypadTrayView: View {
    let model: EntrySheetViewModel
    let safeBottom: CGFloat
    let save: () -> Void
    private let keys = ["1", "2", "3", "⌫", "4", "5", "6", "+", "7", "8", "9", "−", ".", "0", "00", "记下"]

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.keypad)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s8), count: DSLayout.keypadColumns), spacing: DS.Space.s8) {
            ForEach(keys, id: \.self) { key in
                if key == "⌫" {
                    EntryBackspaceKey { model.draft.expression.press(key) }
                } else {
                    Button {
                        if key == "记下" { save() } else { model.draft.expression.press(key) }
                    } label: {
                        EntryKeyLabel(key: key)
                    }
                    .buttonStyle(EntryTactileButtonStyle())
                    .accessibilityLabel(spoken(key))
                    .accessibilityHint(key == "记下" ? "保存并关闭录入面板" : "输入" + spoken(key))
                    .accessibilityIdentifier(key == "记下" ? "saveQuickEntry" : "keypad_" + (key == "−" ? "-" : key))
                    .disabled(key == "记下" && !model.draft.expression.canSave)
                }
            }
        }
        .padding(DS.Space.s8)
        .padding(.bottom, safeBottom)
        .frame(minHeight: max(EntrySpec.trayHeight, EntrySpec.keypadGridHeight + DS.Space.s12 + safeBottom), alignment: .top)
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
    private var isSave: Bool { key == "记下" }
    private var fill: Color {
        if isSave { return DS.Color.accent }
        return ["⌫", "+", "−"].contains(key) ? DS.Color.keyFn : DS.Color.key
    }

    var body: some View {
        Group {
            if key == "⌫" {
                DS.Icon.backspace.view(size: EntrySpec.backspaceIcon, color: DS.Color.ink)
            } else {
                Text(key).dsText(isSave ? DS.Font.tTitle : DS.Font.nKey)
                    .foregroundStyle(isSave ? DS.Color.onAccent : DS.Color.ink)
                    .lineLimit(1).minimumScaleFactor(EntrySpec.amountMinimumScale)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DS.Size.keyH)
        .dsSurface(fill, radius: DS.Radius.s)
        .dsShadow(DS.Shadow.key)
    }
}

private struct EntryCategoryPanelView: View {
    @Bindable var model: EntrySheetViewModel
    let safeBottom: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        let _ = EntryRenderDiagnostics.hit(.categoryPanel)
        VStack(spacing: .zero) {
            EntryGrabber()
            HStack {
                Text("分类").dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    model.categoryEditing.toggle()
                    model.drawer = nil
                } label: {
                    Text(model.categoryEditing ? "完成" : "编辑").dsText(DS.Font.tLabel)
                        .foregroundStyle(DS.Color.accentInk)
                        .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin, alignment: .trailing)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .accessibilityHint(model.categoryEditing ? "结束编辑分类" : "编辑现有分类")
            }
            .frame(minHeight: DS.Size.ctaH)
            .padding(.horizontal, DS.Space.s4)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: EntrySpec.gap), count: EntrySpec.categoryColumns), spacing: EntrySpec.categorySecondaryGap) {
                    ForEach(model.categories) { category in
                        EntryCategoryCircle(name: category.name, icon: category.entryIcon, selected: model.draft.category == category.name) {
                            model.select(category: category.name)
                            if model.categoryEditing {
                                model.inputText = category.name
                                model.drawer = .renameCategory
                            }
                        }
                    }
                    EntryCategoryCircle(name: "新建", icon: .add, hint: "新建分类") { model.toggleDrawer(.newCategory) }
                }
                .padding(.top, EntrySpec.gap)
                if model.drawer == .newCategory {
                    EntryInlineAddView(title: "新建分类", text: $model.inputText, action: model.addCategory)
                        .padding(.top, DS.Space.s12)
                } else if model.drawer == .renameCategory {
                    EntryInlineAddView(title: "分类名称", text: $model.inputText, button: "完成", action: model.renameCategory)
                        .padding(.top, DS.Space.s12)
                }
                if let category = model.draft.category { chips(category: category).padding(.top, EntrySpec.amountBottom) }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .padding(.bottom, safeBottom)
        }
        .padding(.horizontal, DS.Space.s16)
        .frame(height: min(maxHeight, EntrySpec.categoryPanelHeight))
        .background(DS.Color.bg)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("entryCategoryPicker")
        .accessibilityAction(.escape) { model.dismissCategoryPanel() }
        .onKeyPress(.escape) { model.dismissCategoryPanel(); return .handled }
    }

    private func chips(category: String) -> some View {
        VStack(alignment: .leading, spacing: EntrySpec.compactPadding) {
            Text(category + " · 小类").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
            FlowLayout(centered: false) {
                ForEach(model.subcategories, id: \.self) { name in
                    EntrySubcategoryChip(name: name, selected: name == model.draft.subcategory, raised: true) {
                        model.draft.subcategory = name
                    }
                }
                EntrySubcategoryChip(name: "不分小类", selected: false, raised: true, neutral: true) {
                    model.draft.subcategory = nil
                }
                if model.drawer == .subcategory {
                    EntryInlineAddView(title: "新子类", text: $model.inputText, autoFocus: model.autoFocusSubcategory,
                                       action: model.addSubcategory)
                }
                Button { model.toggleDrawer(.subcategory) } label: {
                    HStack(spacing: DS.Space.s4) {
                        DS.Icon.add.view(size: DS.Font.tCaption.size, color: DS.Color.accentInk)
                        Text("小类").dsText(DS.Font.tPill).foregroundStyle(DS.Color.accentInk)
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .frame(minHeight: DS.Size.pillH)
                    .dsPill(DS.Color.raised)
                    .frame(minHeight: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .accessibilityLabel("新子类")
                .accessibilityHint("在当前分类内添加小类")
            }
        }
        .padding(.horizontal, EntrySpec.trailingPadding)
        .padding(.top, EntrySpec.trailingPadding)
        .padding(.bottom, DS.Space.s16)
        .dsSurface(DS.Color.surface, radius: DS.Radius.m)
    }
}

private struct FlowLayout: Layout {
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

private extension AccountKind {
    var entryIcon: DS.Icon {
        switch self {
        case .bank: .acctDebit
        case .credit: .acctCredit
        case .investment: .acctInvest
        case .cash: .acctWallet
        default: .acctBalance
        }
    }
}

private extension YubaiCore.Category {
    var entryIcon: DS.Icon {
        switch name {
        case "吃饭", "餐饮": .catFood
        case "咖啡", "咖啡茶饮": .catCoffee
        case "交通", "出行": .catTransport
        case "买菜", "生鲜买菜": .catGrocery
        case "购物": .catShopping
        case "居住", "住房": .catHousing
        case "娱乐": .catFun
        case "日用", "日用百货": .catDaily
        case "数码", "数码电器": .catDigital
        case "工资", "工资奖金": .acctWallet
        case "退款": .reimburse
        default: iconForSymbol
        }
    }

    private var iconForSymbol: DS.Icon {
        switch symbol {
        case "fork.knife", "takeoutbag.and.cup.and.straw": .catFood
        case "cup.and.saucer": .catCoffee
        case "tram", "car", "bus": .catTransport
        case "basket", "cart": .catGrocery
        case "bag", "shoppingbag": .catShopping
        case "house", "house.fill": .catHousing
        case "ticket", "gamecontroller": .catFun
        case "shippingbox": .catDaily
        case "iphone", "desktopcomputer": .catDigital
        default: .catOther
        }
    }
}
