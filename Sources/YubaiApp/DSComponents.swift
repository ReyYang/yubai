import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

struct DSInlineTag {
    enum Tone { case warning, positive, quiet }
    let title: String
    var tone: Tone = .warning
}

struct DSListRow: View {
    let icon: DS.Icon?
    let name: String
    let amount: String
    var detail: String? = nil
    var tag: DSInlineTag? = nil
    var separator = true

    var detailAmount: String? = nil
    var amountColor = DS.Color.ink

    struct Inline {
        let date: String
        var swatch: Color? = nil
    }
    var inline: Inline? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let inline {
            inlineContent(inline)
        } else {
            standardContent
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: HomeSpec.heroLabelGap) {
            HStack(spacing: DS.Space.s12) {
                if let icon { DSIconView(icon: icon, size: DS.Size.icon, color: DS.Color.iconQuiet) }
                HStack(spacing: HomeSpec.gap6) {
                    Text(name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).lineLimit(1)
                    if let tag {
                        Text(tag.title).dsText(DS.Font.tTag)
                            .foregroundStyle(tag.tone == .warning ? DS.Color.warnInk : tag.tone == .positive ? DS.Color.accentInk : DS.Color.ink3)
                            .padding(.horizontal, HomeSpec.gap6)
                            .dsPill(tag.tone == .warning ? DS.Color.warnSoft : tag.tone == .positive ? DS.Color.accentSoft : DS.Color.surface)
                            .fixedSize()
                    }
                }.dsFillWidth()
                Text(amount).dsText(DS.Font.nSpine).foregroundStyle(amountColor)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale).layoutPriority(1)
            }
            if detail != nil || detailAmount != nil {
                HStack(spacing: DS.Space.s8) {
                    Text(detail ?? "").lineLimit(1)
                    Spacer(minLength: 0)
                    if let detailAmount { Text(detailAmount).monospacedDigit().fixedSize() }
                }.dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                    .padding(.leading, DS.Size.icon + DS.Space.s12)
            }
        }
        .frame(minHeight: detail == nil && detailAmount == nil ? DS.Size.rowBill : DS.Size.rowBill2)
        .dsFillWidth()
        .overlay(alignment: .top) {
            if separator {
                Rectangle().fill(DS.Color.separator).frame(height: DS.Stroke.hairline)
                    .padding(.leading, DS.Size.icon + DS.Space.s12)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func inlineContent(_ presentation: Inline) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: OverviewSpec.legendGap))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: OverviewSpec.legendGap) {
                if let swatch = presentation.swatch {
                    DSOverviewSwatch(color: swatch).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                }
                Text(name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).lineLimit(stacked ? nil : 1)
            }
            HStack(alignment: .firstTextBaseline, spacing: OverviewSpec.legendGap) {
                Text(presentation.date).dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3)
                Spacer(minLength: .zero)
                Text(amount).dsText(DS.Font.nSpine).foregroundStyle(amountColor)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale).layoutPriority(1)
            }
        }
        .padding(.vertical, stacked ? DS.Space.s4 : .zero)
        .frame(minHeight: DS.Size.rowBill)
        .overlay(alignment: .top) {
            if separator { DS.Color.separator.frame(height: DS.Stroke.hairline) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DSDayHeader: View {
    let title: String
    let total: String
    var today = false
    var first = true

    var body: some View {
        HStack(spacing: HomeSpec.gap6) {
            if today { Circle().fill(DS.Color.accent).frame(width: HomeSpec.gap6, height: HomeSpec.gap6) }
            Text(title).dsText(DS.Font.tSubStrong).foregroundStyle(today ? DS.Color.accentInk : DS.Color.ink)
            Spacer(minLength: DS.Space.s8)
            Text(total).dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
        }.padding(.top, first ? DS.Space.s8 : DS.Space.s20)
            .padding(.bottom, DS.Space.s4)
            .frame(minHeight: first ? DS.Size.chipH : DS.Size.tapMin)
            .dsFillWidth().accessibilityElement(children: .combine)
    }
}

struct DSBudget: Identifiable {
    let id: String
    let name: String
    let total: String
    let remaining: String
    let usedFraction: Double
    var overspent = false
    var isWarning: Bool { usedFraction >= DSInteraction.warningFraction }
    var usedText: String { min(1, usedFraction).formatted(.percent.precision(.fractionLength(0))) }
    var displayRemaining: String { overspent ? "超 " + remaining : remaining }
}

private struct DSProgress: View {
    let fraction: Double
    var warning = false
    var amber = false
    var accent = false
    var height = DS.Size.barCalm
    var body: some View {
        GeometryReader { geometry in
            Capsule(style: .continuous).fill(amber ? DS.Color.warnTrack : DS.Color.track)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous).fill(warning ? DS.Color.warn : accent ? DS.Color.accent : DS.Color.fillCalm)
                        .frame(width: geometry.size.width * CGFloat(min(1, max(0, fraction))))
                }
        }.frame(height: height).clipShape(Capsule(style: .continuous)).accessibilityHidden(true)
    }
}

struct DSBudgetRow: View {
    let budget: DSBudget
    var body: some View {
        if budget.isWarning { DSAmberTile(budget: budget) }
        else {
            VStack(spacing: DS.Space.s8) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                    Text(budget.name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2)
                    Text("/ \(budget.total)").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                    Spacer(minLength: DS.Space.s8)
                    Text(budget.displayRemaining).dsText(DS.Font.nSpineLg).foregroundStyle(DS.Color.ink)
                }
                DSProgress(fraction: budget.usedFraction)
            }.padding(.vertical, DS.Space.s8).frame(minHeight: HomeSpec.budgetRow).dsFillWidth()
                .accessibilityElement(children: .combine)
        }
    }
}

struct DSAmberTile: View {
    let budget: DSBudget
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                Text(budget.name).dsText(DS.Font.tBody).fontWeight(.semibold)
                Spacer(minLength: 0)
                Text("已用 \(budget.usedText)").dsText(DS.Font.tCaption)
            }.foregroundStyle(DS.Color.warnInk)
            Text(budget.displayRemaining).dsText(DS.Font.nTile).foregroundStyle(DS.Color.ink)
                .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
            Text("/ \(budget.total)").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
            DSProgress(fraction: budget.usedFraction, warning: true, amber: true,
                       height: DS.Size.barAmber)
        }.dsFillWidth()
            .dsSurface(DS.Color.warnSoft, radius: DS.Radius.m,
                       padding: EdgeInsets(top: DS.Space.s12, leading: DS.Space.s16, bottom: DS.Space.s12, trailing: DS.Space.s16))
            .accessibilityElement(children: .combine)
    }
}

