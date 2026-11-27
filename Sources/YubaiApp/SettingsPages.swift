import SwiftUI
import YubaiCore

// MARK: 固定收支

struct RecurringView: View {
    @Environment(AppStore.self) private var store
    @State private var month: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = SettingsRenderCounts.hit("recurringBody")
        let ledger = store.current, now = store.financialNow
        let hidden = store.preferences.hideAmounts
        let total = SettingsSummary.monthlyFixed(in: ledger, now: now)
        let subscriptions = SettingsSummary.subscriptions(in: ledger, now: now)
        let shown = month ?? store.settingsFixture?.calendarMonth ?? Dates.calendar.dateInterval(of: .month, for: now)!.start
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "固定收支", add: {
                store.subscriptionDraft = SubscriptionDraft(day: Dates.calendar.component(.day, from: now))
                store.settingsSheet = .subAdd
            }, addLabel: "添加订阅")
            ScrollView {
                VStack(alignment: .leading, spacing: .zero) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                        Text(OverviewDisplay.money(total.total, hidden: hidden)).dsText(SettingsSpec.total).foregroundStyle(DS.Color.ink)
                            .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale).accessibilityIdentifier("recurringTotal")
                        Text("每月 · \(total.count) 项").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
                    }
                    .padding(.horizontal, DS.Space.s20).padding(.top, SettingsSpec.headerTop)
                    SubscriptionCalendar(month: shown, now: now, ledger: ledger) { offset in
                        withAnimation(reduceMotion ? nil : DSMotion.snappyAnimation) { month = Dates.addMonths(offset, to: shown) }
                    }
                    .padding(.horizontal, DS.Space.s16).padding(.top, SettingsSpec.cardTop)
                    if !subscriptions.isEmpty {
                        VStack(spacing: .zero) {
                            ForEach(Array(subscriptions.enumerated()), id: \.element.plan.id) { index, item in
                                subscriptionRow(item.plan, due: item.due, now: now, hidden: hidden, separator: index > 0)
                            }
                        }
                        .padding(.horizontal, SettingsSpec.cardInset)
                        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
                        .padding(.horizontal, DS.Space.s16).padding(.top, SettingsSpec.cardTop)
                    }
                }.padding(.bottom, DS.Space.s28)
            }.scrollIndicators(.hidden).accessibilityIdentifier("recurringScroll")
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .dsEdgeSwipeBack()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func subscriptionRow(_ plan: Plan, due: Date, now: Date, hidden: Bool, separator: Bool) -> some View {
        let days = Dates.calendar.dateComponents([.day], from: Dates.day(now), to: due).day ?? 0
        let schedule = plan.frequency == .yearly ? "每年 " + SettingsDisplay.monthDay(due)
            : "每月 \(plan.monthlyDay ?? Dates.calendar.component(.day, from: plan.dueDate)) 日"
        let detail = [OverviewDisplay.money(plan.amount, hidden: hidden) + (plan.currency == .cny ? "" : " " + plan.currency.rawValue),
                      schedule, plan.accountID.map { store.accountName($0) }].compactMap { $0 }.joined(separator: " · ")
        return Button { store.sheet = .editPlan(plan.id) } label: {
            HStack(spacing: DS.Space.s12) {
                DSBrandTile(name: plan.title, slug: plan.iconSlug, size: SettingsSpec.rowTile)
                VStack(alignment: .leading, spacing: .zero) {
                    Text(plan.title).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).lineLimit(1)
                    Text(detail).dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3).lineLimit(1)
                }
                Spacer(minLength: DS.Space.s8)
                Text(days <= 0 ? "今天" : "\(days) 天后").dsText(DS.Font.nSpine).foregroundStyle(DS.Color.ink).lineLimit(1)
            }
            .frame(minHeight: SettingsSpec.subRow)
            .overlay(alignment: .topTrailing) {
                if separator {
                    DS.Color.separator.frame(height: DS.Stroke.hairline).padding(.leading, SettingsSpec.rowTile + DS.Space.s12)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }.dsPressStyle().accessibilityIdentifier("subscription_" + plan.title)
    }
}

/// Month grid with brand marks on due days. Rebuilt only when the month or ledger changes.
struct SubscriptionCalendar: View {
    let month: Date
    let now: Date
    let ledger: Ledger
    let step: (Int) -> Void

