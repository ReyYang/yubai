import SwiftUI

struct DSInlineTag {
    enum Tone { case warning, positive }
    let title: String
    var tone: Tone = .warning
}

struct DSListRow: View {
    let icon: String
    let name: String
    let amount: String
    var detail: String? = nil
    var tag: DSInlineTag? = nil
    var separator = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s12) {
                Image(systemName: icon)
                    .font(.system(size: DS.Size.icon, weight: DS.Icon.Weight.list))
                    .foregroundStyle(DS.Color.iconQuiet).frame(width: DS.Size.icon)
                    .accessibilityHidden(true)
                HStack(spacing: DS.Space.s4) {
                    Text(name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).lineLimit(1)
                    if let tag {
                        Text(tag.title).dsText(DS.Font.tTag).lineLimit(1)
                            .foregroundStyle(tag.tone == .warning ? DS.Color.warnInk : DS.Color.accentInk)
                            .padding(.horizontal, DS.Space.s4)
                            .dsPill(tag.tone == .warning ? DS.Color.warnSoft : DS.Color.accentSoft)
                            .fixedSize()
                    }
                }.dsFillWidth()
                Text(amount).dsText(DS.Font.nSpine).foregroundStyle(DS.Color.ink)
                    .lineLimit(1).fixedSize()
            }
            if let detail {
                Text(detail).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3).dsFillWidth()
                    .padding(.leading, DS.Size.icon + DS.Space.s12)
            }
        }
        .padding(.vertical, DS.Space.s8)
        .frame(minHeight: detail == nil ? DS.Size.rowBill : DS.Size.rowBill2)
        .dsFillWidth()
        .overlay(alignment: .top) {
            if separator {
                Rectangle().fill(DS.Color.separator).frame(height: DS.Stroke.hairline)
                    .padding(.leading, DS.Size.icon + DS.Space.s12)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DSDayHeader: View {
    let title: String
    let total: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).dsText(DS.Font.tSubStrong)
            Spacer(minLength: DS.Space.s8)
            Text(total).dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3)
        }.foregroundStyle(DS.Color.ink).frame(minHeight: DS.Size.chipH).dsFillWidth()
    }
}

struct DSBudget: Identifiable {
    let id: String
    let name: String
    let total: String
    let remaining: String
    let usedFraction: Double
    var isWarning: Bool { usedFraction >= DSInteraction.warningFraction }
    var usedText: String { usedFraction.formatted(.percent.precision(.fractionLength(0))) }
}