struct DSAccordion: View {
    struct Item: Identifiable {
        let id: String
        let icon: DS.Icon
        let title: String
        let subitems: [String]
    }
    let items: [Item]
    @Binding var expandedID: String?
    var onSelect: (String, String) -> Void = { _, _ in }
    var onAdd: (String) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            ForEach(items) { item in
                let expanded = expandedID == item.id
                VStack(spacing: 0) {
                    Button { expandedID = expanded ? nil : item.id } label: {
                        HStack(spacing: DS.Space.s12) {
                            DSIconView(icon: item.icon, size: DS.Size.icon,
                                       color: expanded ? DS.Color.accentInk : DS.Color.ink2)
                                .frame(width: DS.Size.iconTile, height: DS.Size.iconTile)
                                .dsSurface(expanded ? DS.Color.accentSoft : DS.Color.surface, radius: DS.Radius.s)
                            Text(item.title).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink).dsFillWidth()
                            Text("\(item.subitems.count) 个小类").dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink3)
                            DSIconView(icon: .chevron, size: DS.Font.tPill.size,
                                       color: expanded ? DS.Color.ink : DS.Color.chevron)
                                .rotationEffect(.radians(expanded ? .pi / 2 : 0))
                                .animation(enabled ? DSMotion.animation(.chevronRotate, reduceMotion: reduceMotion) : nil, value: expanded)
                        }.padding(.horizontal, DS.Space.s12).frame(minHeight: DS.Size.rowCat)
                    }.dsPressStyle().accessibilityIdentifier("ds-accordion-\(item.id)")
                        .accessibilityValue(expanded ? "展开" : "收起")
                    if expanded {
                        VStack(spacing: 0) {
                            ForEach(item.subitems, id: \.self) { name in
                                Button { onSelect(item.id, name) } label: {
                                    Text(name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2)
                                        .dsFillWidth().frame(minHeight: DS.Size.rowSub)
                                        .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                                }.dsPressStyle()
                            }
                            Button { onAdd(item.id) } label: {
                                Label { Text("添加小类").dsText(DS.Font.tLabelStrong) } icon: {
                                    DSIconView(icon: .add, size: DS.Font.tLabelStrong.size)
                                }.foregroundStyle(DS.Color.accentInk).dsFillWidth().frame(minHeight: DS.Size.rowSub)
                                    .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                            }.dsPressStyle()
                        }.padding(.leading, DS.Space.s12 + DS.Size.iconTile + DS.Space.s12)
                            .padding(.trailing, DS.Space.s12).padding(.bottom, DS.Space.s8)
                            .transition(.opacity.animation(enabled ? DSMotion.animation(.accordion, reduceMotion: reduceMotion, property: .opacity) : nil))
                    }
                }.dsSurface(expanded ? DS.Color.raised : .clear, radius: DS.Radius.m)
                    .overlay(alignment: .top) {
                        if !expanded && item.id != items.first?.id {
                            DS.Color.separator.frame(height: DS.Stroke.hairline)
                                .padding(.leading, DS.Space.s12 + DS.Size.iconTile + DS.Space.s12)
                                .padding(.trailing, DS.Space.s12)
                        }
                    }
                    .animation(enabled ? DSMotion.animation(.accordion, reduceMotion: reduceMotion) : nil, value: expanded)
            }
        }.dsFillWidth()
    }
}

struct DSHero: View {
    struct Day: Identifiable {
        enum State { case past, warning, today, future }
        let id: Int
        let height: CGFloat
        let state: State
        var color: Color {
            switch state {
            case .past: DS.Color.chart4
            case .warning: DS.Color.warn
            case .today: DS.Color.accent
            case .future: DS.Color.track
            }
        }
    }
    let amount: String
    let daily: String
    let remainingDays: Int
    let days: [Day]
    let budgets: [DSBudget]
    var onAmount: () -> Void = {}
    var title = "还能花"
    var tint = DS.Color.ink
    var titleTint = DS.Color.ink3
    var guide: CGFloat? = HomeSpec.barGuide
    var onBudget: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onAmount) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s8))
                    : AnyLayout(HStackLayout(alignment: .bottom, spacing: DS.Space.s8))
                layout {
                    VStack(alignment: .leading, spacing: HomeSpec.heroLabelGap) {
                        HStack(spacing: HomeSpec.heroLabelGap) {
                            Text(title).dsText(DS.Font.tSub)
                            DSIconView(icon: .chevron, size: HomeSpec.chevron, color: titleTint)
                        }.foregroundStyle(titleTint)
                        Text(amount).dsText(DS.Font.nHero).foregroundStyle(tint).lineLimit(1)
                            .minimumScaleFactor(HomeSpec.numberMinimumScale)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(reduceMotion ? nil : DSMotion.standardAnimation, value: amount)
                            .accessibilityLabel(amount.contains("•") ? "金额已隐藏" : amount)
                            .accessibilityIdentifier("availableFunds")
                    }.dsFillWidth()
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
                        if !daily.isEmpty {
                            Text("每天 \(daily)").dsText(DS.Font.tLabelStrong).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                        }
                        Text("还剩 \(remainingDays) 天").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                            .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                    }.foregroundStyle(DS.Color.ink).dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .fixedSize().padding(.bottom, HomeSpec.heroDailyBottom)
                }.contentShape(Rectangle())
            }.dsPressStyle().accessibilityLabel("还能花，查看算式").accessibilityValue(amount.contains("•") ? "金额已隐藏" : amount)
                .accessibilityIdentifier("fundsFormula")
            DSDayBars(days: days, guide: guide).padding(.top, DS.Space.s8)
            DSHomeBudgetColumns(budgets: budgets, onBudget: onBudget)
        }.dsFillWidth()
    }

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
}

struct DSHomeBudgetColumns: View {
    let budgets: [DSBudget]
    var onBudget: (() -> Void)?

    var body: some View {
        if !budgets.isEmpty {
            HStack(spacing: DS.Space.s12) {
                ForEach(budgets.prefix(DSLayout.heroBudgets)) { budget in
                    if let onBudget {
                        Button(action: onBudget) { budgetColumn(budget) }.dsPressStyle()
                    } else { budgetColumn(budget) }
                }
            }.padding(.top, DS.Space.s12)
        }
    }

    private func budgetColumn(_ budget: DSBudget) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(budget.name).dsText(DS.Font.tCaption).lineLimit(1)
                .foregroundStyle(budget.isWarning ? DS.Color.warnInk : DS.Color.ink3)
            HStack(spacing: DS.Space.s4) {
                if budget.overspent { Text("超").dsText(HomeSpec.tinyStrong) }
                Text(budget.remaining).dsText(HomeSpec.headerNumber).lineLimit(1)
                    .minimumScaleFactor(HomeSpec.numberMinimumScale)
            }.foregroundStyle(budget.isWarning ? DS.Color.warnInk : DS.Color.ink)
            DSProgress(fraction: budget.usedFraction, warning: budget.isWarning, accent: true, height: DS.Size.barMini)
        }.dsFillWidth().accessibilityElement(children: .combine)
    }
}

struct DSDayBars: View {
    let days: [DSHero.Day]
    var guide: CGFloat? = HomeSpec.barGuide
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    @State private var appeared = false