    private struct Mark: Identifiable {
        let id: UUID
        let name: String
        let slug: String?
        let income: Bool
    }

    var body: some View {
        let _ = SettingsRenderCounts.hit("subscriptionCalendar")
        let calendar = Dates.calendar
        let interval = calendar.dateInterval(of: .month, for: month)!
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = (calendar.component(.weekday, from: interval.start) + 5) % DSLayout.weekdays
        let marks = marksByDay(in: interval)
        let cycle = Finance.cycle(in: ledger, now: now)
        VStack(spacing: .zero) {
            HStack(spacing: .zero) {
                arrow(.back, label: "上个月") { step(-1) }
                Text(String(calendar.component(.year, from: month)) + " 年 \(calendar.component(.month, from: month)) 月")
                    .dsText(DS.Font.tLabelStrong).monospacedDigit().foregroundStyle(DS.Color.ink).frame(maxWidth: .infinity)
                    .contentTransition(.numericText()).accessibilityAddTraits(.isHeader)
                arrow(.chevron, label: "下个月") { step(1) }
            }.frame(height: SettingsSpec.monthHeader)
            HStack(spacing: .zero) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).frame(maxWidth: .infinity) }
            }.dsText(OverviewSpec.tiny).foregroundStyle(DS.Color.ink3).frame(height: SettingsSpec.weekdayRow)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: .zero), count: DSLayout.weekdays), spacing: SettingsSpec.calendarRowGap) {
                // Blank IDs are negative so they never collide with day numbers in the lazy grid.
                ForEach(-leading..<0, id: \.self) { _ in Color.clear.frame(height: SettingsSpec.calendarCell) }
                ForEach(1...count, id: \.self) { day in
                    let date = Dates.addDays(day - 1, to: interval.start)
                    cell(day, marks: marks[day] ?? [], inCycle: date >= Dates.day(cycle.start) && date <= Dates.day(cycle.end))
                }
            }
            .id(month)
            .transition(.opacity)
        }
        .padding(.horizontal, SettingsSpec.calendarInset).padding(.top, DS.Space.s8).padding(.bottom, SettingsSpec.calendarInset)
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .accessibilityElement(children: .contain).accessibilityIdentifier("subscriptionCalendar")
    }

    private func marksByDay(in interval: DateInterval) -> [Int: [Mark]] {
        var result: [Int: [Mark]] = [:]
        let plans = ledger.plans.filter { $0.active && $0.stoppedAt == nil && $0.frequency != .once && ($0.inflow ? $0.nature == .income : true) }
        for plan in plans.sorted(by: { $0.inflow == $1.inflow ? $0.title < $1.title : !$0.inflow }) {
            for date in SettingsSummary.occurrences(of: plan, in: interval) {
                result[Dates.calendar.component(.day, from: date), default: []].append(Mark(id: plan.id, name: plan.title, slug: plan.iconSlug, income: plan.inflow))
            }
        }
        return result
    }

    private func cell(_ day: Int, marks: [Mark], inCycle: Bool) -> some View {
        let fill = marks.isEmpty ? Color.clear : DS.Color.surface
        return VStack(spacing: SettingsSpec.markGap) {
            Text("\(day)").dsText(marks.isEmpty ? DS.Font.tSub : DS.Font.tSubStrong).monospacedDigit()
                .foregroundStyle(inCycle ? DS.Color.ink : DS.Color.ink3)
            if !marks.isEmpty {
                HStack(spacing: -SettingsSpec.markOverlap) {
                    ForEach(Array(marks.prefix(2).enumerated()), id: \.offset) { index, mark in
                        DSBrandTile(name: mark.name, slug: mark.slug, size: DS.Size.brandTile, shape: mark.income ? .circle : .square,
                                    ring: index > 0 ? fill : nil)
                    }
                    if marks.count > 2 {
                        Text("+\(marks.count - 2)").dsText(SettingsSpec.more).foregroundStyle(DS.Color.ink3).padding(.leading, SettingsSpec.markOverlap)
                    }
                }
            }
        }
        .padding(.top, SettingsSpec.markTop)
        .frame(maxWidth: .infinity, minHeight: SettingsSpec.calendarCell, alignment: .top)
        .background(fill, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day) 日" + (marks.isEmpty ? "" : "，" + marks.map(\.name).joined(separator: "、")))
    }

    private func arrow(_ icon: DS.Icon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSIconView(icon: icon, size: SettingsSpec.calendarArrow, color: DS.Color.ink3)
                .frame(width: DS.Size.tapMin, height: SettingsSpec.monthHeader).contentShape(Rectangle())
        }.dsPressStyle().accessibilityLabel(label)
    }
}