private struct DSProgress: View {
    let fraction: Double
    var warning = false
    var amber = false
    var height = DS.Size.barCalm
    var body: some View {
        GeometryReader { geometry in
            Capsule(style: .continuous).fill(amber ? DS.Color.warnTrack : DS.Color.track)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous).fill(warning ? DS.Color.warn : DS.Color.fillCalm)
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
                    Text(budget.remaining).dsText(DS.Font.nSpineLg).foregroundStyle(DS.Color.ink)
                }
                DSProgress(fraction: budget.usedFraction)
            }.padding(.vertical, DS.Space.s8).frame(minHeight: DS.Size.rowBill2).dsFillWidth()
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
            Text(budget.remaining).dsText(DS.Font.nTile).foregroundStyle(DS.Color.ink)
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
        let icon: String
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
                            Image(systemName: item.icon)
                                .font(.system(size: DS.Size.icon, weight: DS.Icon.Weight.list))
                                .foregroundStyle(expanded ? DS.Color.accentInk : DS.Color.ink2)
                                .frame(width: DS.Size.iconTile, height: DS.Size.iconTile)
                                .dsSurface(expanded ? DS.Color.accentSoft : DS.Color.surface, radius: DS.Radius.s)
                            Text(item.title).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink).dsFillWidth()
                            Text("\(item.subitems.count) 个小类").dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink3)
                            Image(systemName: DS.Icon.chevron)
                                .font(.system(size: DS.Font.tPill.size, weight: DS.Icon.Weight.chevron))
                                .foregroundStyle(expanded ? DS.Color.ink : DS.Color.chevron)
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
                                Label("添加小类", systemImage: DS.Icon.add).dsText(DS.Font.tLabelStrong)
                                    .foregroundStyle(DS.Color.accentInk).dsFillWidth().frame(minHeight: DS.Size.rowSub)
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    @State private var appeared = false
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        VStack(spacing: DS.Space.s12) {
            HStack(alignment: .bottom, spacing: DS.Space.s8) {
                Button(action: onAmount) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: DS.Space.s4) {
                            Text("还能花").dsText(DS.Font.tSub)
                            Image(systemName: DS.Icon.chevron).font(.system(size: DS.Font.tCaption.size, weight: DS.Icon.Weight.chevron))
                        }.foregroundStyle(DS.Color.ink3)
                        Text(amount).dsText(DS.Font.nHero).foregroundStyle(DS.Color.ink).lineLimit(1)
                    }.dsFillWidth()
                }.dsPressStyle()
                VStack(alignment: .trailing, spacing: DS.Space.s4) {
                    Text("每天 \(daily)").dsText(DS.Font.tLabelStrong).monospacedDigit()
                    Text("还剩 \(remainingDays) 天").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                }.foregroundStyle(DS.Color.ink).fixedSize()
            }
            HStack(alignment: .bottom, spacing: DS.Size.dayBarGap) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Capsule(style: .continuous).fill(day.color).frame(height: day.height)
                        .scaleEffect(x: 1, y: reduceMotion || !enabled || appeared ? 1 : 0, anchor: .bottom)
                        .animation(enabled ? DSMotion.animation(.barGrow, reduceMotion: reduceMotion)?.delay(Double(index) * DSMotion.Role.barGrow.staggerDelay) : nil, value: appeared)
                }
            }.frame(height: DS.Size.dayBarsH, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    Rectangle().strokeBorder(DS.Color.chevron, style: StrokeStyle(lineWidth: DS.Stroke.hairline, dash: [DS.Space.s4]))
                        .frame(height: DS.Stroke.hairline)
                }.accessibilityHidden(true)
            HStack(spacing: DS.Space.s12) {
                ForEach(budgets.prefix(DSLayout.heroBudgets)) { budget in
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text(budget.name).dsText(DS.Font.tCaption)
                        Text(budget.remaining).dsText(DS.Font.tLabel).fontWeight(.medium).monospacedDigit()
                        DSProgress(fraction: budget.usedFraction, warning: budget.isWarning, height: DS.Size.barMini)
                    }.foregroundStyle(budget.isWarning ? DS.Color.warnInk : DS.Color.ink3).dsFillWidth()
                }
            }
        }.dsFillWidth().onAppear { appeared = true }
    }
}

struct DSTabBar: View {
    enum Tab: String { case home, overview }
    @Binding var selection: Tab
    var onEntry: () -> Void
    var body: some View {
        HStack(spacing: DS.Space.s12) {
            tab(.home, title: "首页", icon: DS.Icon.tabHome)
            Button(action: onEntry) {
                Label("记一笔", systemImage: DS.Icon.add).dsText(DS.Font.tTitle)
                    .labelStyle(.titleAndIcon).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(DS.Color.onAccent).padding(.horizontal, DS.Space.s28)
                    .frame(minHeight: DS.Size.ctaH).dsPill(DS.Color.accent)
            }.dsPressStyle()
            tab(.overview, title: "全景", icon: DS.Icon.tabOverview)
        }.padding(.horizontal, DS.Space.s12).padding(.vertical, DS.Space.s12)
            .dsFillWidth().dsBarMaterial(in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
    }
    private func tab(_ tab: Tab, title: String, icon: String) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: DS.Size.icon, weight: DS.Icon.Weight.nav))
                Text(title).dsText(DS.Font.tTab)
            }.foregroundStyle(selection == tab ? DS.Color.accentInk : DS.Color.ink3)
                .frame(maxWidth: .infinity, minHeight: DS.Size.tapMin)
        }.dsPressStyle().accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