    var body: some View {
        let reduceMotion = reduceMotionOverride ?? systemReduceMotion
        HStack(alignment: .bottom, spacing: DS.Size.dayBarGap) {
            ForEach(days) { day in
                RoundedRectangle(cornerRadius: HomeSpec.barRadius, style: .continuous)
                    .fill(day.color).frame(height: day.height)
                    .animation(enabled && !reduceMotion ? DSMotion.standardAnimation : nil, value: day.height)
                    .opacity(reduceMotion && enabled && !appeared ? 0 : 1)
                    .animation(enabled && reduceMotion ? DSMotion.reduceMotionAnimation : nil, value: appeared)
                    .scaleEffect(x: 1, y: reduceMotion || !enabled || appeared ? 1 : 0, anchor: .bottom)
                    .animation(enabled && !reduceMotion ? DSMotion.standardAnimation.delay(Double(day.id) * DSMotion.Role.barGrow.staggerDelay) : nil, value: appeared)
            }
        }.frame(height: DS.Size.dayBarsH, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if let guide {
                    Canvas { context, size in
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: size.height - guide))
                        line.addLine(to: CGPoint(x: size.width, y: size.height - guide))
                        context.stroke(line, with: .color(DS.Color.ink3), style: StrokeStyle(lineWidth: DS.Stroke.hairline, dash: [DS.Space.s4]))
                    }.allowsHitTesting(false)
                }
            }.accessibilityHidden(true)
            .onAppear { appeared = true }
    }
}

struct DSTabBar: View {
    enum Tab: String { case home, overview }
    @Binding var selection: Tab
    var onEntry: () -> Void
    var onEntryHold: () -> Void = {}
    @State private var held = false

    var body: some View {
        HStack(spacing: DS.Space.s20) {
            tab(.home, title: "首页", icon: .tabHome)
            Button {
                // A long press already opened 常用; its release is not a tap.
                if held { held = false } else { onEntry() }
            } label: {
                HStack(spacing: HomeSpec.gap6) {
                    DSIconView(icon: .add, size: DS.Size.brandTile, color: DS.Color.onAccent)
                    Text("记一笔").dsText(DS.Font.tBody).fontWeight(.semibold)
                        .minimumScaleFactor(HomeSpec.numberMinimumScale)
                }.foregroundStyle(DS.Color.onAccent).lineLimit(1)
                    .padding(.horizontal, DS.Space.s20)
                    .frame(minWidth: HomeSpec.entryWidth, minHeight: DS.Size.ctaH).dsPill(DS.Color.accent)
            }.dsPressStyle().accessibilityIdentifier("addEntry")
                .simultaneousGesture(LongPressGesture(minimumDuration: DSInteraction.holdDuration).onEnded { _ in held = true; onEntryHold() })
                .accessibilityAction(named: "常用") { onEntryHold() }
            tab(.overview, title: "全景", icon: .tabOverview)
        }.dynamicTypeSize(...DynamicTypeSize.xLarge)
            .padding(.horizontal, DS.Space.s12)
            .frame(maxWidth: .infinity, minHeight: HomeSpec.tabHeight)
            .background { DS.Color.raised.ignoresSafeArea(edges: .bottom) }
            .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
    }

    private func tab(_ tab: Tab, title: String, icon: DS.Icon) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: HomeSpec.tabIconGap) {
                DSIconView(icon: icon, size: DS.Size.icon,
                           color: selection == tab ? DS.Color.accentInk : DS.Color.ink3)
                Text(title).dsText(DS.Font.tTab).fontWeight(selection == tab ? .semibold : .medium)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
            }.foregroundStyle(selection == tab ? DS.Color.accentInk : DS.Color.ink3)
                .frame(width: HomeSpec.tabWidth).frame(minHeight: DS.Size.ctaH)
        }.dsPressStyle().accessibilityAddTraits(selection == tab ? .isSelected : [])
            .accessibilityIdentifier(tab == .home ? "tab_ledger" : "tab_insights")
    }
}

struct DSAskBar: View {
    var onAsk: () -> Void = {}
    var onVoice: () -> Void = {}
    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Button(action: onAsk) {
                HStack(spacing: DS.Space.s8) {
                    DSIconView(icon: .search, size: DS.Size.brandTile, color: DS.Color.ink3)
                    Text("问余白 · 搜账单").dsText(DS.Font.tLabel).lineLimit(1).dsFillWidth()
                }.frame(minHeight: DS.Size.askH)
            }.dsPressStyle().accessibilityIdentifier("openLedgerSearch")
            Button(action: onVoice) {
                DSIconView(icon: .voice, size: DS.Size.brandTile, color: DS.Color.ink2)
                    .frame(width: HomeSpec.tile32, height: HomeSpec.tile32)
            }.dsPressStyle().accessibilityLabel("语音输入")
        }.foregroundStyle(DS.Color.ink3)
            .padding(.leading, HomeSpec.askInset).padding(.trailing, DS.Space.s8)
            .dsPill(DS.Color.raised)
            .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
    }
}

struct DSHomeSearchField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        TextField("", text: $text, prompt: Text("问余白 · 搜账单").foregroundStyle(DS.Color.ink3))
            .textFieldStyle(.plain).dsText(DS.Font.tLabel).tint(DS.Color.accent)
            .foregroundStyle(DS.Color.ink).focused(focus).onSubmit(onSubmit)
            .accessibilityLabel("搜账单").accessibilityIdentifier("entriesSearch")
    }
}

/// 问余白's field: Return sends.
struct DSAskField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        TextField("", text: $text, prompt: Text("问余白").foregroundStyle(DS.Color.ink3))
            .textFieldStyle(.plain).dsText(DS.Font.tLabel).tint(DS.Color.accent)
            .foregroundStyle(DS.Color.ink).focused(focus).submitLabel(.send).onSubmit(onSubmit)
            .accessibilityLabel("问余白").accessibilityIdentifier("askInput")
    }
}

struct DSEntryPills: View {
    enum Exception: String, CaseIterable { case none = "", reserve = "走机动余钱", reimburse = "待报销", split = "待 AA" }
    let account: String
    var day = "今天"
    var calendarOpen = false
    @Binding var repeats: Bool
    @Binding var exception: Exception
    var repeatDay: Int
    var onAccount: () -> Void = {}
    var onCalendar: () -> Void = {}

    var body: some View {
        FlowLayout {
            pill(account, icon: .acctDebit, action: onAccount)
            pill(repeats ? "\(day) · 每月 \(repeatDay) 日" : day,
                 icon: repeats ? .subscription : .time, selected: calendarOpen, strong: repeats, action: onCalendar)
            pill(exception == .none ? "更多" : exception.rawValue, icon: .more,
                 strong: exception != .none, iconOnly: exception == .none) {
                let all = Exception.allCases
                exception = all[((all.firstIndex(of: exception) ?? 0) + 1) % all.count]
                if exception != .none { repeats = false }
            }
        }
    }

