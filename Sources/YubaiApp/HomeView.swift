import SwiftUI
import YubaiCore

enum HomeDisplay {
    /// Every amount on home, overview and settings: in the main currency (display only), CNY by default.
    static func money(_ cents: Int64, hidden: Bool, currency: Bool = false) -> String {
        let symbol = DisplayCurrency.symbol
        if hidden { return currency ? symbol + "••••" : "••••" }
        let shown = DisplayCurrency.convert(cents)
        let number = DisplayCurrency.main.formatted(abs(shown))
        guard currency else { return (shown < 0 ? "-" : "") + number }
        return (shown < 0 ? "-" : "") + symbol + number
    }

    static func signed(_ cents: Int64, hidden: Bool) -> String {
        guard !hidden else { return money(cents, hidden: true) }
        return (cents < 0 ? "−" : cents > 0 ? "+" : "") + money(abs(cents), hidden: false)
    }

    static func billAmount(_ entry: Entry, hidden: Bool) -> String {
        guard !hidden else { return money(entry.amount, hidden: true) }
        let sign = entry.nature.paired || entry.intoFixedSavings ? "" : entry.nature.inflow ? "+" : "−"
        // Spec-Currency 首页和列表: the main-currency amount; the original goes on the second line.
        return sign + money(entry.amount, hidden: false)
    }

    /// The second line of a foreign bill: what was paid, in its own currency (「C$4.25」).
    static func originalAmount(_ entry: Entry, hidden: Bool) -> String? {
        guard let currency = entry.originalCurrency, let original = entry.originalAmount else { return nil }
        return currency.amountText(original, hidden: hidden)
    }

    static func dsBudget(_ row: HomeBudget, hidden: Bool) -> DSBudget {
        DSBudget(id: row.id.uuidString, name: row.name, total: money(row.amount, hidden: hidden),
                 remaining: money(row.over > 0 ? row.over : row.remaining, hidden: hidden),
                 usedFraction: row.fraction, overspent: row.over > 0)
    }

    static func daysLeft(_ period: SpendableBreakdown) -> Int {
        if HomeFixture.current != nil, Dates.day(period.asOf) != Dates.day(period.cycleStart) {
            return max(1, period.daysLeft - 1)
        }
        return period.daysLeft
    }

    static func bars(_ daily: DailySpending, fixture: Bool) -> (days: [DSHero.Day], guide: CGFloat?) {
        let ceiling = fixture ? HomeSpec.fixtureBarMaximum : max(1, daily.amounts.max() ?? 0)
        func height(_ amount: Int64) -> CGFloat {
            min(DS.Size.dayBarsH, max(HomeSpec.barFloor, (CGFloat(amount) / CGFloat(ceiling) * DS.Size.dayBarsH).rounded()))
        }
        let days = daily.amounts.enumerated().map { index, amount in
            DSHero.Day(id: index, height: height(amount), state: index > daily.today ? .future
                : index == daily.today ? .today
                : amount > (fixture ? HomeSpec.fixtureBarWarning : daily.evenPace ?? .max) ? .warning : .past)
        }
        return (days, daily.evenPace.map { fixture ? HomeSpec.barGuide : height($0) })
    }

    static func icon(_ entry: Entry, category: String, picked: String? = nil) -> DS.Icon {
        if entry.intoFixedSavings || entry.nature == .investBuy { return .saveFirst }
        if let picked = picked.flatMap(DS.Icon.init(rawValue:)), !entry.nature.paired, entry.nature != .income { return picked }
        if entry.nature.paired { return .transfer }
        if entry.nature == .income { return .acctWallet }
        if entry.planID != nil { return .subscription }
        switch category {
        case "吃饭", "餐饮": return entry.displayTitle.contains("咖啡") || entry.displayTitle.contains("瑞幸") ? .catCoffee : .catFood
        case "咖啡": return .catCoffee
        case "交通": return .catTransport
        case "买菜", "买菜做饭": return .catGrocery
        case "购物": return .catShopping
        case "居住": return .catHousing
        case "娱乐": return .catFun
        case "日用": return .catDaily
        case "数码", "数码与电子产品", "通讯": return .catDigital
        default: return .catOther
        }
    }

    static func icon(_ account: Account) -> DS.Icon {
        switch account.kind {
        case .bank: .acctDebit
        case .cash: .acctCash
        case .credit: .acctCredit
        case .investment: .acctInvest
        case .receivable: .acctBalance
        }
    }
}