struct DSAskBar: View {
    var onAsk: () -> Void = {}
    var onVoice: () -> Void = {}
    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Button(action: onAsk) {
                HStack(spacing: DS.Space.s8) {
                    Image(systemName: DS.Icon.search)
                    Text("问余白 · 搜账单").dsText(DS.Font.tLabel).lineLimit(1).dsFillWidth()
                }.frame(minHeight: DS.Size.askH)
            }.dsPressStyle()
            Button(action: onVoice) {
                Image(systemName: DS.Icon.voice).frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
            }.dsPressStyle().accessibilityLabel("语音记账")
        }.font(.system(size: DS.Size.icon, weight: DS.Icon.Weight.list))
            .foregroundStyle(DS.Color.ink3).padding(.leading, DS.Space.s16)
            .dsPill(DS.Color.raised)
            .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
    }
}

struct DSEntryPills: View {
    enum Time: String, CaseIterable { case today = "今天", yesterday = "昨天", dayBefore = "前天" }
    enum Exception: String, CaseIterable { case none = "", reserve = "走机动余钱", reimburse = "待报销", split = "待 AA" }
    let account: String
    @Binding var time: Time
    @Binding var timeExpanded: Bool
    @Binding var repeats: Bool
    @Binding var exception: Exception
    var repeatDay: Int
    var onAccount: () -> Void = {}
    var onCalendar: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pillRow
            ScrollView(.horizontal) { pillRow }
                .scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
            .animation(DSMotion.animation(.accordion, reduceMotion: reduceMotionOverride ?? systemReduceMotion), value: timeExpanded)
    }
    private var pillRow: some View {
        HStack(spacing: DS.Space.s8) {
            if timeExpanded {
                ForEach(Time.allCases, id: \.self) { option in
                    pill(option.rawValue, icon: nil, selected: time == option) { time = option; timeExpanded = false }
                }
                pill("日历", icon: DS.Icon.cycle, iconOnly: true, action: onCalendar)
                pill("每月", icon: DS.Icon.subscription, selected: repeats) {
                    repeats.toggle(); exception = .none; timeExpanded = false
                }
            } else {
                pill(account, icon: DS.Icon.acctDebit, action: onAccount)
                pill(repeats && exception == .none ? "\(time.rawValue) · 每月 \(repeatDay) 日" : time.rawValue,
                     icon: repeats && exception == .none ? DS.Icon.subscription : DS.Icon.time,
                     selected: repeats && exception == .none) { timeExpanded = true }
                pill(exception == .none ? "更多" : exception.rawValue, icon: DS.Icon.more,
                     selected: exception != .none, iconOnly: exception == .none) {
                    let all = Exception.allCases
                    let next = ((all.firstIndex(of: exception) ?? 0) + 1) % all.count
                    exception = all[next]
                    if exception != .none { repeats = false }
                }
            }
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func pill(_ title: String, icon: String?, selected: Bool = false, iconOnly: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: DS.Font.tLabel.size, weight: DS.Icon.Weight.list))
                        .foregroundStyle(selected ? DS.Color.ink : DS.Color.ink3)
                }
                if !iconOnly { Text(title).dsText(DS.Font.tPill).fontWeight(selected ? .semibold : .regular) }
            }.lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selected ? DS.Color.ink : DS.Color.ink2)
                .padding(.horizontal, DS.Space.s12).frame(minHeight: DS.Size.pillH)
                .dsPill(selected ? DS.Color.selected : DS.Color.surface)
        }.dsPressStyle().accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DSKeypad: View {
    var onKey: (String) -> Void = { _ in }
    private let keys = ["1", "2", "3", "⌫", "4", "5", "6", "+", "7", "8", "9", "−", ".", "0", "00", "记下"]
    @State private var saves = 0
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s8), count: DSLayout.keypadColumns), spacing: DS.Space.s8) {
            ForEach(keys, id: \.self) { key in
                Button {
                    onKey(key)
                    if key == "记下" { saves += 1 }
                } label: {
                    Text(key).dsText(key == "记下" ? DS.Font.tTitle : DS.Font.nKey)
                        .foregroundStyle(key == "记下" ? DS.Color.onAccent : DS.Color.ink)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.keyH)
                        .dsSurface(key == "记下" ? DS.Color.accent : (["⌫", "+", "−"].contains(key) ? DS.Color.keyFn : DS.Color.key), radius: DS.Radius.s)
                        .dsShadow(DS.Shadow.key)
                }.dsPressStyle().accessibilityLabel(key == "⌫" ? "退格" : key)
            }
        }.padding(DS.Space.s8).background(DS.Color.tray).clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
            .sensoryFeedback(DSMotion.Haptic.save, trigger: saves)
    }
}