// MARK: 分类

struct CategorySettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var segment = "支出"
    @State private var open: String?
    @State private var menu: (category: String, sub: String)?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride

    private var income: Bool { segment == "收入" }
    private var reduced: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let _ = SettingsRenderCounts.hit("categoriesBody")
        let categories = store.current.orderedCategories(income: income)
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "分类", add: { store.settingsSheet = .addCategory(income: income) }, addLabel: "添加分类")
            DSSegmented(options: ["支出", "收入"], selection: $segment, width: SettingsSpec.segmentWidth, identifierPrefix: "categoriesDirection_")
                .padding(.top, SettingsSpec.headerTop)
            ScrollView {
                VStack(spacing: .zero) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        let isOpen = open == category.name
                        let previousOpen = index > 0 && open == categories[index - 1].name
                        categoryRow(category, open: isOpen, separator: index > 0 && !isOpen && !previousOpen)
                    }
                }.padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s12).padding(.bottom, DS.Space.s28)
            }.scrollIndicators(.hidden).accessibilityIdentifier("categoriesScroll")
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .overlay {
            if let menu {
                ZStack {
                    DS.Color.scrim.opacity(.zero).contentShape(Rectangle()).onTapGesture { self.menu = nil }.ignoresSafeArea()
                    DSActionMenu(items: [
                        .init(title: "改名") { self.menu = nil; store.settingsSheet = .renameSubcategory(category: menu.category, sub: menu.sub, income: income) },
                        .init(title: "删除", warning: true) {
                            self.menu = nil
                            store.update("删除小类") { try CategoryModel.removeSubcategory(menu.sub, from: menu.category, income: income, in: &$0) }
                        },
                    ])
                    .transition(.scale(scale: DSInteraction.floatScale).combined(with: .opacity))
                }
            }
        }
        .animation(reduced ? nil : DSMotion.bouncyAnimation, value: menu?.sub)
        .onChange(of: segment) { open = nil }
        .onAppear { if open == nil, let fixture = store.settingsFixture?.openCategory { open = fixture } }
        .dsEdgeSwipeBack()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func categoryRow(_ category: YubaiCore.Category, open isOpen: Bool, separator: Bool) -> some View {
        VStack(spacing: .zero) {
            Button {
                withAnimation(reduced ? nil : DSMotion.smoothAnimation) { open = isOpen ? nil : category.name }
            } label: {
                HStack(spacing: DS.Space.s12) {
                    DSIconView(icon: SettingsDisplay.categoryIcon(category.name), size: DS.Size.icon, color: isOpen ? DS.Color.accentInk : DS.Color.ink2)
                        .frame(width: DS.Size.iconTile, height: DS.Size.iconTile)
                        .background(isOpen ? DS.Color.accentSoft : DS.Color.surface, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                    Text(category.name).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink).lineLimit(1)
                    Spacer(minLength: DS.Space.s8)
                    if !category.subcategories.isEmpty {
                        Text("\(category.subcategories.count) 个小类").dsText(DS.Font.tPill).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    }
                    DSIconView(icon: .chevron, size: SettingsSpec.categoryChevron, color: isOpen ? DS.Color.ink : DS.Color.chevron)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: SettingsSpec.chevronColumn)
                }
                .padding(.leading, DS.Space.s12).padding(.trailing, SettingsSpec.cardInset)
                .frame(minHeight: DS.Size.rowCat)
                .overlay(alignment: .top) {
                    if separator {
                        DS.Color.separator.frame(height: DS.Stroke.hairline)
                            .padding(.leading, DS.Space.s12 + DS.Size.iconTile + DS.Space.s12).padding(.trailing, SettingsSpec.cardInset)
                    }
                }
                .contentShape(Rectangle())
            }
            .dsPressStyle()
            .accessibilityValue(isOpen ? "已展开" : "已收起")
            .accessibilityIdentifier("category_" + category.name)
            if isOpen {
                VStack(spacing: .zero) {
                    ForEach(category.subcategories, id: \.self) { sub in
                        Text(sub).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.rowSub, alignment: .leading)
                            .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                            .contentShape(Rectangle())
                            .onLongPressGesture { menu = (category.name, sub) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(named: "改名") { store.settingsSheet = .renameSubcategory(category: category.name, sub: sub, income: income) }
                            .accessibilityIdentifier("subcategory_" + sub)
                    }
                    Button { store.settingsSheet = .addSubcategory(category: category.name, income: income) } label: {
                        HStack(spacing: HomeSpec.gap6) {
                            DSIconView(icon: .add, size: SettingsSpec.addIcon, color: DS.Color.accentInk)
                            Text("添加小类").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.accentInk)
                        }
                        .frame(maxWidth: .infinity, minHeight: DS.Size.rowSub, alignment: .leading)
                        .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                        .contentShape(Rectangle())
                    }.dsPressStyle().accessibilityIdentifier("addSubcategory")
                }
                .padding(.leading, DS.Space.s12 + DS.Size.iconTile + DS.Space.s12).padding(.trailing, SettingsSpec.cardInset)
                .padding(.bottom, DS.Space.s8)
                .transition(.opacity)
            }
        }
        .background(isOpen ? DS.Color.raised : .clear, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .padding(.bottom, isOpen ? SettingsSpec.openGap : .zero)
    }
}