    private func pill(_ title: String, icon: DS.Icon, selected: Bool = false, strong: Bool = false,
                      iconOnly: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s4) {
                icon.view(size: DS.Font.tLabel.size, color: DS.Color.ink3)
                if !iconOnly {
                    Text(title).dsText(DS.Font.tPill).monospacedDigit()
                        .fontWeight(selected || strong ? .semibold : .regular)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .lineLimit(1)
            .foregroundStyle(selected || strong ? DS.Color.ink : DS.Color.ink2)
            .padding(.leading, iconOnly ? EntrySpec.iconOnlyPadding : EntrySpec.pillLeading)
            .padding(.trailing, iconOnly ? EntrySpec.iconOnlyPadding : EntrySpec.trailingPadding)
            .frame(minWidth: DS.Size.pillH, minHeight: DS.Size.pillH)
            .dsPill(selected ? DS.Color.selected : DS.Color.surface)
        }.dsPressStyle().accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DSCategoryPicker: View {
    struct Category: Identifiable {
        let id: String
        let name: String
        let icon: DS.Icon
        var suggested = false
    }
    let categories: [Category]
    let subcategories: [String]
    @Binding var selectedID: String
    @Binding var selectedSubcategory: String?
    var onAll: () -> Void = {}
    var onAdd: () -> Void = {}
    var body: some View {
        VStack(spacing: DS.Space.s16) {
            HStack(alignment: .top, spacing: DS.Space.s8) {
                ForEach(categories.prefix(DSLayout.categoryRow)) { category in
                    let selected = category.id == selectedID
                    Button {
                        if category.id == categories.last?.id { onAll() }
                        else { selectedID = category.id; selectedSubcategory = nil }
                    } label: {
                        VStack(spacing: DS.Space.s4) {
                            DSIconView(icon: category.icon, size: EntrySpec.categoryIcon,
                                       color: selected ? DS.Color.accentInk : DS.Color.ink2)
                                .frame(width: DS.Size.catCircle, height: DS.Size.catCircle)
                                .dsPill(selected ? DS.Color.accentSoft : DS.Color.surface)
                                .overlay(alignment: .topTrailing) {
                                    if category.suggested && !selected {
                                        Circle().fill(DS.Color.accent).frame(width: DS.Space.s8, height: DS.Space.s8)
                                            .padding(EntrySpec.guessRing)
                                            .background(DS.Color.bg, in: Circle())
                                            .padding(max(0, EntrySpec.guessInset - EntrySpec.guessRing))
                                    }
                                }
                            Text(category.name).dsText(DS.Font.tCaption).fontWeight(selected ? .semibold : .regular)
                                .foregroundStyle(selected ? DS.Color.ink : DS.Color.ink2)
                        }.frame(maxWidth: .infinity)
                    }.dsPressStyle().accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: DS.Space.s8) {
                    ForEach(subcategories, id: \.self) { name in
                        let selected = selectedSubcategory == name
                        Button { selectedSubcategory = name } label: {
                            Text(name).dsText(DS.Font.tPill).fontWeight(selected ? .semibold : .regular)
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(selected ? DS.Color.accentInk : DS.Color.ink2)
                                .padding(.horizontal, DS.Space.s12).frame(minHeight: DS.Size.chipH)
                                .dsPill(selected ? DS.Color.accentSoft : DS.Color.surface)
                        }.dsPressStyle().accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    Button(action: onAdd) {
                        DSIconView(icon: .add, size: DS.Font.tCaption.size, color: DS.Color.ink2)
                            .frame(width: DS.Size.chipH, height: DS.Size.chipH).dsPill()
                    }.dsPressStyle().accessibilityLabel("添加小类")
                }
            }.scrollIndicators(.hidden)
        }.dsFillWidth()
    }
}

struct DSEffectLine: View {
    let effect: EntryEffect
    var hidesAmount = false

    var body: some View {
        Text(effect.displayText(hidesAmount: hidesAmount))
            .dsText(DS.Font.tSub).monospacedDigit()
            .foregroundStyle(effect.warning ? DS.Color.warnInk : DS.Color.ink3)
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(hidesAmount ? "连带影响" : effect.text)
            .accessibilityValue(hidesAmount ? "金额已隐藏" : "")
    }
}

struct DSFloatingMenu: View {
    var onEdit: () -> Void = {}
    var onRecategorize: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onDelete: () -> Void = {}
    var recategorizationEnabled = true
    var body: some View {
        VStack(spacing: 0) {
            item("编辑", action: onEdit).accessibilityIdentifier("entryDetailEdit")
            item("改分类", action: onRecategorize).accessibilityIdentifier("entryDetailRecategorize")
                .disabled(!recategorizationEnabled)
            item("再记一笔一样的", action: onDuplicate)
            item("删除", warning: true, action: onDelete).accessibilityIdentifier("deleteEntryDetail")
                .padding(.top, HomeSpec.gap6)
                .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
        }.padding(.vertical, HomeSpec.gap6).frame(width: DS.Size.menuW)
            .background(DS.Color.raised).clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous)).dsShadow(DS.Shadow.float)
    }
    private func item(_ title: String, warning: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).dsText(DS.Font.tBody)
                .foregroundStyle(warning ? DS.Color.warnInk : DS.Color.ink)
                .dsFillWidth().frame(minHeight: DS.Size.tapMin).padding(.horizontal, DS.Space.s16)
        }.dsPressStyle()
    }
}

struct DSFloatingCard: View {
    struct Route {
        let title: String
        let icon: DS.Icon
    }

    let name: String
    let amount: String
    let impact: String
    let metadata: String
    var note: String? = nil
    var warning: String? = nil
    var showsMenu = false
    var onMore: () -> Void = {}
    var onDone: () -> Void = {}
    var onEdit: () -> Void = {}
    var onRecategorize: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onDelete: () -> Void = {}
    var amountColor = DS.Color.ink
    var effectValue = ""
    var effectTail = ""
    var foreign = false
    var route: (Route, Route)?
    var recovery: AnyView?
    var recategorizationEnabled = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button(action: onMore) {
                    DSIconView(icon: .more, size: DS.Size.icon, color: DS.Color.ink2)
                        .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                }.dsPressStyle().accessibilityLabel("更多操作").accessibilityIdentifier("billMore")
            }.padding(.trailing, DS.Space.s12)
            VStack(spacing: 0) {
                Text(name).dsText(HomeSpec.billName).foregroundStyle(DS.Color.ink3).multilineTextAlignment(.center)
                Text(amount).dsText(DS.Font.nDetail).foregroundStyle(amountColor)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                if let route {
                    HStack(spacing: HomeSpec.gap6) {
                        routePill(route.0, positive: false)
                        DSIconView(icon: .chevron, size: DS.Space.s16, color: DS.Color.ink3)
                        routePill(route.1, positive: true)
                    }.padding(.top, DS.Space.s8)
                }
                if !impact.isEmpty {
                    HStack(spacing: DS.Space.s4) {
                        Text(impact).foregroundStyle(foreign ? DS.Color.ink3 : DS.Color.accentInk)
                        if !effectValue.isEmpty { Text(effectValue).fontWeight(.semibold) }
                        if !effectTail.isEmpty { Text(effectTail) }
                    }.dsText(DS.Font.tLabel).monospacedDigit()
                        .foregroundStyle(foreign ? DS.Color.ink : DS.Color.accentInk)
                        .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                        .padding(.horizontal, DS.Space.s12).frame(minHeight: HomeSpec.effectHeight)
                        .dsPill(foreign ? DS.Color.surface : DS.Color.accentSoft).padding(.top, HomeSpec.formulaTop)
                }
            }.padding(.horizontal, HomeSpec.billCenterInset)
            if let recovery { recovery.padding(.horizontal, DS.Space.s16).padding(.top, HomeSpec.recoveryTop) }
            else if let warning {
                Text(warning).dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.warnInk)
                    .dsFillWidth().padding(DS.Space.s16).dsSurface(DS.Color.warnSoft, radius: DS.Radius.m)
                    .padding(.horizontal, DS.Space.s16).padding(.top, HomeSpec.recoveryTop)
            }
            VStack(spacing: HomeSpec.gap6) {
                if let note, !note.isEmpty {
                    HStack(spacing: HomeSpec.gap6) {
                        DSIconView(icon: .edit, size: HomeSpec.chevron, color: DS.Color.ink3)
                        Text(note).dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink2).multilineTextAlignment(.center)
                    }
                }
                Text(metadata).dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .multilineTextAlignment(.center)
            }.padding(.horizontal, HomeSpec.billCenterInset).padding(.top, HomeSpec.billCenterInset)
            DSButton("完成", kind: .secondary, action: onDone)
                .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s20)
                .accessibilityIdentifier("closeBill")
        }.frame(maxWidth: .infinity)
            .padding(.top, HomeSpec.billCardTop).padding(.bottom, DS.Space.s20)
            .dsSurface(DS.Color.raised, radius: DS.Radius.float).dsShadow(DS.Shadow.float)
            .overlay(alignment: .topTrailing) {
                if showsMenu {
                    DSFloatingMenu(onEdit: onEdit, onRecategorize: onRecategorize, onDuplicate: onDuplicate,
                                   onDelete: onDelete, recategorizationEnabled: recategorizationEnabled)
                        .padding(.top, HomeSpec.menuTop).padding(.trailing, DS.Space.s12)
                        .transition(reduceMotion ? .opacity : .scale(scale: DSInteraction.floatScale, anchor: .topTrailing).combined(with: .opacity))
                }
            }.animation(reduceMotion ? DSMotion.reduceMotionAnimation : DSMotion.snappyAnimation, value: showsMenu)
    }

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private func routePill(_ route: Route, positive: Bool) -> some View {
        HStack(spacing: HomeSpec.gap6) {
            DSIconView(icon: route.icon, size: HomeSpec.routeIcon, color: positive ? DS.Color.accentInk : DS.Color.ink2)
            Text(route.title).dsText(HomeSpec.routeName).lineLimit(1)
        }.foregroundStyle(positive ? DS.Color.accentInk : DS.Color.ink2)
            .padding(.horizontal, DS.Space.s12).frame(minHeight: DS.Size.chipH)
            .dsPill(positive ? DS.Color.accentSoft : DS.Color.surface)
    }
}