struct HomeView: View {
    let request: LedgerPreset?
    @Environment(AppStore.self) private var store

    var body: some View {
        HomePage(ledger: store.current, now: store.financialNow, request: request, fixture: HomeFixture.current, scrollRequest: store.rootScrollRequest[.ledger, default: 0],
                 openBudget: { store.tabRouteRequest = .formula },
                 openSettings: { store.tabRouteRequest = .settings },
                 openBill: { store.billCardID = $0 },
                 openAsk: { store.openAsk($0, send: true) },
                 openMenu: { store.billMenu = $0 },
                 deleteBill: { store.deleteBill($0) },
                 menuAction: { store.perform($1, on: $0) },
                 recordSalary: { store.requestCaptureSheet(.prefilledEntry(.init(category: nil, amount: nil, purpose: "工资", nature: .income))) },
                 cover: { amount in
                     _ = store.update("补上") { try Reserve.transfer(.take, amount: amount, in: &$0, now: store.financialNow) }
                 })
        .modifier(HomeMenuScrollLock())
        .overlay(alignment: .bottom) { HomeRunningOverlay() }
    }
}

private struct HomePage: View {
    let ledger: Ledger
    let now: Date
    let request: LedgerPreset?
    let fixture: HomeFixture?
    let scrollRequest: Int
    let openBudget: () -> Void
    let openSettings: () -> Void
    let openBill: (UUID) -> Void
    let openAsk: (String) -> Void
    let openMenu: (BillMenuRequest) -> Void
    let deleteBill: (Entry) -> Void
    let menuAction: (Entry, BillMenuAction) -> Void
    let recordSalary: () -> Void
    let cover: (Int64) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.yubaiRootNavigationHeight) private var navigationHeight
    @Environment(\.yubaiToastClearance) private var toastClearance
    @Environment(\.displayScale) private var displayScale
    @State private var searching = HomeFixture.current?.isSearch == true
    @State private var query = HomeFixture.current?.isSearch == true ? "打车" : ""
    @State private var preset: LedgerPreset?
    @State private var frames = BillRowFrames()
    @State private var groupsCache = HomeBillGroupsCache()
    @FocusState private var focused: Bool

    var body: some View {
        let _ = HomeRenderCounts.increment("homeBody")
        VStack(spacing: .zero) {
            if searching { searchBar.padding(.horizontal, DS.Space.s20) }
            else { HomeTopBar(openSettings: openSettings) }
            ScrollViewReader { scroll in
                // A List, so rows get the system swipe (iOS 26 only offers it here).
                List {
                    Group {
                        if searching {
                            searchResults
                        } else {
                            if preset == nil { hero.id("homeTop") }
                            DSAskBar(onAsk: beginSearch).padding(.top, DS.Space.s16).padding(.bottom, DS.Space.s8)
                            billDays
                        }
                    }
                    .listRowInsets(EdgeInsets(top: .zero, leading: DS.Space.s20, bottom: .zero, trailing: DS.Space.s20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(DS.Color.bg)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, .zero)
                .contentMargins(.bottom, navigationHeight + DS.Space.s12 + toastClearance, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("entriesScroll")
                .onChange(of: scrollRequest) {
                    cancelSearch()
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(reduceMotion ? nil : DSMotion.smoothAnimation) { scroll.scrollTo("homeTop", anchor: .top) }
                    }
                }
            }
        }.background(DS.Color.bg.ignoresSafeArea())
            .task {
                if fixture?.isSearch == true { focused = true }
            }
            .onChange(of: request, initial: true) { _, request in
                guard let request else { return }
                preset = request
                if !request.search.isEmpty || request.categories != nil {
                    query = request.search
                    searching = true
                }
            }
    }

    private var hide: Bool { ledger.preferences.hideAmounts }
    private var period: SpendableBreakdown { Finance.spendableBreakdown(ledger, now: now) }
    private var hero: some View {
        let period = period
        let chartLedger = fixture?.chartLedger(from: ledger) ?? ledger
        let series = DailySpending(in: chartLedger, period: period)
        let bars = HomeDisplay.bars(series, fixture: fixture != nil)
        let over = period.showsSpendableDeficit
        let amount = period.spendableDisplayAmount
        let days = HomeDisplay.daysLeft(period)
        let daily = Int64((Double(period.available) / Double(days)).rounded())
        let elapsed = max(1, period.daysTotal - days + 1)
        let burn = max(1, period.spent / Int64(elapsed))
        let projected: Int
        if fixture?.isTight == true, let today = series.amounts.last(where: { $0 > 0 }) {
            projected = Int((Double(period.available) / Double(today)).rounded(.up))
        } else {
            projected = Int((Double(period.available) / Double(burn)).rounded(.up))
        }
        let tight = fixture?.isTight == true || (fixture == nil && period.available > 0 && period.waterBar?.fast == true && projected < days)
        let tint = over || tight ? DS.Color.warnInk : period.income == 0 ? DS.Color.ink3 : DS.Color.ink
        let budgets = HomeBudgets(in: ledger, now: now).home.map { HomeDisplay.dsBudget($0, hidden: hide) }
        return VStack(spacing: .zero) {
            DSHero(amount: HomeDisplay.money(amount, hidden: hide, currency: true),
                   // Spec-Issues 7: overspent shows 每天 0.00, not an empty slot.
                   daily: over ? HomeDisplay.money(0, hidden: hide) : period.income > 0 ? HomeDisplay.money(daily, hidden: hide) : "",
                   remainingDays: days, days: bars.days, budgets: [], onAmount: openBudget,
                   title: over ? "超支" : "还能花", tint: tint, titleTint: over || tight ? DS.Color.warnInk : DS.Color.ink3,
                   guide: bars.guide)
            if period.income == 0 {
                HomeStatus(text: "工资未到账", action: "记工资", onAction: recordSalary, identifier: "recordSalary")
            } else if over {
                let reserve = ledger.fixedSavingsTotal(now: now)
                HomeStatus(text: "机动余钱 " + HomeDisplay.money(reserve, hidden: hide),
                           action: reserve >= amount ? "补上 " + HomeDisplay.money(amount, hidden: hide) : nil,
                           onAction: { cover(amount) }, identifier: "coverFromReserve")
            } else if tight {
                let date = Dates.addDays(projected, to: now)
                HomeStatus(text: "照这个速度，\(BudgetPageDate.text(date)) 花完")
            }
            DSHomeBudgetColumns(budgets: budgets, onBudget: openBudget)
        }
    }

    /// Bills grouped by day: one `Section` a day, the day line as its header, every row a single view.
    /// The grouping is cached per ledger version, preset and moment, never sorted again in a body pass.
    @ViewBuilder private var billDays: some View {
        let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
        let recoveryIDs = pendingIDs
        let groups = groupsCache.groups(ledger: ledger, now: now, preset: preset, fixture: fixture)
        if preset != nil {
            DSDayHeader(title: "\(groups.count) 笔", total: HomeDisplay.signed(groups.net, hidden: hide))
                .accessibilityIdentifier("entriesSearchTotal")
                .homeRow()
        }
        ForEach(groups.days) { day in
            Section {
                // The day line is the section's first row, not its header, so it scrolls away like the canvas.
                DSDayHeader(title: dayTitle(day.day),
                            total: day.net == 0 || fixture == .home(.empty) ? "" : HomeDisplay.signed(day.net, hidden: hide),
                            today: day.day == Dates.day(now), first: day.day == groups.days.first?.day)
                    .accessibilityAddTraits(.isHeader)
                    .homeRow()
                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                    billRow(entry, account: accounts[entry.accountID], pending: recoveryIDs.contains(entry.id), separator: index > 0)
                        .dsRowEnter(index: min(day.offset + index, DailySpending.columnCount))
                        .homeRow()
                }
            }
        }
    }

    private var pendingIDs: Set<UUID> {
        let recovered = Dictionary(grouping: ledger.activeEntries.filter { $0.nature == .refund && $0.date <= now }, by: \.relatedEntryID)
        return Set(ledger.activeEntries.filter {
            $0.pendingRecovery != nil && EntryRecovery.pendingAmount(for: $0) > (recovered[$0.id] ?? []).reduce(0) { $0 + $1.amount }
        }.map(\.id))
    }

    private func dayTitle(_ day: Date) -> String {
        let label = ManualBookkeeping.dayLabel(day, now: now)
        guard day < Dates.day(Dates.addDays(-1, to: now)),
              day >= Dates.day(Dates.addDays(-7, to: now)) else { return label }
        let weekday = Dates.calendar.component(.weekday, from: day)
        let days = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return label + " " + days[weekday - 1]
    }

    private func billNet(_ rows: [Entry]) -> Int64 { HomeBillGroups.net(rows) }

    private func billRow(_ entry: Entry, account: Account?, pending: Bool, separator: Bool) -> some View {
        let category = ledger.normalizedCategory(for: entry).category
        let tag: DSInlineTag? = pending ? .init(title: entry.pendingRecovery == .split ? "待 AA" : "待报销")
            : (entry.intoFixedSavings || entry.nature == .investBuy) ? .init(title: "存入", tone: .positive) : nil
        let secondLine = searching
            ? [Dates.monthDay(entry.date), account?.name].compactMap { $0 }.joined(separator: " · ")
            : entry.originalCurrency != nil || account?.kind == .credit ? account?.name : nil
        let icon = HomeDisplay.icon(entry, category: category,
                                    picked: ledger.categories.first { $0.name == category && $0.income == entry.nature.categoryIncome }?.icon)
        let amount = HomeDisplay.billAmount(entry, hidden: hide)
        let detailAmount = HomeDisplay.originalAmount(entry, hidden: hide)
        let amountColor = entry.nature.inflow || entry.intoFixedSavings ? DS.Color.accentInk : DS.Color.ink
        let frames = frames
        return HomeBillButton(onTap: {
            focused = false
            openBill(entry.id)
        }, onHold: {
            focused = false
            openMenu(BillMenuRequest(entryID: entry.id, frame: frames.frames[entry.id] ?? .zero, icon: icon,
                                     name: entry.displayTitle, amount: amount, detail: secondLine,
                                     detailAmount: detailAmount, amountColor: amountColor))
        }) {
            DSListRow(icon: icon, name: entry.displayTitle, amount: amount, detail: secondLine, tag: tag, separator: separator,
                      detailAmount: detailAmount, amountColor: amountColor)
                .contentShape(Rectangle())
        }
            .accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.frames[entry.id] = $0 }
            .nativeSwipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { deleteBill(entry) } label: {
                    Label { Text("删除") } icon: { DS.Icon.delete.templateImage(size: HomeSpec.swipeIcon, scale: displayScale) }
                }.tint(DS.Color.warnStrong)
            }
            // 改分类 only where the menu offers it; deleting stays the system swipe's own action.
            .accessibilityActions {
                Button("编辑") { menuAction(entry, .edit) }
                Button("再记一笔") { menuAction(entry, .duplicate) }
                if entry.canRecategorize { Button("改分类") { menuAction(entry, .recategorize) } }
            }
    }

    private var searchBar: some View {
        HStack(spacing: DS.Space.s12) {
            HStack(spacing: DS.Space.s8) {
                DSIconView(icon: .search, size: DS.Size.brandTile, color: DS.Color.ink3)
                DSHomeSearchField(text: $query, focus: $focused, onSubmit: { focused = false })
            }.padding(.horizontal, HomeSpec.askInset)
                .frame(minHeight: HomeSpec.statusHeight).dsPill(DS.Color.raised)
                .overlay(DS.Shape.pill.strokeBorder(DS.Color.accent, lineWidth: HomeSpec.searchBorder))
            Button(action: cancelSearch) {
                Text("取消").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.accentInk).fixedSize()
            }.dsPressStyle().accessibilityIdentifier("entriesSearchCancel")
        }
    }

    @ViewBuilder private var searchResults: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty, preset?.categories != nil {
            billDays
        } else if !needle.isEmpty {
            let results = ledger.searchBills(needle, now: now).filter { entry in
                guard let preset, let categories = preset.categories else { return true }
                return (preset.entryIDs?.contains(entry.id) ?? true)
                    && (preset.interval.map { $0.start <= entry.date && entry.date < $0.end } ?? true)
                    && categories.contains(ledger.normalizedCategory(for: entry).category)
            }
            let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
            let pending = pendingIDs
            Button {
                focused = false
                openAsk(needle)
            } label: {
                HStack(spacing: DS.Space.s12) {
                    DSIconView(icon: .chat, size: DS.Size.brandTile, color: DS.Color.accentInk)
                        .frame(width: HomeSpec.tile32, height: HomeSpec.tile32).dsSurface(DS.Color.accentSoft, radius: DS.Radius.s)
                    Text("问余白「\(needle)」").dsText(HomeSpec.medium).lineLimit(1)
                    Spacer(minLength: .zero)
                    DSIconView(icon: .chevron, size: DS.Space.s16, color: DS.Color.ink3)
                }.foregroundStyle(DS.Color.accentInk).frame(height: SettingsSpec.row).contentShape(Rectangle())
            }.dsPressStyle().padding(.top, DS.Space.s4).accessibilityIdentifier("askHomeSearch")
            DS.Color.separator.frame(height: DS.Stroke.hairline)
            DSDayHeader(title: "\(results.count) 笔", total: HomeDisplay.signed(billNet(results), hidden: hide))
                .accessibilityIdentifier("entriesSearchTotal")
            ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                billRow(entry, account: accounts[entry.accountID], pending: pending.contains(entry.id), separator: index > 0)
            }
        }
    }

    private func beginSearch() {
        withAnimation(reduceMotion ? DSMotion.reduceMotionAnimation : DSMotion.smoothAnimation) { searching = true }
        Task { @MainActor in
            await Task.yield()
            if searching { focused = true }
        }
    }

    private func cancelSearch() {
        focused = false
        withAnimation(reduceMotion ? DSMotion.reduceMotionAnimation : DSMotion.smoothAnimation) {
            searching = false
            query = ""
            preset = nil
        }
    }
}