struct DSCategoryPicker: View {
    struct Category: Identifiable {
        let id: String
        let name: String
        let icon: String
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
                            Image(systemName: category.icon)
                                .font(.system(size: DS.Font.nKey.size, weight: DS.Icon.Weight.list))
                                .foregroundStyle(selected ? DS.Color.accentInk : DS.Color.ink2)
                                .frame(width: DS.Size.catCircle, height: DS.Size.catCircle)
                                .dsPill(selected ? DS.Color.accentSoft : DS.Color.surface)
                                .overlay(alignment: .topTrailing) {
                                    if category.suggested {
                                        Circle().fill(DS.Color.accent).frame(width: DS.Space.s8, height: DS.Space.s8)
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
                        Image(systemName: DS.Icon.add).foregroundStyle(DS.Color.ink2)
                            .frame(width: DS.Size.chipH, height: DS.Size.chipH).dsPill()
                    }.dsPressStyle().accessibilityLabel("添加小类")
                }
            }.scrollIndicators(.hidden)
        }.dsFillWidth()
    }
}

struct DSResultStrip: View {
    let title: String
    let detail: String
    let value: String
    var unchanged = false
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                labels
                Text(value).dsText(DS.Font.nKey).fontWeight(.semibold).fixedSize()
                    .foregroundStyle(unchanged ? DS.Color.ink : DS.Color.accentInk)
            }
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                labels
                Text(value).dsText(DS.Font.nKey).fontWeight(.semibold)
                    .foregroundStyle(unchanged ? DS.Color.ink : DS.Color.accentInk)
            }
        }.dsFillWidth().dsSurface(DS.Color.surface, radius: DS.Radius.m,
                                 padding: EdgeInsets(top: DS.Space.s8, leading: DS.Space.s16, bottom: DS.Space.s8, trailing: DS.Space.s16))
            .accessibilityElement(children: .combine)
    }
    private var labels: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
            Text(title).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2)
            Text(detail).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3).dsFillWidth()
        }
    }
}

struct DSFloatingMenu: View {
    var onEdit: () -> Void = {}
    var onRecategorize: () -> Void = {}
    var onDuplicate: () -> Void = {}
    var onDelete: () -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            item("编辑", icon: DS.Icon.edit, action: onEdit)
            item("改分类", icon: DS.Icon.recategorize, action: onRecategorize)
            item("再记一笔一样的", icon: DS.Icon.duplicate, action: onDuplicate)
            item("删除", icon: DS.Icon.delete, warning: true, action: onDelete)
                .padding(.top, DS.Space.s4)
                .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
        }.padding(.vertical, DS.Space.s4).frame(width: DS.Size.menuW)
            .background(DS.Color.raised).clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous)).dsShadow(DS.Shadow.float)
    }
    private func item(_ title: String, icon: String, warning: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).dsText(DS.Font.tBody)
                .foregroundStyle(warning ? DS.Color.warnInk : DS.Color.ink)
                .dsFillWidth().frame(minHeight: DS.Size.tapMin).padding(.horizontal, DS.Space.s16)
        }.dsPressStyle()
    }
}