struct DSSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: DS.Space.s16) {
            Text(title).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                .frame(maxWidth: .infinity, minHeight: DS.Size.tapMin)
            content()
        }.padding(DS.Space.s16).dsFillWidth().background(DS.Color.bg)
    }
}

private struct DSSheetPresenter<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheetContent: () -> SheetContent
    @State private var contentHeight = DS.Size.buttonH
    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            sheetContent().fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if height > 0 { contentHeight = height }
                }
                .presentationDetents([.height(contentHeight)])
                .presentationCornerRadius(DS.Radius.sheet)
                .presentationBackground(DS.Color.bg)
                .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    func dsSheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(DSSheetPresenter(isPresented: isPresented, sheetContent: content))
    }
}

struct DSSegmented: View {
    let options: [String]
    @Binding var selection: String
    var width: CGFloat? = HomeSpec.segmentedWidth
    var identifierPrefix: String? = nil
    /// The small 30 pt control inside a settings row.
    var compact = false
    @Namespace private var thumb
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    var body: some View {
        let reduceMotion = reduceMotionOverride ?? systemReduceMotion
        let inset = compact ? SettingsSpec.toneInset : DS.Size.segmentedInset
        let height = compact ? SettingsSpec.toneHeight : DS.Size.pillH
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(option).dsText(compact ? DS.Font.tSub : DS.Font.tPill).fontWeight(selection == option ? .semibold : .regular)
                        .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                        .foregroundStyle(selection == option ? DS.Color.ink : DS.Color.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, inset)
                        .frame(minHeight: height)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: DS.Radius.s - DS.Size.segmentedInset, style: .continuous)
                                    .fill(DS.Color.selected).dsShadow(DS.Shadow.near)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                                    .padding(.vertical, inset)
                            }
                        }.frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
                }.dsPressStyle().accessibilityAddTraits(selection == option ? .isSelected : [])
                    .accessibilityIdentifier(identifierPrefix.map { $0 + option } ?? "")
            }
        }.padding(.horizontal, inset)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).fill(DS.Color.surface).frame(height: height)
            }
            .frame(width: typeSize.isAccessibilitySize ? nil : width)
            .animation(enabled ? (reduceMotion ? nil : DSMotion.snappyAnimation) : nil, value: selection)
            .sensoryFeedback(DSMotion.Haptic.toggle, trigger: selection)
    }
}

struct DSButton: View {
    enum Kind { case primary, secondary, text }
    let title: String
    var kind: Kind
    var enabled: Bool
    var action: () -> Void
    init(_ title: String, kind: Kind = .primary, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.kind = kind; self.enabled = enabled; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).dsText(kind == .text ? DS.Font.tLabelStrong : DS.Font.tTitle)
                .lineLimit(1)
                .foregroundStyle(kind == .primary ? DS.Color.onAccent : (kind == .text ? DS.Color.accentInk : DS.Color.ink))
                .frame(maxWidth: kind == .text ? nil : .infinity, minHeight: kind == .text ? DS.Size.tapMin : DS.Size.buttonH)
                .padding(.horizontal, DS.Space.s16)
                .dsPill(kind == .primary ? DS.Color.accent : (kind == .secondary ? DS.Color.surface : .clear))
                .opacity(enabled ? 1 : DSInteraction.reducedPressOpacity)
        }.dsPressStyle().disabled(!enabled)
    }
}

struct DSAlertCard: View {
    enum Tone { case warning, positive }
    let title: String
    var detail = ""
    var value = ""
    var tone: Tone = .warning
    var subtitle: String? = nil
    var onTap: () -> Void = {}
    var body: some View {
        Button(action: onTap) {
            if let subtitle {
                HStack(spacing: DS.Space.s12) {
                    VStack(alignment: .leading, spacing: OverviewSpec.alertSubtitleGap) {
                        Text(title).dsText(DS.Font.tLabelStrong).monospacedDigit()
                        Text(subtitle).dsText(DS.Font.tSub).monospacedDigit()
                    }.dsFillWidth()
                    DSIconView(icon: .chevron, size: DS.Space.s16, color: DS.Color.warnInk)
                }
                .foregroundStyle(DS.Color.warnInk)
                .padding(.leading, DS.Space.s16).padding(.trailing, DS.Space.s12)
                .padding(.vertical, OverviewSpec.alertVertical)
                .dsSurface(DS.Color.warnSoft, radius: DS.Radius.m)
            } else {
                singleLine
            }
        }.dsPressStyle()
    }

    private var singleLine: some View {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                HStack(spacing: DS.Space.s8) {
                    Text(title).dsText(DS.Font.tLabelStrong).fixedSize()
                    if !detail.isEmpty { Text(detail).dsText(DS.Font.tSub).lineLimit(1) }
                }.dsFillWidth()
                Text(value).dsText(tone == .positive ? DS.Font.nSpine : DS.Font.tLabel).monospacedDigit().fixedSize()
                if tone == .warning {
                    DSIconView(icon: .chevron, size: DS.Font.tCaption.size, color: DS.Color.warnInk)
                }
            }.foregroundStyle(tone == .warning ? DS.Color.warnInk : DS.Color.accentInk)
                .frame(minHeight: tone == .positive ? DS.Size.tapMin : nil)
                .padding(.horizontal, DS.Space.s16).padding(.vertical, tone == .warning ? HomeSpec.formulaTop : 0)
                .background(tone == .warning ? DS.Color.warnSoft : DS.Color.accentSoft)
                .clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
    }
}