/// Home's bills by day, newest first, with each day's net and where its rows start (for the entrance stagger).
struct HomeBillGroups {
    struct Day: Identifiable {
        var id: Date { day }
        let day: Date
        let entries: [Entry]
        let net: Int64
        let offset: Int
    }
    let days: [Day]
    let count: Int
    let net: Int64

    static func net(_ rows: [Entry]) -> Int64 {
        rows.reduce(0) { net, entry in
            guard !entry.nature.paired else { return net }
            return net + (entry.nature.inflow ? entry.amount : -entry.amount)
        }
    }

    init(ledger: Ledger, now: Date, preset: LedgerPreset?, fixture: HomeFixture?) {
        let rows = ledger.activeEntries.filter { entry in
            guard entry.date <= now, fixture?.shows(entry) ?? true else { return false }
            guard let preset else { return true }
            return (preset.entryIDs?.contains(entry.id) ?? true)
                && (preset.interval.map { $0.start <= entry.date && entry.date < $0.end } ?? true)
                && (preset.categories?.contains(ledger.normalizedCategory(for: entry).category) ?? true)
                && (preset.category.map { $0 == ledger.normalizedCategory(for: entry).category } ?? true)
        }.sorted { a, b in
            (a.date, a.recordedAt ?? a.date, a.id.uuidString) > (b.date, b.recordedAt ?? b.date, b.id.uuidString)
        }
        let grouped = Dictionary(grouping: rows, by: { Dates.day($0.date) })
        var offset = 0
        days = grouped.keys.sorted(by: >).map { day in
            let entries = grouped[day] ?? []
            defer { offset += entries.count }
            return Day(day: day, entries: entries, net: Self.net(entries), offset: offset)
        }
        count = rows.count
        net = Self.net(rows)
    }
}