/// A short floating menu of actions; the last may be a warning.
struct DSActionMenu: View {
    struct Item: Identifiable {
        let title: String
        var warning = false
        let action: () -> Void
        var id: String { title }
    }
    let items: [Item]
    var body: some View {
        VStack(spacing: .zero) {
            ForEach(items) { item in
                Button(action: item.action) {
                    Text(item.title).dsText(DS.Font.tBody).foregroundStyle(item.warning ? DS.Color.warnInk : DS.Color.ink)
                        .dsFillWidth().frame(minHeight: DS.Size.tapMin).padding(.horizontal, DS.Space.s16).contentShape(Rectangle())
                }.dsPressStyle().accessibilityIdentifier("actionMenu_" + item.title)
            }
        }
        .padding(.vertical, HomeSpec.gap6).frame(width: DS.Size.menuW)
        .background(DS.Color.raised).clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous)).dsShadow(DS.Shadow.float)
    }
}

// MARK: 余白的 AI

struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var available = false

    var body: some View {
        let _ = SettingsRenderCounts.hit("aiBody")
        let preferences = store.preferences
        let share = preferences.cloudShareSettings
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "余白的 AI")
            ScrollView {
                VStack(alignment: .leading, spacing: .zero) {
                    HStack(spacing: DS.Space.s12) {
                        VStack(alignment: .leading, spacing: OverviewSpec.headingGap) {
                            Text("云端 AI").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.ink)
                            Text("DeepSeek").dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                        }
                        Spacer(minLength: DS.Space.s8)
                        DSSwitch(title: "云端 AI", isOn: Binding(get: { preferences.cloudAIEnabled && available }, set: setCloud), showsTitle: false)
                            .accessibilityIdentifier("cloudAIToggle")
                    }
                    .padding(.horizontal, SettingsSpec.cardInset).frame(minHeight: SettingsSpec.aiCard)
                    .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
                    Text("云端能看到").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
                        .padding(.horizontal, DS.Space.s4).frame(height: DS.Space.s28, alignment: .leading).padding(.top, SettingsSpec.shareTop)
                    DSShareChips(items: [.init(id: "amount", title: "金额", on: share.amount), .init(id: "category", title: "分类", on: share.category),
                                         .init(id: "note", title: "备注", on: share.note), .init(id: "account", title: "账户", on: share.account)],
                                 enabled: preferences.cloudAIEnabled) { id in
                        store.update("云端能看到", entryMotion: false, showToast: false) { ledger in
                            var value = ledger.preferences.cloudShareSettings
                            switch id {
                            case "amount": value.amount.toggle()
                            case "category": value.category.toggle()
                            case "note": value.note.toggle()
                            default: value.account.toggle()
                            }
                            ledger.preferences.cloudShareSettings = value
                        }
                    }
                    DSSettingsCard {
                        Button { store.settingsSheet = .apiKey(enabling: false) } label: {
                            DSSettingsRow(icon: nil, name: "密钥", accessory: .link(keyHint), separator: false)
                        }.dsPressStyle().accessibilityIdentifier("openCloudKey")
                        HStack(spacing: DS.Space.s8) {
                            Text("说话方式").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink)
                            Spacer(minLength: DS.Space.s8)
                            DSSegmented(options: ["温和", "直接"], selection: Binding(get: { preferences.tone == .direct ? "直接" : "温和" }, set: { value in
                                store.update("说话方式", entryMotion: false, showToast: false) { $0.preferences.assistantTone = value == "直接" ? .direct : nil }
                            }), width: SettingsSpec.toneWidth, identifierPrefix: "assistantTone_", compact: true)
                        }
                        .padding(.trailing, DS.Space.s12).frame(minHeight: SettingsSpec.row)
                        .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                        Button { store.tabRouteRequest = .memories } label: {
                            DSSettingsRow(icon: nil, name: "余白记得的", accessory: .link("\(store.settingsSummary.memoryCount) 条"))
                        }.dsPressStyle().accessibilityIdentifier("openMemories")
                        Button { store.settingsSheet = .weeklyTime } label: {
                            DSSettingsRow(icon: nil, name: "每周回顾", accessory: .link(SettingsDisplay.reviewTime(preferences.reviewTime)))
                        }.dsPressStyle().accessibilityIdentifier("openWeeklyTime")
                    }.padding(.top, SettingsSpec.groupGap)
                }
                .padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s8).padding(.bottom, DS.Space.s28)
            }.scrollIndicators(.hidden).accessibilityIdentifier("aiSettingsScroll")
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .task(id: [preferences.cloudAIEnabled, IntelligenceRuntime.cloud.hasKeychainKey]) { available = await keyAvailable() }
        .dsEdgeSwipeBack()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var keyHint: String {
        let key: String?
        if let fixture = store.settingsFixture { key = fixture.apiKey }
        else { key = IntelligenceRuntime.cloud.hasKeychainKey ? IntelligenceRuntime.cloud.configuration?.apiKey : nil }
        guard let key, key.count > SettingsSpec.keyPrefix + SettingsSpec.keySuffix else { return "未填" }
        return String(key.prefix(SettingsSpec.keyPrefix)) + "…" + String(key.suffix(SettingsSpec.keySuffix))
    }

    /// Whether a key is saved, through the same provider the router uses; no request is sent.
    private func keyAvailable() async -> Bool {
        var preferences = store.preferences
        preferences.cloudAIEnabled = true
        if let fixture = store.settingsFixture {
            return await DeepSeekProvider.configured(preferences: preferences, feature: .answers,
                                                     keyStore: APIKeyStore(storage: FixtureKeyStorage(key: fixture.apiKey)), environment: [:]).availability() == .available
        }
        let frozen = preferences
        return await Task.detached(priority: .utility) {
            await DeepSeekProvider.configured(preferences: frozen, feature: .answers).availability() == .available
        }.value
    }

    private func setCloud(_ on: Bool) {
        if on && !available { store.settingsSheet = .apiKey(enabling: true); return }
        store.update("云端 AI", entryMotion: false, showToast: false) { $0.preferences.cloudAIEnabled = on }
    }
}