enum DSChartPalette {
    static func colors(anomalies: [Bool]) -> [Color] {
        let palette = [DS.Color.chart1, DS.Color.chart2, DS.Color.chart3, DS.Color.chart4, DS.Color.chart5]
        var index = 0
        return anomalies.map { anomaly in
            if anomaly { return DS.Color.warn }
            defer { index += 1 }
            return palette.indices.contains(index) ? palette[index] : DS.Color.track
        }
    }
}

struct DSDonut: View {
    struct Slice: Identifiable {
        let id: String
        let name: String
        let value: Double
        let amount: String
        var isAnomaly = false
        var delta: String? = nil
    }
    let slices: [Slice]
    var identifierPrefix = "overviewCategory_"
    var showsShares = true
    var hidesAmounts = false
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        let sorted = slices.filter { $0.value > 0 }.sorted {
            hidesAmounts || $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value
        }
        let total = sorted.reduce(0) { $0 + $1.value }
        let colors = hidesAmounts ? Array(repeating: DS.Color.ink3, count: sorted.count)
            : DSChartPalette.colors(anomalies: sorted.map(\.isAnomaly))
        let ends = sorted.reduce(into: [0.0]) { boundaries, slice in
            let share = hidesAmounts ? 1 / Double(sorted.count) : slice.value / total
            boundaries.append((boundaries.last ?? 0) + share)
        }
        let gap = Double(OverviewSpec.donutGap / OverviewSpec.donutCenterline) / .pi

        VStack(spacing: DS.Space.s8) {
            ZStack {
                Circle().stroke(DS.Color.track, lineWidth: DS.Size.donutStroke)
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, slice in
                    let start = ends[index]
                    let end = ends[index + 1]
                    let inset = sorted.count == 1 ? 0 : min(gap, (end - start) / 2)
                    Circle().trim(from: start, to: end - inset)
                        .stroke(colors[index], lineWidth: DS.Size.donutStroke)
                        .rotationEffect(.radians(-.pi / 2))
                }
                if !hidesAmounts, let largest = sorted.first {
                    VStack(spacing: .zero) {
                        Text("最多").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                        Text(largest.name).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                            .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                    }.padding(DS.Space.s12)
                }
            }.padding(OverviewSpec.donutInset)
                .frame(width: DS.Size.donut, height: DS.Size.donut)
                .accessibilityHidden(true)
            VStack(spacing: .zero) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, slice in
                    Button { onSelect(slice.id) } label: {
                        DSOverviewLegendRow(name: slice.name, amount: slice.amount, color: colors[index],
                                            share: showsShares && !hidesAmounts ? (slice.value / total).formatted(.percent.precision(.fractionLength(0))) : nil,
                                            delta: hidesAmounts ? nil : slice.delta, isAnomaly: !hidesAmounts && slice.isAnomaly)
                        .frame(minHeight: DS.Size.tapMin)
                        .contentShape(Rectangle())
                    }.dsPressStyle().accessibilityIdentifier(identifierPrefix + slice.id)
                }
            }.dsFillWidth()
        }.frame(maxWidth: .infinity)
    }
}

struct DSOverviewLegendRow: View {
    let name: String
    let amount: String
    let color: Color
    let share: String?
    let delta: String?
    let isAnomaly: Bool
    var isDrill = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ink = isAnomaly ? DS.Color.warnInk : DS.Color.ink
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: OverviewSpec.legendGap))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: OverviewSpec.legendGap) {
                DSOverviewSwatch(color: color).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                Text(name).dsText(isDrill ? DS.Font.tBody : DS.Font.tLabel)
                    .fontWeight(isAnomaly ? .semibold : .regular).foregroundStyle(ink).lineLimit(stacked ? nil : 1)
                if let share {
                    Text(share).dsText(isDrill ? DS.Font.tSub : DS.Font.tCaption)
                        .monospacedDigit().foregroundStyle(DS.Color.ink3).fixedSize()
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: OverviewSpec.legendGap) {
                Spacer(minLength: .zero)
                if let delta {
                    Text(delta).dsText(DS.Font.tCaption).monospacedDigit()
                        .fontWeight(isAnomaly || !isDrill ? .semibold : .regular)
                        .foregroundStyle(isAnomaly ? DS.Color.warnInk : DS.Color.ink3).fixedSize()
                }
                Text(amount).dsText(OverviewSpec.legendAmount).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                    .frame(minWidth: OverviewSpec.legendAmountWidth, alignment: .trailing)
            }
        }
        .padding(.vertical, stacked ? DS.Space.s4 : .zero)
        .accessibilityElement(children: .combine)
    }
}

struct DSOverviewSwatch: View {
    let color: Color
    var size = DS.Size.legendSwatch

    var body: some View {
        Rectangle().fill(color).frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: DS.Radius.xs, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct DSSubCalendar: View {
    struct Day: Identifiable {
        let number: Int
        var brand: String? = nil
        var color: Color = DS.Color.accent
        var id: Int { number }
    }
    let days: [Day]
    var leadingEmptyDays = 0
    var onSelect: (Int) -> Void = { _ in }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s4), count: DSLayout.weekdays), spacing: DS.Space.s4) {
            ForEach(-max(0, leadingEmptyDays)..<0, id: \.self) { _ in Color.clear.frame(height: DS.Size.tapMin) }
            ForEach(days) { day in
                Button { onSelect(day.number) } label: {
                    VStack(spacing: DS.Size.segmentedInset) {
                        Text("\(day.number)").dsText(DS.Font.tSub).monospacedDigit()
                        if let brand = day.brand {
                            Text(brand).dsText(DS.Font.tTab).foregroundStyle(DS.Color.onAccent)
                                .frame(width: DS.Size.brandTile, height: DS.Size.brandTile)
                                .dsSurface(day.color, radius: DS.Radius.xs)
                        }
                    }.foregroundStyle(DS.Color.ink).frame(maxWidth: .infinity, minHeight: DS.Size.tapMin, alignment: .top)
                        .background(day.brand == nil ? .clear : DS.Color.surface)
                        .clipShape(.rect(cornerRadius: DS.Radius.s, style: .continuous))
                }.dsPressStyle().accessibilityLabel("\(day.number) 日\(day.brand.map { " · " + $0 } ?? "")")
            }
        }.padding(DS.Space.s12).background(DS.Color.raised).clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
    }
}

/// Self-drawn switch. VoiceOver reads it as a native switch.
struct DSSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var showsTitle = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled
    var body: some View {
        HStack(spacing: DS.Space.s12) {
            if showsTitle {
                Text(title).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2)
                Spacer(minLength: .zero)
            }
            Button { isOn.toggle() } label: {
                Capsule(style: .continuous).fill(isOn ? DS.Color.accent : DS.Color.track)
                    .frame(width: DS.Size.switchW, height: DS.Size.switchH)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(DS.Color.knob).frame(width: DS.Size.switchKnob, height: DS.Size.switchKnob)
                            .dsShadow(DS.Shadow.near).padding(.horizontal, SettingsSpec.knobInset)
                    }
                    .frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
            }
            .dsPressStyle()
            .opacity(enabled ? 1 : SettingsSpec.disabledOpacity)
            .animation(animationsEnabled && !(reduceMotionOverride ?? systemReduceMotion) ? DSMotion.snappyAnimation : nil, value: isOn)
        }
        .frame(minHeight: DS.Size.tapMin)
        .sensoryFeedback(DSMotion.Haptic.toggle, trigger: isOn)
        .accessibilityRepresentation { Toggle(title, isOn: $isOn) }
    }
}

