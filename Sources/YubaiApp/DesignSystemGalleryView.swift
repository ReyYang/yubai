#if DEBUG
import SwiftUI
import YubaiCore

private enum GallerySample {
    static let barHeights: [CGFloat] = [12, 14, 10, 22, 12, 8, 16, 16, 12, 26, 10, 12, 6, 3]
}

struct DesignSystemGalleryView: View {
    enum Section: String, Identifiable {
        case colors, typography = "type", spacing, radius, shadow, components, motion
        case componentsSkeleton = "components-skeleton"
        case componentsNumbers = "components-numbers"
        case componentsEntry = "components-entry"
        case componentsOverlayControls = "components-overlay-controls"

        // The interactive gallery retains its complete components section and jump target.
        static let gallerySections: [Self] = [.colors, .typography, .spacing, .radius, .shadow, .components, .motion]
        static let componentSnapshotSections: [Self] = [.componentsSkeleton, .componentsNumbers, .componentsEntry, .componentsOverlayControls]
        static let snapshotSections: [Self] = [.colors, .typography, .spacing, .radius, .shadow] + componentSnapshotSections + [.motion]

        var id: String { rawValue }
        var title: String {
            switch self {
            case .colors: "颜色"
            case .typography: "字体"
            case .spacing: "间距"
            case .radius: "圆角"
            case .shadow: "阴影"
            case .components, .componentsSkeleton, .componentsNumbers, .componentsEntry, .componentsOverlayControls: "组件"
            case .motion: "动效"
            }
        }
    }
    private enum Component: CaseIterable, Hashable {
        // Preserve the interactive gallery's specimen order.
        case listRow, budgetRow, accordion, hero, tabBar, entryPills, keypad, categoryPicker, effectLine
        case floatingCard, sheet, segmented, button, alertCard, donut, subCalendar, toggle
    }
    enum IsolatedComponent: String {
        case sheet = "Sheet", categoryPicker = "CategoryPicker", entryPills = "EntryPills"
        case effectLine = "EffectLine", keypad = "Keypad", icon = "Icon", categoryPanel = "CategoryPanel"
    }
    let section: Section?
    var isolatedComponent: IsolatedComponent?
    init(section: Section? = nil, isolatedComponent: IsolatedComponent? = nil) {
        self.section = section
        self.isolatedComponent = isolatedComponent
    }
    @State private var sheetPresented = false
    @State private var expanded: String? = "shopping"
    @State private var motionExpanded: String?
    @State private var selectedSegment = "支出"
    @State private var selectedSegment2 = "收入"
    @State private var tab = DSTabBar.Tab.home
    @State private var calendarPreviewOpen = true
    @State private var calendarPreviewDate = EntrySpec.fixtureCalendarSelection
    @State private var calendarPreviewMonth = DSCalendarPopover.initialMonth(
        for: EntrySpec.fixtureCalendarSelection, now: EntrySpec.fixtureToday)
    @State private var calendarPreviewRepeats = false
    @State private var calendarPreviewException = DSEntryPills.Exception.none
    @State private var repeats = false
    @State private var exception = DSEntryPills.Exception.none
    @State private var category = "food"
    @State private var subcategory: String? = "午餐"
    @State private var switchOn = true
    @State private var switchOff = false
    @State private var motionSwitch = false
    @State private var menuShown = true
    @State private var allPlays = 0
    @State private var number = 42
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        Group {
            if let isolatedComponent {
                ScrollView { isolated(isolatedComponent).padding(DS.Space.s20) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.Color.bg.ignoresSafeArea())
            } else if let section {
                // No scroll clipping: hosted snapshots measure the complete section at 393pt.
                sectionView(section).padding(DS.Space.s20).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.Space.s28) {
                            ForEach(Section.gallerySections) { part in
                                sectionView(part).id(part)
                            }
                        }.padding(DS.Space.s20)
                    }.accessibilityIdentifier("ds-gallery-scroll")
                        .safeAreaInset(edge: .top, spacing: 0) {
                            HStack(spacing: DS.Space.s16) {
                                DSButton("组件", kind: .text) { proxy.scrollTo(Section.components, anchor: .top) }
                                    .accessibilityIdentifier("ds-gallery-show-components")
                                DSButton("动效", kind: .text) { proxy.scrollTo(Section.motion, anchor: .top) }
                                    .accessibilityIdentifier("ds-gallery-show-motion")
                                sheetButton
                            }.frame(maxWidth: .infinity).background(DS.Color.bg)
                        }
                }
            }
        }.foregroundStyle(DS.Color.ink).background(DS.Color.bg)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .dsSheet(isPresented: $sheetPresented) { sheetContent }
            #if os(iOS) && targetEnvironment(simulator)
            .background { if UITestSupport.script != nil { UITestDiagnostics() } }
            #endif
    }

    @ViewBuilder private func isolated(_ component: IsolatedComponent) -> some View {
        switch component {
        case .sheet: EntryHeaderGallery()
        case .categoryPicker: categorySpecimen
        case .entryPills: entryPillSpecimens
        case .effectLine: effectSpecimens
        case .keypad: DSKeypad(pressedKey: "5")
        case .icon: iconSpecimens
        case .categoryPanel: EntryCategoryGallery()
        }
    }

    private var categorySpecimen: some View {
        DSCategoryPicker(categories: Self.categories, subcategories: ["午餐", "早餐", "晚餐", "夜宵"],
                         selectedID: $category, selectedSubcategory: $subcategory)
    }

    private var entryPillSpecimens: some View {
        VStack(spacing: DS.Space.s16) {
            DSEntryPills(account: "招行储蓄", repeats: $repeats, exception: $exception,
                         repeatDay: EntrySpec.galleryRepeatDay)
            interactiveCalendarSpecimen
            DSEntryPills(account: "招行储蓄", repeats: .constant(true),
                         exception: .constant(.none), repeatDay: EntrySpec.galleryRepeatDay)
            DSEntryPills(account: "招行储蓄", repeats: .constant(false),
                         exception: .constant(.reserve), repeatDay: EntrySpec.galleryRepeatDay)
        }.frame(maxWidth: .infinity)
    }

    private var interactiveCalendarSpecimen: some View {
        VStack(spacing: DS.Space.s8) {
            if calendarPreviewOpen {
                DSCalendarPopover(date: calendarPreviewDate, now: EntrySpec.fixtureToday,
                                  displayedMonth: $calendarPreviewMonth, repeats: calendarPreviewRepeats,
                                  canRepeat: calendarPreviewException == .none, onSelect: { date in
                    calendarPreviewDate = date
                    calendarPreviewOpen = false
                }, onRepeat: {
                    calendarPreviewRepeats.toggle()
                    calendarPreviewOpen = false
                })
            }
            DSEntryPills(account: "招行储蓄", day: EntrySheetDraft.dayLabel(for: calendarPreviewDate, now: EntrySpec.fixtureToday),
                         calendarOpen: calendarPreviewOpen, repeats: $calendarPreviewRepeats,
                         exception: $calendarPreviewException,
                         repeatDay: Dates.calendar.component(.day, from: calendarPreviewDate),
                         onCalendar: {
                if !calendarPreviewOpen {
                    calendarPreviewMonth = DSCalendarPopover.initialMonth(for: calendarPreviewDate, now: EntrySpec.fixtureToday)
                }
                calendarPreviewOpen.toggle()
            })
        }
    }

    private var effectSpecimens: some View {
        VStack(spacing: DS.Space.s12) {
            DSEffectLine(effect: .reserve(142_100))
            DSEffectLine(effect: .monthly(5_800))
            DSEffectLine(effect: .split(5_200))
            DSEffectLine(effect: .reimbursement(15_580))
        }
    }

    private var iconSpecimens: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            iconGroup("分类", [.catFood, .catCoffee, .catTransport, .catGrocery, .catShopping, .catHousing,
                               .catFun, .catDaily, .catDigital, .catOther, .catAll])
            iconGroup("账户与钱", [.acctDebit, .acctCredit, .acctWallet, .acctCash, .acctBalance, .acctInvest,
                                 .saveFirst, .floor, .subscription, .cycle, .transfer, .reimburse])
            iconGroup("余白", [.tabHome, .tabOverview, .ai, .memory, .screenshot, .voice, .cloud, .export, .settings])
            iconGroup("操作", [.add, .edit, .delete, .duplicate, .recategorize, .done, .close, .more, .time,
                               .search, .backspace, .chevron, .chevronDown, .back])
            Text("用的时候").dsText(DS.Font.tLabelStrong)
            FlowLayout(centered: false) {
                iconUsage("列表 20 · icon-quiet", .catFood, size: DS.Size.icon, color: DS.Color.iconQuiet)
                iconUsage("分类圆 22", .catFood, size: EntrySpec.categoryIcon, category: true, color: DS.Color.accentInk)
                iconUsage("胶囊 15", .edit, size: DS.Font.tLabel.size)
                iconUsage("箭头 16", .chevron, size: EntrySpec.galleryChevron, color: DS.Color.chevron)
            }
        }
    }

    private func iconGroup(_ title: String, _ icons: [DS.Icon]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Text(title).dsText(DS.Font.tLabelStrong)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s4),
                                    count: EntrySpec.galleryIconColumns), spacing: DS.Space.s8) {
                ForEach(icons) { icon in
                    VStack(spacing: DS.Space.s4) {
                        icon.view(size: EntrySpec.galleryIconLarge, color: DS.Color.ink2)
                            .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                            .dsSurface(DS.Color.surface, radius: DS.Radius.s)
                        Text(icon.rawValue).dsText(DS.Font.tTag).fontWeight(.regular).lineLimit(1)
                            .foregroundStyle(DS.Color.ink3)
                            .minimumScaleFactor(EntrySpec.amountMinimumScale)
                            .padding(.horizontal, DS.Space.s4)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func iconUsage(_ title: String, _ icon: DS.Icon, size: CGFloat, category: Bool = false,
                           color: Color = DS.Color.ink2) -> some View {
        HStack(spacing: DS.Space.s4) {
            if category {
                icon.view(size: size, color: color)
                    .frame(width: DS.Size.catCircle, height: DS.Size.catCircle)
                    .background(DS.Color.accentSoft, in: Circle())
            } else {
                icon.view(size: size, color: color)
            }
            Text(title).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            Text(section.title).dsText(DS.Font.tTitle).accessibilityAddTraits(.isHeader)
            switch section {
            case .colors: colors
            case .typography: typography
            case .spacing: spacing
            case .radius: radii
            case .shadow: shadows
            case .components: components(Component.allCases)
            case .componentsSkeleton: components([.listRow, .accordion, .tabBar])
            case .componentsNumbers: components([.hero, .budgetRow, .alertCard, .donut, .subCalendar])
            case .componentsEntry: components([.entryPills, .keypad, .categoryPicker, .effectLine])
            case .componentsOverlayControls: components([.floatingCard, .sheet, .segmented, .button, .toggle])
            case .motion: motion
            }
        }.dsFillWidth().accessibilityElement(children: .contain)
            .accessibilityIdentifier("ds-gallery-\(section.rawValue)")
    }

    private var colors: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: DS.Space.s12) {
            ForEach(DS.Color.all) { token in
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    token.color.frame(height: DS.Size.keyH)
                        .clipShape(.rect(cornerRadius: DS.Radius.s, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
                    Text(token.name).dsText(DS.Font.tLabelStrong)
                    Text("\(token.lightHex) / \(token.darkHex)").dsText(DS.Font.tCaption)
                        .foregroundStyle(DS.Color.ink3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var typography: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            ForEach(DS.Font.all) { token in
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text(token.name).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                    Text(Self.typeSamples[token.name] ?? "记一笔").dsText(token.style)
                        .fixedSize(horizontal: false, vertical: true)
                }.dsFillWidth()
            }
        }
    }
    // Samples from the supplied DS v3 generator; the new strong/tab styles reuse its copy.
    private static let typeSamples: [String: String] = [
        "n-entry": "42.00", "n-detail": "−128.60", "n-hero": "¥6,268.40", "n-tile": "72.00",
        "n-key": "1 2 3", "n-spine-lg": "1,236.00", "n-spine": "−42.00", "t-title": "记一笔",
        "t-body": "午饭", "t-label": "本期入账", "t-label-strong": "添加小类", "t-pill": "招行储蓄",
        "t-sub": "11.10 – 12.09 · 还剩 16 天", "t-sub-strong": "昨天", "t-caption": "信用卡",
        "t-tag": "待报销", "t-tab": "首页"
    ]
    private var spacing: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            ForEach(Self.spaces, id: \.name) { token in
                HStack(spacing: DS.Space.s12) {
                    Text(token.name).dsText(DS.Font.tCaption).fixedSize()
                    Rectangle().fill(DS.Color.accentSoft).frame(width: token.value, height: DS.Size.icon)
                    Text(Double(token.value).formatted()).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                }
            }
        }
    }
    private static let spaces: [(name: String, value: CGFloat)] = [
        ("space-4", DS.Space.s4), ("space-8", DS.Space.s8), ("space-12", DS.Space.s12),
        ("space-16", DS.Space.s16), ("space-20", DS.Space.s20), ("space-28", DS.Space.s28)
    ]
    private var radii: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Space.s12) {
            radiusTile("radius-xs", DS.Radius.xs)
            radiusTile("radius-s", DS.Radius.s)
            radiusTile("radius-m", DS.Radius.m)
            radiusTile("radius-sheet", DS.Radius.sheet)
            radiusTile("radius-float", DS.Radius.float)
            Text("pill").dsText(DS.Font.tCaption).frame(maxWidth: .infinity, minHeight: DS.Size.buttonH).dsPill()
        }
    }
    private func radiusTile(_ name: String, _ radius: CGFloat) -> some View {
        Text(name).dsText(DS.Font.tCaption).frame(maxWidth: .infinity, minHeight: DS.Size.rowCat)
            .dsSurface(DS.Color.surface, radius: radius)
    }
    private var shadows: some View {
        VStack(spacing: DS.Space.s28) {
            Text("shadow-float").dsText(DS.Font.tLabel).dsFillWidth().dsCard().dsShadow(DS.Shadow.float)
            Text("shadow-near").dsText(DS.Font.tLabel).dsFillWidth().dsCard().dsShadow(DS.Shadow.near)
            Text("shadow-key").dsText(DS.Font.tLabel).dsFillWidth().dsCard().dsShadow(DS.Shadow.key)
        }.padding(DS.Space.s16)
    }

    private func components(_ items: [Component]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s28) {
            ForEach(items, id: \.self) { component in
                componentView(component)
            }
        }
    }

    @ViewBuilder private func componentView(_ component: Component) -> some View {
        switch component {
        case .listRow:
            specimen("ListRow · DayHeader") {
                VStack(spacing: 0) {
                    DSDayHeader(title: "昨天", total: "−243.10")
                    DSListRow(icon: DS.Icon.catGrocery, name: "盒马", amount: "−128.60", separator: false)
                    DSListRow(icon: DS.Icon.catShopping, name: "为了搬家以后和家人朋友一起使用的生活用品", amount: "−1,234,567.00")
                    DSListRow(icon: DS.Icon.catFun, name: "电影票", amount: "−78.00", detail: "信用卡", tag: DSInlineTag(title: "待 AA"))
                    DSListRow(icon: DS.Icon.catTransport, name: "打车", amount: "−36.50", detail: "信用卡", tag: DSInlineTag(title: "待报销"))
                    DSListRow(icon: DS.Icon.saveFirst, name: "工资", amount: "+12,000.00", tag: DSInlineTag(title: "存入", tone: .positive))
                }
            }
        case .budgetRow:
            specimen("BudgetRow · AmberTile") {
                VStack(spacing: DS.Space.s12) {
                    HStack(alignment: .top, spacing: DS.Space.s12) {
                        DSAmberTile(budget: Self.budgets[0]); DSAmberTile(budget: Self.budgets[1])
                    }
                    DSBudgetRow(budget: Self.budgets[2]); DSBudgetRow(budget: Self.budgets[3])
                }
            }
        case .accordion:
            specimen("Accordion") { DSAccordion(items: Self.accordionItems, expandedID: $expanded) }
        case .hero:
            specimen("Hero") {
                DSHero(amount: "¥6,268.40", daily: "391.78", remainingDays: 16, days: Self.days,
                       budgets: [Self.budgets[3], Self.budgets[1], Self.budgets[4]])
            }
        case .tabBar:
            specimen("TabBar · AskBar") {
                VStack(spacing: DS.Space.s20) {
                    DSAskBar()
                    DSTabBar(selection: $tab, onEntry: { sheetPresented = true })
                        .background {
                            // Keep system glass, with visible backing if the off-screen effect is empty.
                            if section != nil {
                                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(DS.Color.surface)
                            }
                        }
                }
            }
        case .entryPills:
            specimen("EntryPills") { entryPillSpecimens }
        case .keypad:
            specimen("Keypad") { DSKeypad() }
        case .categoryPicker:
            specimen("CategoryPicker") { categorySpecimen }
        case .effectLine:
            specimen("EffectLine") { effectSpecimens }
        case .floatingCard:
            specimen("FloatingCard · Menu") {
                DSFloatingCard(name: "换手机", amount: "−6,999.00", impact: "走机动余钱 · 还剩 1,421.00",
                               metadata: "购物 · 今天 14:20 · 招行信用卡", showsMenu: menuShown,
                               onMore: { menuShown.toggle() })
                    .fixedSize(horizontal: false, vertical: true)
                    .clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
            }
        case .sheet:
            specimen("Sheet") {
                VStack(spacing: DS.Space.s12) {
                    DSSheet(title: "记一笔") { Text(EntrySpec.fixtureLunchAmount).dsText(DS.Font.nEntry) }
                    if section != nil { sheetButton }
                }
            }
        case .segmented:
            specimen("Segmented") {
                VStack(spacing: DS.Space.s8) {
                    DSSegmented(options: ["支出", "收入"], selection: $selectedSegment)
                    DSSegmented(options: ["支出", "收入"], selection: $selectedSegment2)
                }
            }
        case .button:
            specimen("Button") {
                VStack(spacing: DS.Space.s12) {
                    DSButton("记下") {}; DSButton("完成", kind: .secondary) {}
                    DSButton("调整", kind: .text) {}; DSButton("记下", enabled: false) {}
                }
            }
        case .alertCard:
            specimen("AlertCard") {
                VStack(spacing: DS.Space.s12) {
                    DSAlertCard(title: "衣服比上期多 181%", detail: "", value: "899.00")
                    DSAlertCard(title: "上期留下", detail: "已转入机动余钱", value: "+1,204.30", tone: .positive)
                }
            }
        case .donut:
            specimen("Donut") { DSDonut(slices: Self.slices) }
        case .subCalendar:
            specimen("SubCalendar") {
                DSSubCalendar(days: (1...28).map { day in
                    DSSubCalendar.Day(number: day, brand: Self.brands[day]?.name, color: Self.brands[day]?.color ?? DS.Color.accent)
                })
            }
        case .toggle:
            specimen("Switch") {
                VStack(spacing: DS.Space.s8) {
                    DSSwitch(title: "每月", isOn: $switchOn); DSSwitch(title: "每月", isOn: $switchOff)
                }
            }
        }
    }
    private func specimen<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            Text(title).dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink3)
            content()
        }.dsFillWidth()
    }

    private var motion: some View {
        VStack(spacing: DS.Space.s16) {
            DSGallerySpringRow(name: "snappy", animation: DSMotion.snappyAnimation, playAll: allPlays)
            DSGallerySpringRow(name: "smooth", animation: DSMotion.smoothAnimation, playAll: allPlays)
            DSGallerySpringRow(name: "standard", animation: DSMotion.standardAnimation, playAll: allPlays)
            DSGallerySpringRow(name: "bouncy", animation: DSMotion.bouncyAnimation, playAll: allPlays)
            DSButton("全部播放") { allPlays += 1 }.accessibilityIdentifier("ds-motion-all")
            DSButton("按压", kind: .secondary) {}.accessibilityIdentifier("ds-motion-press")
            HStack(spacing: DS.Space.s16) {
                DSIconView(icon: .ai, size: DS.Size.icon, color: DS.Color.accentInk)
                    .dsBreathe().accessibilityLabel("读取中")
                Text(" ").frame(maxWidth: .infinity, minHeight: DS.Size.askH)
                    .dsSurface(DS.Color.surface, radius: DS.Radius.s).dsShimmer().accessibilityLabel("读取中")
            }
            Button { number += 1 } label: {
                Text("\(number)").dsText(DS.Font.nHero).foregroundStyle(DS.Color.ink).frame(maxWidth: .infinity)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(number)))
                    .animation(enabled ? DSMotion.animation(.number, reduceMotion: reduceMotion) : nil, value: number)
            }.dsPressStyle().accessibilityLabel("计数").accessibilityValue("\(number)").accessibilityIdentifier("ds-motion-number")
            DSSwitch(title: "每月", isOn: $motionSwitch).accessibilityIdentifier("ds-motion-switch")
            DSAccordion(items: [DSAccordion.Item(id: "motion-shopping", icon: DS.Icon.catShopping, title: "购物", subitems: ["衣服", "数码配件", "日用杂货"])], expandedID: $motionExpanded)
            if section != nil { sheetButton }
        }.dsFillWidth()
    }
    private var sheetButton: some View {
        DSButton("打开弹窗", kind: .text) { sheetPresented = true }.accessibilityIdentifier("ds-gallery-open-sheet")
    }
    private var sheetContent: some View {
        DSSheet(title: "记一笔") {
            VStack(spacing: DS.Space.s16) {
                Text(EntrySpec.fixtureLunchAmount).dsText(DS.Font.nEntry).accessibilityIdentifier("ds-gallery-sheet-amount")
                DSKeypad()
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("ds-gallery-sheet")
    }

    private static let budgets = [
        DSBudget(id: "fun", name: "娱乐", total: "650.00", remaining: "72.00", usedFraction: 0.89),
        DSBudget(id: "shopping", name: "购物", total: "1,500.00", remaining: "182.00", usedFraction: 0.88),
        DSBudget(id: "grocery", name: "买菜", total: "1,500.00", remaining: "520.00", usedFraction: 0.65),
        DSBudget(id: "food", name: "吃饭", total: "2,500.00", remaining: "1,236.00", usedFraction: 0.51),
        DSBudget(id: "transport", name: "交通", total: "600.00", remaining: "412.50", usedFraction: 0.30)
    ]
    private static let accordionItems = [
        DSAccordion.Item(id: "food", icon: DS.Icon.catFood, title: "吃饭", subitems: ["早餐", "午餐", "晚餐", "夜宵"]),
        DSAccordion.Item(id: "shopping", icon: DS.Icon.catShopping, title: "购物", subitems: ["衣服", "数码配件", "日用杂货"]),
        DSAccordion.Item(id: "transport", icon: DS.Icon.catTransport, title: "交通", subitems: ["地铁", "打车", "公交"]),
        DSAccordion.Item(id: "housing", icon: DS.Icon.catHousing, title: "居住", subitems: ["房租", "水电", "维修"])
    ]
    private static let categories = [
        DSCategoryPicker.Category(id: "food", name: "吃饭", icon: DS.Icon.catFood),
        DSCategoryPicker.Category(id: "coffee", name: "咖啡", icon: DS.Icon.catCoffee, suggested: true),
        DSCategoryPicker.Category(id: "transport", name: "交通", icon: DS.Icon.catTransport),
        DSCategoryPicker.Category(id: "grocery", name: "买菜", icon: DS.Icon.catGrocery),
        DSCategoryPicker.Category(id: "all", name: "全部", icon: DS.Icon.catAll)
    ]
    private static let slices = [
        DSDonut.Slice(id: "housing", name: "居住", value: 40, amount: "2,800.00"),
        DSDonut.Slice(id: "food", name: "吃饭", value: 26, amount: "1,264.00"),
        DSDonut.Slice(id: "shopping", name: "购物", value: 18, amount: "1,318.00"),
        DSDonut.Slice(id: "other", name: "其余", value: 16, amount: "1,463.60")
    ]
    // Brand colors are caller-owned data; this specimen uses DS colors to avoid introducing a palette.
    private static let brands: [Int: (name: String, color: Color)] = [
        1: ("移", DS.Color.chart1), 3: ("腾", DS.Color.chart2), 12: ("云", DS.Color.chart3),
        15: ("F", DS.Color.warn), 20: ("Q", DS.Color.accent)
    ]
    private static let days: [DSHero.Day] = (0..<30).map { index in
        let heights = GallerySample.barHeights
        let state: DSHero.Day.State = index == 9 ? .warning : (index == 13 ? .today : (index > 13 ? .future : .past))
        return DSHero.Day(id: index, height: heights[min(index, heights.count - 1)], state: state)
    }
}

private struct DSGallerySpringRow: View {
    let name: String
    let animation: Animation
    let playAll: Int
    @State private var atEnd = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Button(name) { atEnd.toggle() }.dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.accentInk)
                .dsPressStyle().accessibilityIdentifier("ds-motion-\(name)")
            GeometryReader { geometry in
                Capsule(style: .continuous).fill(DS.Color.track).frame(height: DS.Stroke.hairline)
                    .frame(maxHeight: .infinity)
                Circle().fill(DS.Color.accent).frame(width: DS.Size.icon, height: DS.Size.icon)
                    .offset(x: atEnd ? max(0, geometry.size.width - DS.Size.icon) : 0)
                    .frame(maxHeight: .infinity)
                    .animation(enabled && !(reduceMotionOverride ?? systemReduceMotion) ? animation : nil, value: atEnd)
            }.frame(height: DS.Size.tapMin).accessibilityHidden(true)
        }.onChange(of: playAll) { _, _ in atEnd.toggle() }
    }
}
private struct EntryHeaderGallery: View {
    @State private var model = EntryFixture.expense.makeModel()

    var body: some View {
        let outline = UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet,
                                             topTrailingRadius: DS.Radius.sheet, style: .continuous)
        VStack(spacing: DS.Space.s20) {
            EntryTopHeaderView(model: model, close: {}, drag: EntryHeaderDrag(move: { _ in }, end: { _ in }))
            Text(EntrySpec.fixtureLunchAmount).dsText(DS.Font.nEntry).monospacedDigit()
                .padding(.bottom, DS.Space.s20)
        }
        .background(DS.Color.bg, in: outline)
        .overlay { outline.strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline).allowsHitTesting(false) }
    }
}

private struct EntryCategoryGallery: View {
    @State private var model = EntryFixture.cats.makeModel(includeDigital: true)

    var body: some View {
        EntryCategoryPanelView(model: model, safeBottom: .zero, maxHeight: EntrySpec.categoryPanelHeight)
    }
}

#endif