/// Place above the page in a ZStack; scrim and card share the presentation lifetime.
struct DSFloatingCard: View {
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    @State private var appeared = false
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    var body: some View {
        ZStack {
            DS.Color.scrim.ignoresSafeArea().onTapGesture(perform: onDone).accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: DS.Space.s20) {
                VStack(spacing: DS.Space.s8) {
                    HStack {
                        Spacer(minLength: 0)
                        Button(action: onMore) {
                            Image(systemName: DS.Icon.more).foregroundStyle(DS.Color.ink3)
                                .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                        }.dsPressStyle().accessibilityLabel("更多操作")
                    }
                    Text(name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink3)
                    Text(amount).dsText(DS.Font.nDetail).foregroundStyle(DS.Color.ink)
                    Text(impact).dsText(DS.Font.tSub).foregroundStyle(DS.Color.accentInk)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, DS.Space.s12).dsPill(DS.Color.accentSoft)
                    if let warning {
                        Text(warning).dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.warnInk)
                            .dsFillWidth().dsSurface(DS.Color.warnSoft, radius: DS.Radius.m,
                                                    padding: EdgeInsets(top: DS.Space.s12, leading: DS.Space.s16, bottom: DS.Space.s12, trailing: DS.Space.s16))
                    }
                    if let note { Label(note, systemImage: DS.Icon.edit).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2) }
                    Text(metadata).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3).padding(.top, DS.Space.s12)
                    DSButton("完成", kind: .secondary, action: onDone).padding(.top, DS.Space.s4)
                }.padding(.horizontal, DS.Space.s20).padding(.bottom, DS.Space.s20)
                    .dsFillWidth().background(DS.Color.raised)
                    .clipShape(.rect(cornerRadius: DS.Radius.float, style: .continuous)).dsShadow(DS.Shadow.float)
                if showsMenu {
                    DSFloatingMenu(onEdit: onEdit, onRecategorize: onRecategorize, onDuplicate: onDuplicate, onDelete: onDelete)
                }
            }.padding(DS.Space.s16)
                .opacity(appeared || !enabled ? 1 : 0)
                .animation(enabled ? DSMotion.animation(.floatCard, reduceMotion: reduceMotion, property: .opacity) : nil, value: appeared)
                .scaleEffect(reduceMotion || appeared || !enabled ? 1 : DSInteraction.floatScale)
                .animation(enabled ? DSMotion.animation(.floatCard, reduceMotion: reduceMotion) : nil, value: appeared)
        }.onAppear { appeared = true }
    }
}

struct DSSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: DS.Space.s16) {
            ZStack {
                Text(title).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: DS.Icon.close).foregroundStyle(DS.Color.ink3)
                            .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                    }.dsPressStyle().accessibilityLabel("关闭")
                    Spacer(minLength: 0)
                }
            }.frame(minHeight: DS.Size.tapMin)
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
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(option).dsText(DS.Font.tPill).fontWeight(selection == option ? .semibold : .regular)
                        .lineLimit(1)
                        .foregroundStyle(selection == option ? DS.Color.ink : DS.Color.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Size.segmentedInset)
                        .frame(minHeight: DS.Size.pillH)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: DS.Radius.s - DS.Size.segmentedInset, style: .continuous)
                                    .fill(DS.Color.selected).dsShadow(DS.Shadow.near)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                                    .padding(.vertical, DS.Size.segmentedInset)
                            }
                        }.frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
                }.dsPressStyle().accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }.padding(.horizontal, DS.Size.segmentedInset)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).fill(DS.Color.surface).frame(height: DS.Size.pillH)
            }
            .animation(enabled ? DSMotion.animation(.segmentedThumb, reduceMotion: reduceMotionOverride ?? systemReduceMotion) : nil, value: selection)
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
    let detail: String
    let value: String
    var tone: Tone = .warning
    var onTap: () -> Void = {}
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text(title).dsText(DS.Font.tLabelStrong)
                    if !detail.isEmpty { Text(detail).dsText(DS.Font.tSub) }
                }.dsFillWidth()
                Text(value).dsText(tone == .positive ? DS.Font.nSpine : DS.Font.tLabel).monospacedDigit().fixedSize()
                if tone == .warning {
                    Image(systemName: DS.Icon.chevron).font(.system(size: DS.Font.tCaption.size, weight: DS.Icon.Weight.chevron))
                }
            }.foregroundStyle(tone == .warning ? DS.Color.warnInk : DS.Color.accentInk)
                .frame(minHeight: DS.Size.tapMin)
                .padding(.horizontal, DS.Space.s16).padding(.vertical, tone == .warning ? DS.Space.s8 : 0)
                .background(tone == .warning ? DS.Color.warnSoft : DS.Color.accentSoft)
                .clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
        }.dsPressStyle()
    }
}