/// Keeps the last grouping; a body pass with the same ledger version, moment and preset reuses it.
final class HomeBillGroupsCache {
    private var key: (ledger: UUID, updated: Date, entries: Int, now: Date, preset: LedgerPreset?, fixture: HomeFixture?)?
    private var value: HomeBillGroups?

    func groups(ledger: Ledger, now: Date, preset: LedgerPreset?, fixture: HomeFixture?) -> HomeBillGroups {
        if let key, let value, key.ledger == ledger.id, key.updated == ledger.updatedAt, key.entries == ledger.entries.count,
           key.now == now, key.preset == preset, key.fixture == fixture {
            return value
        }
        let fresh = HomeBillGroups(ledger: ledger, now: now, preset: preset, fixture: fixture)
        key = (ledger.id, ledger.updatedAt, ledger.entries.count, now, preset, fixture)
        value = fresh
        return fresh
    }
}

private extension View {
    /// A home List row: 20 in from each edge, no system separator, page background.
    func homeRow() -> some View {
        listRowInsets(EdgeInsets(top: .zero, leading: DS.Space.s20, bottom: .zero, trailing: DS.Space.s20))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Color.bg)
    }
}

/// While the long-press menu is up the finger that opened it must not scroll the list.
/// Read here, not in `HomeView.body`, so opening the menu does not rebuild the page.
private struct HomeMenuScrollLock: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content.scrollDisabled(store.billMenu != nil)
    }
}