struct DSInlineTextField: View {
    let title: String
    @Binding var text: String
    var decimal = false
    var autoFocus = true
    var secure = false
    var embedded = false
    var previewCaretSize: CGSize?
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if embedded {
                field.dsText(DS.Font.tPill)
                    .overlay(alignment: .leading) {
                        if let previewCaretSize, !focused, !text.isEmpty {
                            HStack(spacing: DS.Space.s4) {
                                Text(text).dsText(DS.Font.tPill).hidden()
                                Capsule(style: .continuous).fill(DS.Color.accent)
                                    .frame(width: previewCaretSize.width, height: previewCaretSize.height)
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                    }
            } else {
                field.dsText(DS.Font.tBody)
                    .padding(.horizontal, DS.Space.s12)
                    .frame(minHeight: DS.Size.tapMin)
                    .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                    .overlay {
                        if focused {
                            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                                .strokeBorder(DS.Color.accent, lineWidth: DS.Stroke.focus)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .onAppear { if autoFocus { focused = true } }
    }

    private var field: some View {
        let prompt = Text(title).foregroundStyle(DS.Color.ink3)
        return Group {
            if secure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
            }
        }
            .accessibilityLabel(title)
            #if os(iOS)
            .keyboardType(decimal ? .decimalPad : .default)
            #endif
            .tint(DS.Color.accent)
            .textFieldStyle(.plain)
            .foregroundStyle(DS.Color.ink)
            .focused($focused)
            .onSubmit(onSubmit)
    }
}

struct DSCalendarPopover: View {
    let date: Date
    let now: Date
    @Binding var displayedMonth: Date
    var repeats = false
    var canRepeat = true
    var onSelect: (Date) -> Void = { _ in }
    var onRepeat: () -> Void = {}

    static func initialMonth(for date: Date, now: Date) -> Date {
        monthStart(for: min(date, now))
    }

    private static func monthStart(for date: Date) -> Date {
        Dates.calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private var calendar: Calendar { Dates.calendar }
    private var currentMonth: Date { Self.monthStart(for: now) }
    private var month: Date { displayedMonth }
    private var monthTitle: String {
        "\(calendar.component(.year, from: month))年\(calendar.component(.month, from: month))月"
    }

    var body: some View {
        VStack(spacing: .zero) {
            HStack(spacing: .zero) {
                Text(monthTitle).dsText(DS.Font.tBody).fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                Spacer(minLength: .zero)
                arrow(.back, offset: -1, label: "上个月")
                arrow(.chevron, offset: 1, label: "下个月")
            }
            .padding(.horizontal, DS.Space.s4)
            .frame(minHeight: EntrySpec.calendarHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: .zero), count: DSLayout.weekdays), spacing: .zero) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) {
                    Text($0).dsText(DS.Font.tTag).fontWeight(.regular)
                        .foregroundStyle(DS.Color.ink3).frame(minHeight: DS.Space.s20)
                }
                ForEach((1 - calendar.component(.weekday, from: month))..<0, id: \.self) { _ in
                    Color.clear.frame(height: EntrySpec.calendarDay).accessibilityHidden(true)
                }
                ForEach(calendar.range(of: .day, in: .month, for: month) ?? (1..<1), id: \.self) { day in
                    dayCell(day, date: Dates.addDays(day - 1, to: month))
                }
            }
            .padding(.top, DS.Space.s4)

            DS.Color.separator.frame(height: DS.Stroke.hairline)
                .padding(.top, DS.Space.s8)
            HStack(spacing: DS.Space.s8) {
                quick("今天", offset: 0)
                quick("昨天", offset: -1)
                Spacer(minLength: .zero)
                if canRepeat {
                    chip("每月", icon: .subscription, selected: repeats, action: onRepeat)
                }
            }
            .padding(.top, EntrySpec.calendarGap)
        }
        .padding(.top, DS.Space.s12)
        .padding(.horizontal, EntrySpec.trailingPadding)
        .padding(.bottom, EntrySpec.trailingPadding)
        .frame(maxWidth: EntrySpec.calendarWidth)
        .dsSurface(DS.Color.raised, radius: DS.Radius.m)
        .dsShadow(DS.Shadow.float)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("日历")
    }

    private func arrow(_ icon: DS.Icon, offset: Int, label: String) -> some View {
        let disabled = offset > 0 && month >= currentMonth
        return Button {
            if let next = calendar.date(byAdding: .month, value: offset, to: month) {
                displayedMonth = next
            }
        } label: {
            icon.view(size: EntrySpec.routeIcon, color: disabled ? DS.Color.chevron : DS.Color.ink3)
                .frame(width: DS.Size.tapMin, height: EntrySpec.calendarHeader)
                .contentShape(Rectangle())
        }.buttonStyle(EntryTactileButtonStyle()).disabled(disabled).accessibilityLabel(label)
    }

    private func dayCell(_ day: Int, date value: Date) -> some View {
        let selected = calendar.isDate(value, inSameDayAs: date)
        let today = calendar.isDate(value, inSameDayAs: now)
        let future = Dates.day(value) > Dates.day(now)
        return Button { onSelect(value) } label: {
            Text(day.formatted()).dsText(DS.Font.tLabel).monospacedDigit()
                .fontWeight(selected || today ? .semibold : .regular)
                .frame(width: DS.Size.chipH, height: DS.Size.chipH)
                .foregroundStyle(future ? DS.Color.chevron : selected ? DS.Color.raised : DS.Color.ink)
                .background(selected && !future ? DS.Color.ink : .clear, in: Circle())
                .frame(maxWidth: .infinity, minHeight: EntrySpec.calendarDay)
                .contentShape(Rectangle())
        }
        .buttonStyle(EntryTactileButtonStyle())
        .disabled(future)
        .accessibilityLabel(monthTitle + "\(day)日")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func quick(_ title: String, offset: Int) -> some View {
        let value = Dates.addDays(offset, to: Dates.day(now))
        return chip(title, selected: calendar.isDate(date, inSameDayAs: value)) { onSelect(value) }
            .accessibilityIdentifier("entryQuick_" + title)
    }

    private func chip(_ title: String, icon: DS.Icon? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: EntrySpec.gap) {
                if let icon { icon.view(size: DS.Font.tLabel.size, color: selected ? DS.Color.ink : DS.Color.ink3) }
                Text(title).dsText(DS.Font.tPill).fontWeight(selected ? .semibold : .regular)
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? DS.Color.ink : DS.Color.ink2)
            .padding(.leading, icon == nil ? DS.Space.s12 : EntrySpec.compactPadding)
            .padding(.trailing, DS.Space.s12)
            .frame(minHeight: DS.Size.chipH)
            .dsPill(selected ? DS.Color.selected : DS.Color.surface)
        }
        .buttonStyle(EntryTactileButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if os(iOS)
/// A hidden navigation bar drops the default gesture's eligibility check.
private struct DSEdgeSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var edgeSwipe: UIGestureRecognizer?
        private weak var originalDelegate: (any UIGestureRecognizerDelegate)?
        private var wasEnabled = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let edge = navigationController?.interactivePopGestureRecognizer, edge.delegate !== self else { return }
            edgeSwipe = edge
            originalDelegate = edge.delegate
            wasEnabled = edge.isEnabled
            edge.delegate = self
            edge.isEnabled = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            guard let edgeSwipe, edgeSwipe.delegate === self else { return }
            edgeSwipe.delegate = originalDelegate
            edgeSwipe.isEnabled = wasEnabled
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController else { return false }
            return navigationController.viewControllers.count > 1 && navigationController.transitionCoordinator == nil
        }
    }
}
#endif