struct DSDonut: View {
    struct Slice: Identifiable {
        let id: String
        let name: String
        let value: Double
        let amount: String
    }
    let slices: [Slice]
    var onSelect: (String) -> Void = { _ in }
    private let colors = [DS.Color.chart1, DS.Color.chart2, DS.Color.chart3, DS.Color.chart4, DS.Color.chart5]
    private var sorted: [Slice] { Array(slices.sorted { $0.value > $1.value }.prefix(colors.count)) }
    private var total: Double { sorted.reduce(0) { $0 + max(0, $1.value) } }
    private func fraction(_ value: Double) -> Double { total > 0 ? max(0, value) / total : 0 }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s16) { ring; legend }
            VStack(spacing: DS.Space.s16) { ring; legend }
        }.dsFillWidth()
    }
    private var ring: some View {
        GeometryReader { geometry in
            let gap = Double(DS.Stroke.hairline / geometry.size.width)
            ZStack {
                Circle().stroke(DS.Color.track, lineWidth: DS.Size.donutStroke)
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, slice in
                    let start = sorted.prefix(index).reduce(0) { $0 + fraction($1.value) }
                    Circle().trim(from: CGFloat(start + min(gap, fraction(slice.value) / 2)),
                                  to: CGFloat(max(start + min(gap, fraction(slice.value) / 2), start + fraction(slice.value) - gap)))
                        .stroke(colors[index], style: StrokeStyle(lineWidth: DS.Size.donutStroke, lineCap: .butt))
                        .rotationEffect(.radians(-.pi / 2))
                }
                VStack(spacing: 0) {
                    Text("最多").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                    Text(sorted.first?.name ?? "—").dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                }
            }.padding(DS.Size.donutStroke / 2)
        }.frame(width: DS.Size.donut, height: DS.Size.donut)
            .accessibilityHidden(true)
    }
    private var legend: some View {
        VStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, slice in
                Button { onSelect(slice.id) } label: {
                    HStack(spacing: DS.Space.s4) {
                        RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).fill(colors[index])
                            .frame(width: DS.Size.legendSwatch, height: DS.Size.legendSwatch)
                        Text(slice.name).dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink2)
                        Text(fraction(slice.value).formatted(.percent.precision(.fractionLength(0))))
                            .dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                        Spacer(minLength: 0)
                        Text(slice.amount).dsText(DS.Font.tLabelStrong).monospacedDigit().foregroundStyle(DS.Color.ink)
                    }.frame(minHeight: DS.Size.iconTile).dsFillWidth()
                }.dsPressStyle()
            }
        }.dsFillWidth()
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
            ForEach(0..<max(0, leadingEmptyDays), id: \.self) { _ in Color.clear.frame(height: DS.Size.tapMin) }
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

struct DSSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.switch).tint(DS.Color.accent)
            .dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).frame(minHeight: DS.Size.tapMin)
            .sensoryFeedback(DSMotion.Haptic.toggle, trigger: isOn)
    }
}