struct HomeTopBar: View {
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: .zero)
            Button(action: openSettings) {
                DSIconView(icon: .settings, size: HomeSpec.navIcon, color: DS.Color.ink)
                    .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
            }.dsPressStyle().accessibilityLabel("设置").accessibilityIdentifier("openSettings")
        }.padding(.horizontal, DS.Space.s20)
            .accessibilityElement(children: .contain).accessibilityIdentifier("rootHeaderRegion")
    }
}

private struct HomeStatus: View {
    let text: String
    var action: String?
    var onAction: () -> Void = {}
    var identifier = ""

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Text(text).dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.warnInk).dsFillWidth()
            if let action {
                Button(action: onAction) {
                    Text(action).dsText(HomeSpec.smallStrong).monospacedDigit().foregroundStyle(DS.Color.ink)
                        .padding(.horizontal, DS.Space.s12).frame(height: HomeSpec.statusButton)
                        .dsSurface(DS.Color.raised, radius: DS.Radius.s)
                        .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin).contentShape(Rectangle())
                }.buttonStyle(EntryTactileButtonStyle()).accessibilityIdentifier(identifier)
            }
        }.padding(.leading, DS.Space.s12).padding(.trailing, HomeSpec.gap6)
            .frame(height: HomeSpec.statusHeight).dsSurface(DS.Color.warnSoft, radius: DS.Radius.s)
            .frame(minHeight: action == nil ? nil : DS.Size.tapMin)
            .padding(.top, DS.Space.s12)
    }
}

