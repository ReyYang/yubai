import SwiftUI
import YubaiCore

enum HomeDisplay {
    static func money(_ cents: Int64, hidden: Bool, currency: Bool = false) -> String {
        hidden ? (currency ? "¥••••" : "••••") : Money.text(cents, currency: currency)
    }

    static func signed(_ cents: Int64, hidden: Bool) -> String {
        guard !hidden else { return money(cents, hidden: true) }
        return (cents < 0 ? "−" : cents > 0 ? "+" : "") + money(abs(cents), hidden: false)
    }

    static func billAmount(_ entry: Entry, hidden: Bool) -> String {
        guard !hidden else { return money(entry.amount, hidden: true) }
        let sign = entry.nature.paired || entry.intoFixedSavings ? "" : entry.nature.inflow ? "+" : "−"
        if let currency = entry.originalCurrency, let original = entry.originalAmount {
            let value = money(original, hidden: false)
            return sign + (currency == .jpy && original.isMultiple(of: 100) ? String(value.dropLast(3)) : value) + " " + currency.rawValue
        }
        return sign + money(entry.amount, hidden: false)
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

    static func icon(_ entry: Entry, category: String) -> DS.Icon {
        if entry.intoFixedSavings || entry.nature == .investBuy { return .saveFirst }
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
        case "数码", "数码与电子产品": return .catDigital
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
                 openAsk: { store.tabRouteRequest = .askDraft($0) },
                 openVoice: { store.tabRouteRequest = .askDraft("") },
                 recordSalary: { store.requestCaptureSheet(.prefilledEntry(.init(category: nil, amount: nil, purpose: "工资", nature: .income))) },
                 cover: { amount in
                     _ = store.update("补上") { try Reserve.transfer(.take, amount: amount, in: &$0, now: store.financialNow) }
                 })
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
    let openVoice: () -> Void
    let recordSalary: () -> Void
    let cover: (Int64) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.yubaiToastClearance) private var toastClearance
    @State private var searching = HomeFixture.current?.isSearch == true
    @State private var query = HomeFixture.current?.isSearch == true ? "打车" : ""
    @State private var preset: LedgerPreset?
    @FocusState private var focused: Bool