// MARK: 币种

struct CurrencyView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let _ = SettingsRenderCounts.hit("currencyBody")
        let rates = (store.preferences.billExchangeRates ?? []).filter(\.isValid)
        let updated = rates.map(\.updatedAt).max()
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "币种")
            ScrollView {
                VStack(alignment: .leading, spacing: .zero) {
                    Text("记账币种").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3).frame(height: DS.Space.s28, alignment: .leading)
                    HStack(spacing: DS.Space.s12) {
                        currency(.cny)
                        Spacer(minLength: DS.Space.s8)
                        DSIconView(icon: .done, size: SettingsSpec.check, color: DS.Color.accentInk)
                    }
                    .padding(.leading, DS.Space.s16).padding(.trailing, SettingsSpec.cardInset).frame(minHeight: SettingsSpec.subRow)
                    .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isSelected)
                    HStack {
                        Text("常用外币")
                        Spacer(minLength: DS.Space.s8)
                        if let updated { Text("汇率 " + SettingsDisplay.monthDay(updated) + " 更新").monospacedDigit() }
                    }.dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3).frame(height: DS.Space.s28).padding(.top, SettingsSpec.groupGap)
                    DSSettingsCard(leading: DS.Space.s16) {
                        ForEach(Array(rates.enumerated()), id: \.element.currency) { index, rate in
                            Button { store.settingsSheet = .rate(rate.currency) } label: {
                                HStack(spacing: DS.Space.s12) {
                                    currency(rate.currency)
                                    Spacer(minLength: DS.Space.s8)
                                    Text("1 = " + rate.valueText).dsText(DS.Font.tPill).monospacedDigit().foregroundStyle(DS.Color.ink3)
                                }
                                .padding(.trailing, SettingsSpec.cardInset).frame(minHeight: SettingsSpec.subRow)
                                .overlay(alignment: .top) { if index > 0 { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
                                .contentShape(Rectangle())
                            }.dsPressStyle().accessibilityIdentifier("currency_" + rate.currency.rawValue)
                        }
                        if rates.count < BillCurrency.allCases.count - 1 {
                            Button { store.settingsSheet = .addCurrency } label: {
                                HStack(spacing: HomeSpec.gap6) {
                                    DSIconView(icon: .add, size: SettingsSpec.calendarArrow, color: DS.Color.accentInk)
                                    Text("添加币种").dsText(DS.Font.tBody).fontWeight(.semibold).foregroundStyle(DS.Color.accentInk)
                                }
                                .frame(maxWidth: .infinity, minHeight: SettingsSpec.row, alignment: .leading)
                                .overlay(alignment: .top) { if !rates.isEmpty { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
                                .contentShape(Rectangle())
                            }.dsPressStyle().accessibilityIdentifier("addCurrency")
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s8).padding(.bottom, DS.Space.s28)
            }.scrollIndicators(.hidden).accessibilityIdentifier("currencyScroll")
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .dsEdgeSwipeBack()
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func currency(_ code: BillCurrency) -> some View {
        HStack(spacing: DS.Space.s12) {
            Text(SettingsDisplay.symbol(code)).dsText(code == .hkd ? SettingsSpec.smallSymbol : DS.Font.tLabelStrong).monospacedDigit()
                .foregroundStyle(DS.Color.ink).frame(width: SettingsSpec.symbolColumn)
            Text(code.rawValue).dsText(DS.Font.tBody).fontWeight(.semibold).foregroundStyle(DS.Color.ink)
                .frame(width: SettingsSpec.codeColumn, alignment: .leading)
            Text(code.unit).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink2).lineLimit(1)
        }
    }
}

// MARK: 编辑账户

struct AccountEditView: View {
    let accountID: UUID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingArchive = false

    var body: some View {
        let _ = SettingsRenderCounts.hit("accountEditBody")
        if let account = store.accounts.first(where: { $0.id == accountID }) {
            let hidden = store.preferences.hideAmounts
            let type = AccountType.of(account)
            VStack(spacing: .zero) {
                OverviewNavigationBar(title: "编辑账户")
                ScrollView {
                    VStack(spacing: SettingsSpec.groupGap) {
                        DSSettingsCard(leading: DS.Space.s16) {
                            row("名称", account.name, first: true, id: "editAccountName") { store.settingsSheet = .accountName(accountID) }
                            row("类型", type.title, id: "editAccountType") { store.settingsSheet = .accountType(accountID) }
                        }
                        if account.kind == .credit {
                            DSSettingsCard(leading: DS.Space.s16) {
                                row("额度", OverviewDisplay.money(account.creditLimit, hidden: hidden), first: true, id: "editAccountLimit") { store.settingsSheet = .accountLimit(accountID) }
                                row("账单日", account.creditStatementDay.map { "每月 \($0) 日" } ?? "未设", id: "editAccountStatement") { store.settingsSheet = .accountDay(accountID, statement: true) }
                                row("还款日", account.creditPaymentDay.map { "每月 \($0) 日" } ?? "未设", id: "editAccountPayment") { store.settingsSheet = .accountDay(accountID, statement: false) }
                            }
                        }
                        DSSettingsCard(leading: DS.Space.s16) {
                            row(account.kind == .investment ? "现值" : "余额", OverviewDisplay.money(store.balance(account), hidden: hidden), first: true, ink: true, id: "editAccountBalance") {
                                store.openAccountValuation(account.kind == .investment ? .invest(accountID) : .reconcile(accountID))
                            }
                        }
                        if !account.archived {
                            Button { confirmingArchive = true } label: {
                                Text("归档这个账户").dsText(DS.Font.tTitle).foregroundStyle(DS.Color.warnInk)
                                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonH).dsPill(DS.Color.surface)
                            }.dsPressStyle().accessibilityIdentifier("archiveAccount")
                        }
                    }
                    .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s8).padding(.bottom, DS.Space.s28)
                }.scrollIndicators(.hidden).accessibilityIdentifier("accountEditScroll")
            }
            .background(DS.Color.bg.ignoresSafeArea())
            .overlay {
                if confirmingArchive {
                    SettingsConfirm(consequence: "归档后不再出现在资产和记一笔里，账目保留。", action: "归档",
                                    cancel: { confirmingArchive = false }) {
                        confirmingArchive = false
                        if store.update("归档账户", entryMotion: false, { try Accounts.archive(accountID, in: &$0, now: store.financialNow) }) { dismiss() }
                    }
                }
            }
            .dsEdgeSwipeBack()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private func row(_ name: String, _ value: String, first: Bool = false, ink: Bool = false, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s8) {
                Text(name).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink)
                Spacer(minLength: DS.Space.s8)
                Text(value).dsText(DS.Font.tBody).monospacedDigit().foregroundStyle(ink ? DS.Color.ink : DS.Color.ink3)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                DSIconView(icon: .chevron, size: SettingsSpec.chevron, color: DS.Color.chevron)
            }
            .padding(.trailing, SettingsSpec.cardInset).frame(minHeight: SettingsSpec.row)
            .overlay(alignment: .top) { if !first { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }.dsPressStyle().accessibilityIdentifier(id)
    }
}

/// A destructive confirmation: one consequence line, the action and 取消.
struct SettingsConfirm: View {
    let consequence: String
    let action: String
    let cancel: () -> Void
    let confirm: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DS.Color.scrim.ignoresSafeArea().onTapGesture(perform: cancel)
            VStack(spacing: DS.Space.s16) {
                Text(consequence).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: DS.Space.s8) {
                    Button(action: confirm) {
                        Text(action).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.warnInk)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.buttonH).dsPill(DS.Color.warnSoft)
                    }.dsPressStyle().accessibilityIdentifier("confirmAction")
                    DSButton("取消", kind: .secondary, action: cancel).accessibilityIdentifier("confirmCancel")
                }
            }
            .padding(DS.Space.s20)
            .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
            .dsShadow(DS.Shadow.float)
            .padding(.horizontal, DS.Space.s28)
            .scaleEffect(shown || reduceMotion ? 1 : DSInteraction.floatScale)
            .opacity(shown ? 1 : .zero)
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, cancel)
        }
        .onAppear { withAnimation(DSMotion.bouncyAnimation) { shown = true } }
    }
}

/// 心愿与回顾: one card routing to the three existing pages.
struct WishesHubView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let ledger = store.current
        VStack(spacing: .zero) {
            OverviewNavigationBar(title: "心愿与回顾")
            ScrollView {
                DSSettingsCard {
                    row(.heart, "心愿单", "\(WishesHub.wishCount(in: ledger)) 件", first: true, id: "openWishlist") { store.tabRouteRequest = .wishlist }
                    row(.mail, "每周来信", WishesHub.lastLetter(in: ledger).map(SettingsDisplay.monthDay) ?? "", id: "openWeekly") { store.tabRouteRequest = .weekly(nil) }
                    row(.compass, "消费观", "\(WishesHub.valueCount(in: ledger)) 条", id: "openProfile") { store.tabRouteRequest = .profile }
                }.padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s4)
            }.scrollIndicators(.hidden)
        }
        .background(DS.Color.bg.ignoresSafeArea())
        .dsEdgeSwipeBack()
        .accessibilityIdentifier("wishesHubPage")
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func row(_ icon: DS.Icon, _ name: String, _ value: String, first: Bool = false, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSSettingsRow(icon: icon, name: name, accessory: .link(value), separator: !first)
        }.dsPressStyle().accessibilityIdentifier(id)
    }
}