/// 余白在算: a question still running after 问余白 was closed. Tap to reopen.
private struct HomeRunningOverlay: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if HomeFixture.current?.isRunning == true || (store.ask.busy && store.askRequest == nil) {
            Button { store.openAsk() } label: {
                HomeRunningPill(task: HomeFixture.current?.isRunning == true ? "核对购物预算…" : store.ask.runningLabel)
            }.dsPressStyle().padding(.bottom, HomeSpec.statusBottom)
                .accessibilityIdentifier("askRunning")
                .transition(.opacity)
        }
    }
}

struct HomeRunningPill: View {
    let task: String

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            HomeRunningDots()
            Text(task).dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink).lineLimit(1).fixedSize()
            Text(DeepSeekProvider.displayName).dsText(HomeSpec.pillBadge)
                .foregroundStyle(DS.Color.accentInk).padding(.horizontal, DS.Space.s8)
                .frame(height: HomeSpec.pillBadgeHeight).dsPill(DS.Color.accentSoft)
        }.padding(.leading, HomeSpec.askInset).padding(.trailing, DS.Space.s8)
            .frame(height: HomeSpec.statusHeight)
            .background(DS.Color.raised, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
            .dsShadow(DS.Shadow.near)
            .accessibilityElement(children: .combine)
    }
}

/// Three dots at 1 / .6 / .3 that hand the bright one along; still under Reduce Motion.
private struct HomeRunningDots: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled

    var body: some View {
        let still = !animationsEnabled || (reduceMotionOverride ?? systemReduceMotion)
        PhaseAnimator(still ? [0] : [0, 1, 2]) { phase in
            HStack(spacing: HomeSpec.statusDotGap) {
                ForEach(HomeSpec.statusDotOpacities.indices, id: \.self) { index in
                    let count = HomeSpec.statusDotOpacities.count
                    Circle().fill(DS.Color.accent).frame(width: HomeSpec.statusDots, height: HomeSpec.statusDots)
                        .opacity(HomeSpec.statusDotOpacities[(index - phase + count) % count])
                }
            }
        } animation: { _ in DSMotion.standardAnimation }
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("首页") {
    let fixture = HomeFixture.home(.normal)
    HomePage(ledger: fixture.makeLedger().ledger, now: fixture.now, request: nil, fixture: fixture, scrollRequest: 0,
             openBudget: {}, openSettings: {}, openBill: { _ in }, openAsk: { _ in },
             openMenu: { _ in }, deleteBill: { _ in }, menuAction: { _, _ in },
             recordSalary: {}, cover: { _ in })
        .safeAreaInset(edge: .bottom, spacing: .zero) { DSTabBar(selection: .constant(.home), onEntry: {}) }
}
#endif