extension View {
    @ViewBuilder func dsEdgeSwipeBack() -> some View {
        #if os(iOS)
        background(DSEdgeSwipe().allowsHitTesting(false))
        #else
        self
        #endif
    }
}

struct DSStackedBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    enum Kind { case drill, assets }
    let segments: [Segment]
    var kind: Kind = .drill
    var hidesAmounts = false

    var body: some View {
        let positive = hidesAmounts ? segments.map { Segment(id: $0.id, value: 1, color: DS.Color.ink3) }
            : segments.filter { $0.value > 0 }
        let total = positive.reduce(0) { $0 + $1.value }
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - CGFloat(max(0, positive.count - 1)) * OverviewSpec.barGap)
            HStack(spacing: OverviewSpec.barGap) {
                ForEach(positive) { segment in
                    Rectangle().fill(segment.color).frame(width: width * CGFloat(segment.value / total))
                }
            }.background(positive.isEmpty ? DS.Color.track : DS.Color.bg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.background(DS.Color.track)
            .frame(height: kind == .drill ? OverviewSpec.drillBarHeight : OverviewSpec.assetsBarHeight)
            .clipShape(kind == .drill ? AnyShape(DS.Shape.pill) : AnyShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)))
            .accessibilityHidden(true)
    }
}

struct DSBalanceChart: View {
    let values: [Int64]
    let startLabel: String
    let highlightLabel: String?
    let highlightIndex: Int?
    let endLabel: String
    var hidesAmounts = false

    var body: some View {
        let _ = OverviewRenderCounts.hit("balanceChartBody")
        let visibleHighlight = hidesAmounts ? nil : highlightLabel
        VStack(spacing: OverviewSpec.headingGap) {
            GeometryReader { geometry in
                let points = plot(in: geometry.size)
                let line = Path { path in path.addLines(points) }
                Path { path in
                    guard let first = points.first, let last = points.last else { return }
                    path.addLines(points)
                    path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: first.x, y: geometry.size.height))
                    path.closeSubpath()
                }.fill(DS.Color.accent.opacity(OverviewSpec.chartAreaOpacity))
                BalanceChartStroke(line: line)
                if !hidesAmounts, let index = highlightIndex, points.indices.contains(index) {
                    Circle().fill(DS.Color.bg)
                        .overlay(Circle().strokeBorder(DS.Color.accent, lineWidth: DS.Stroke.focus))
                        .frame(width: OverviewSpec.chartHighlightDot, height: OverviewSpec.chartHighlightDot)
                        .position(points[index])
                }
                if let last = points.last {
                    Circle().fill(DS.Color.accent)
                        .overlay(Circle().stroke(DS.Color.bg, lineWidth: OverviewSpec.chartStroke))
                        .frame(width: OverviewSpec.chartEndDot, height: OverviewSpec.chartEndDot)
                        .position(last)
                }
            }.frame(height: OverviewSpec.chartHeight)
            HStack {
                Text(startLabel)
                Spacer(minLength: DS.Space.s4)
                if let visibleHighlight {
                    Text(visibleHighlight).lineLimit(1)
                    Spacer(minLength: DS.Space.s4)
                }
                Text(endLabel)
            }.dsText(OverviewSpec.tiny).foregroundStyle(DS.Color.ink3)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("近 30 天余额走势")
            .accessibilityValue([startLabel, visibleHighlight, endLabel].compactMap { $0 }.joined(separator: "，"))
            .accessibilityIdentifier("accountBalanceChart")
    }

    private func plot(in size: CGSize) -> [CGPoint] {
        let values = hidesAmounts ? [Int64(0), 0] : values
        guard let minValue = values.min(), let maxValue = values.max() else { return [] }
        let range = Double(maxValue) - Double(minValue)
        let horizontal = max(0, size.width - 2 * OverviewSpec.chartHorizontalInset)
        let vertical = max(0, size.height - 2 * OverviewSpec.chartVerticalInset)
        return values.enumerated().map { index, value in
            let x = Double(index) / Double(max(1, values.count - 1))
            let y = range > 0 ? (Double(maxValue) - Double(value)) / range : 0.5
            return CGPoint(x: OverviewSpec.chartHorizontalInset + horizontal * x,
                           y: OverviewSpec.chartVerticalInset + vertical * y)
        }
    }
}

private struct BalanceChartStroke: View {
    let line: Path
    @State private var trimProgress = CGFloat.zero
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled

    var body: some View {
        let _ = OverviewRenderCounts.hit("balanceChartStroke")
        let animate = animationsEnabled && !(reduceMotionOverride ?? systemReduceMotion)
        line.trim(from: .zero, to: animate ? trimProgress : 1)
            .stroke(DS.Color.accent, style: StrokeStyle(lineWidth: OverviewSpec.chartStroke, lineCap: .round, lineJoin: .round))
            .allowsHitTesting(false)
            .onAppear {
                guard trimProgress == 0 else { return }
                withAnimation(animate ? DSMotion.smoothAnimation : nil) { trimProgress = 1 }
            }
    }
}

struct DSPeriodOptionGroup: View {
    struct Option: Identifiable {
        let id: String
        let title: String
        var range: String? = nil
    }

    let options: [Option]
    let selection: String
    var rowHeight = OverviewSpec.optionHeight
    var identifierPrefix = "overviewPeriod_"
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: .zero) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let selected = option.id == selection
                Button { onSelect(option.id) } label: {
                    HStack(spacing: OverviewSpec.legendGap) {
                        Text(option.title).dsText(DS.Font.tLabel).fontWeight(selected ? .semibold : .regular)
                        Spacer(minLength: .zero)
                        if let range = option.range {
                            Text(range).dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                                .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                        }
                        ZStack {
                            if selected {
                                Circle().fill(DS.Color.accent)
                                Circle().fill(DS.Color.onAccent).frame(width: DS.Space.s8, height: DS.Space.s8)
                            } else {
                                Circle().strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.focus)
                            }
                        }.frame(width: DS.Size.icon, height: DS.Size.icon).accessibilityHidden(true)
                    }.foregroundStyle(DS.Color.ink)
                        .frame(minHeight: rowHeight)
                        .contentShape(Rectangle())
                        .overlay(alignment: .top) {
                            if index > 0 { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                        }
                }.dsPressStyle()
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier(identifierPrefix + option.id)
            }
        }.padding(.horizontal, DS.Space.s16)
            .background(DS.Color.raised)
            .clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline).allowsHitTesting(false))
    }
}