    var body: some View {
        let _ = HomeRenderCounts.increment("homeBody")
        VStack(spacing: .zero) {
            if searching { searchBar.padding(.horizontal, DS.Space.s20) }
            else { HomeTopBar(openSettings: openSettings) }
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: .zero) {
                        if searching {
                            searchResults
                        } else {
                            if preset == nil { hero.id("homeTop") }
                            DSAskBar(onAsk: beginSearch, onVoice: openVoice).padding(.top, DS.Space.s16)
                            billDays.padding(.top, DS.Space.s8)
                        }
                    }.padding(.horizontal, DS.Space.s20)
                        .padding(.bottom, HomeSpec.tabHeight)
                        .padding(.bottom, toastClearance)
                }
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
                if !request.search.isEmpty {
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
        let amount = period.income > 0 && period.rawR < 0 ? -period.rawR : period.available
        let over = period.income > 0 && period.rawR < 0
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
        let tight = fixture?.isTight == true || (fixture == nil && period.waterBar?.fast == true && projected < days)
        let tint = over || tight ? DS.Color.warnInk : period.income == 0 ? DS.Color.ink3 : DS.Color.ink
        let budgets = HomeBudgets(in: ledger, now: now).home.map { HomeDisplay.dsBudget($0, hidden: hide) }
        return VStack(spacing: .zero) {
            DSHero(amount: HomeDisplay.money(amount, hidden: hide, currency: true),
                   daily: !over && period.income > 0 ? HomeDisplay.money(daily, hidden: hide) : "",
                   remainingDays: days, days: bars.days, budgets: [], onAmount: openBudget,
                   title: over ? "超出" : "还能花", tint: tint, titleTint: over || tight ? DS.Color.warnInk : DS.Color.ink3,
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

    private var billDays: some View {
        let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
        let recoveryIDs = pendingIDs
        let rows = ledger.activeEntries.filter { entry in
            guard entry.date <= now, fixture?.shows(entry) ?? true else { return false }
            guard let preset else { return true }
            return (preset.entryIDs?.contains(entry.id) ?? true)
                && (preset.interval?.contains(entry.date) ?? true)
                && (preset.category.map { $0 == ledger.normalizedCategory(for: entry).category } ?? true)
        }.sorted(by: newestFirst)
        let groups = Dictionary(grouping: rows, by: { Dates.day($0.date) })
        let days = groups.keys.sorted(by: >)
        let offsets = rowOffsets(days: days, groups: groups)
        return LazyVStack(spacing: .zero) {
            if preset != nil {
                DSDayHeader(title: "\(rows.count) 笔", total: HomeDisplay.signed(billNet(rows), hidden: hide))
                    .accessibilityIdentifier("entriesSearchTotal")
            }
            ForEach(days, id: \.self) { day in
                let entries = groups[day] ?? []
                let net = billNet(entries)
                DSDayHeader(title: dayTitle(day),
                            total: net == 0 || fixture == .home(.empty) ? "" : HomeDisplay.signed(net, hidden: hide),
                            today: day == Dates.day(now), first: day == days.first)
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    billRow(entry, account: accounts[entry.accountID], pending: recoveryIDs.contains(entry.id), separator: index > 0)
                        .dsRowEnter(index: min((offsets[day] ?? 0) + index, DailySpending.columnCount))
                }
            }
        }
        .animation(reduceMotion ? nil : DSMotion.smoothAnimation, value: rows.first?.id)
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

    private func rowOffsets(days: [Date], groups: [Date: [Entry]]) -> [Date: Int] {
        var offset = 0
        var result: [Date: Int] = [:]
        for day in days {
            result[day] = offset
            offset += groups[day]?.count ?? 0
        }
        return result
    }

    private func newestFirst(_ a: Entry, _ b: Entry) -> Bool {
        (a.date, a.recordedAt ?? a.date, a.id.uuidString) > (b.date, b.recordedAt ?? b.date, b.id.uuidString)
    }

    private func billNet(_ rows: [Entry]) -> Int64 {
        rows.reduce(0) { net, entry in
            guard !entry.nature.paired else { return net }
            return net + (entry.nature.inflow ? entry.amount : -entry.amount)
        }
    }

    private func billRow(_ entry: Entry, account: Account?, pending: Bool, separator: Bool) -> some View {
        let category = ledger.normalizedCategory(for: entry).category
        let tag: DSInlineTag? = pending ? .init(title: entry.pendingRecovery == .split ? "待 AA" : "待报销")
            : (entry.intoFixedSavings || entry.nature == .investBuy) ? .init(title: "存入", tone: .positive) : nil
        let secondLine = searching
            ? [Dates.monthDay(entry.date), account?.name].compactMap { $0 }.joined(separator: " · ")
            : entry.originalCurrency != nil || account?.kind == .credit ? account?.name : nil
        return Button {
            focused = false
            openBill(entry.id)
        } label: {
            DSListRow(icon: HomeDisplay.icon(entry, category: category), name: entry.displayTitle,
                      amount: HomeDisplay.billAmount(entry, hidden: hide), detail: secondLine, tag: tag, separator: separator,
                      detailAmount: entry.originalCurrency.map { _ in "≈ " + HomeDisplay.money(entry.amount, hidden: hide) },
                      amountColor: entry.nature.inflow || entry.intoFixedSavings ? DS.Color.accentInk : DS.Color.ink)
                .contentShape(Rectangle())
        }.dsPressStyle().accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
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
        if !needle.isEmpty {
            let results = ledger.searchBills(needle, now: now)
            let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
            let pending = pendingIDs
            Button {
                focused = false
                openAsk(needle)
            } label: {
                HStack(spacing: DS.Space.s12) {
                    DSIconView(icon: .ai, size: DS.Size.brandTile, color: DS.Color.accentInk)
                        .frame(width: HomeSpec.tile32, height: HomeSpec.tile32).dsSurface(DS.Color.accentSoft, radius: DS.Radius.s)
                    Text("问余白「\(needle)」").dsText(HomeSpec.medium).lineLimit(1)
                    Spacer(minLength: .zero)
                    DSIconView(icon: .chevron, size: DS.Space.s16, color: DS.Color.accentInk)
                }.foregroundStyle(DS.Color.accentInk).padding(.vertical, DS.Space.s8).contentShape(Rectangle())
            }.dsPressStyle().padding(.top, DS.Space.s8).accessibilityIdentifier("askHomeSearch")
            DS.Color.separator.frame(height: DS.Stroke.hairline)
            DSDayHeader(title: "\(results.count) 笔", total: HomeDisplay.signed(billNet(results), hidden: hide))
                .accessibilityIdentifier("entriesSearchTotal")
            LazyVStack(spacing: .zero) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                    billRow(entry, account: accounts[entry.accountID], pending: pending.contains(entry.id), separator: index > 0)
                }
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

private struct HomeRunningOverlay: View {
    var body: some View {
        if HomeFixture.current?.isRunning == true {
            HStack(spacing: DS.Space.s8) {
                HStack(spacing: DS.Space.s4) {
                    ForEach(HomeSpec.statusDotOpacities, id: \.self) { opacity in
                        Circle().fill(DS.Color.accent)
                            .frame(width: HomeSpec.statusDots, height: HomeSpec.statusDots).opacity(opacity)
                    }
                }.dsBreathe().accessibilityHidden(true)
                Text("核对购物预算…").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink)
                Text("本机 AI").dsText(DS.Font.tTag).fontWeight(.regular)
                    .foregroundStyle(DS.Color.accentInk).padding(.horizontal, HomeSpec.gap6).dsPill(DS.Color.accentSoft)
            }.padding(.horizontal, DS.Space.s12).frame(minHeight: HomeSpec.statusHeight).dsPill(DS.Color.raised)
                .overlay(DS.Shape.pill.strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
                .dsShadow(DS.Shadow.float).padding(.bottom, HomeSpec.statusBottom)
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
#Preview("首页") {
    let fixture = HomeFixture.home(.normal)
    HomePage(ledger: fixture.makeLedger().ledger, now: fixture.now, request: nil, fixture: fixture, scrollRequest: 0,
             openBudget: {}, openSettings: {}, openBill: { _ in }, openAsk: { _ in },
             openVoice: {}, recordSalary: {}, cover: { _ in })
        .safeAreaInset(edge: .bottom, spacing: .zero) { DSTabBar(selection: .constant(.home), onEntry: {}) }
}
#endif
