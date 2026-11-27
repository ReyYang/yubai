#if DEBUG
import SwiftUI
import YubaiCore

enum EntryFixture: String, CaseIterable {
    case expense, aa, income, transfer, move, deposit, large, foreign, fixed, time, cats
    case nocat, more, account, purpose, manage
    /// X-entry-norate: a foreign amount with no rate synced or fixed. S-Entry-Ccy / S-Entry-Rate open their lists.
    case norate, ccy, rate
    case calendarPopover = "flow-calendar-popover"
    case empty = "flow-empty-draft"
    case guess = "flow-guess-only"
    case longJPY = "flow-long-jpy"

    static var launchMode: Self? { argument("-YubaiEntryFixture").flatMap(Self.init(rawValue:)) }
    static var launchTheme: ColorScheme? {
        switch argument("-YubaiTheme") {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
    static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: name).flatMap { args.dropFirst($0 + 1).first }
    }

    @MainActor func makeModel(includeDigital: Bool = false) -> EntrySheetViewModel {
        let today = EntrySpec.fixtureToday
        let bank = Account(name: "招行储蓄", kind: .bank, balance: EntrySpec.fixtureBank, at: today)
        let credit = Account(name: "招行信用卡", kind: .credit, balance: EntrySpec.fixtureCredit, at: today)
        let wallet = Account(name: "支付宝", kind: .cash, balance: EntrySpec.fixtureWallet, at: today)
        let funds = Account(name: "基金账户", kind: .investment, balance: EntrySpec.fixtureFunds, at: today)
        var ledger = Ledger()
        ledger.accounts = [bank, credit, wallet, funds]
        ledger.fixedSavings = EntrySpec.fixtureSavings
        ledger.cycleAnchor = .calendarMonth
        ledger.categories = [
            YubaiCore.Category("吃饭", subcategories: self == .foreign || self == .longJPY
                     ? ["便利店", "正餐", "咖啡"] : ["午餐", "早餐", "晚餐", "夜宵"], keywords: ["午饭"]),
            YubaiCore.Category("购物", subcategories: self == .large ? ["数码", "衣服", "日用"] : ["衣服", "数码配件", "日用杂货"]),
            YubaiCore.Category("交通"), YubaiCore.Category("居住"), YubaiCore.Category("买菜"),
            YubaiCore.Category("娱乐", subcategories: ["电影", "演出", "游戏"]),
            YubaiCore.Category("日用", subcategories: ["话费", "宽带", "会员"]),
            YubaiCore.Category("咖啡"), YubaiCore.Category("其他"),
            YubaiCore.Category("工资", income: true), YubaiCore.Category("奖金", income: true),
            YubaiCore.Category("退款", income: true), YubaiCore.Category("其他", income: true)
        ]
        if includeDigital { ledger.categories.append(YubaiCore.Category("数码")) }
        ledger.preferences.categoryOrder = ledger.categories.map(\.id)
        ledger.entries = [
            Entry(date: today, amount: EntrySpec.fixtureBreakfast, accountID: bank.id, title: "早餐", category: "吃饭"),
            Entry(date: EntrySpec.fixtureYesterdayCoffee, amount: EntrySpec.fixtureCoffee, accountID: wallet.id, title: "咖啡", category: "咖啡"),
            Entry(date: EntrySpec.fixtureYesterdayMetro, amount: EntrySpec.fixtureMetro, accountID: wallet.id, title: "地铁", category: "交通")
        ]
        var draft = EntrySheetDraft()
        draft.date = today
        draft.accountID = bank.id
        var top = ["吃饭", "咖啡", "交通", "买菜"]
        var dayLabel: String?
        var repeatDay: Int?

        switch self {
        case .expense, .time, .calendarPopover, .guess, .more, .account, .purpose:
            draft.expression = EntryAmountExpression(expression: EntrySpec.fixtureLunchAmount)
            draft.purpose = "午饭"
            if self != .guess { draft.category = "吃饭"; draft.subcategory = "午餐" }
        case .cats, .manage:
            draft.expression = EntryAmountExpression(expression: EntrySpec.fixtureLunchAmount)
            draft.purpose = "午饭"
            draft.category = "购物"
            draft.subcategory = "衣服"
        case .aa:
            draft.expression = EntryAmountExpression(expression: EntrySpec.fixtureSplitTotal)
            draft.purpose = "电影票 · IMAX"
            draft.category = "娱乐"
            draft.subcategory = "电影"
            draft.accountID = credit.id
            draft.date = EntrySpec.fixtureCalendarSelection
            dayLabel = "11月22日"
            draft.exception = .split
            draft.personalShare = EntrySpec.fixtureSplitShare
            top = ["娱乐", "吃饭", "咖啡", "交通"]
        case .income:
            draft.type = .income
            draft.expression = EntryAmountExpression(expression: EntrySpec.fixtureIncomeAmount)
            draft.purpose = "工资"
            draft.category = "工资"
            draft.date = EntrySpec.fixtureIncomeDate
            draft.incomeNextCycle = true
            top = ["工资", "奖金", "退款", "其他"]
        case .transfer, .move, .deposit:
            draft.type = self == .deposit ? .deposit : .transfer
            draft.destinationID = self == .deposit ? funds.id : self == .transfer ? credit.id : wallet.id
            draft.expression = EntryAmountExpression(expression: self == .deposit ? EntrySpec.fixtureDepositAmount :
                self == .transfer ? EntrySpec.fixtureRepaymentAmount : EntrySpec.fixtureMoveAmount)
            draft.purpose = self == .deposit ? "基金定投" : self == .transfer ? "还信用卡" : "转到支付宝"
            if self == .deposit {
                draft.repeatMonthly = true
                repeatDay = EntrySpec.fixtureDepositDay
            }
        case .large:
            draft.expression = EntryAmountExpression(expression: EntrySpec.fixtureReserveAmount)
            draft.purpose = "换手机"
            draft.category = "购物"
            draft.subcategory = "数码"
            draft.accountID = credit.id
            draft.exception = .reserve
            top = ["购物", "吃饭", "娱乐", "买菜"]
        case .fixed:
            draft.expression = EntryAmountExpression(expression: EntrySpec.fixtureMonthlyAmount)
            draft.purpose = "手机话费"
            draft.category = "日用"
            draft.subcategory = "话费"
            draft.repeatMonthly = true
            repeatDay = EntrySpec.galleryRepeatDay
            top = ["日用", "吃饭", "交通", "购物"]
        case .foreign, .longJPY:
            draft.expression = EntryAmountExpression(expression: self == .longJPY ? EntrySpec.fixtureLongJPYAmount : EntrySpec.fixtureJPYAmount)
            draft.purpose = "出差 · 便利店"
            draft.category = "吃饭"
            draft.subcategory = "便利店"
            draft.currency = .jpy
            draft.exchangeRate = EntrySpec.fixtureJPYRate
            draft.accountID = credit.id
            draft.exception = .reimbursement
        case .norate, .ccy, .rate:
            draft.expression = EntryAmountExpression(expression: "1280")
            draft.purpose = "一兰拉面"
            draft.category = "吃饭"
            draft.currency = self == .norate ? .jpy : .cad
            draft.accountID = credit.id
            if self != .norate {
                draft.expression = EntryAmountExpression(expression: "4.25")
                draft.purpose = "咖啡"
            }
        case .empty: break
        case .nocat:
            draft.expression = EntryAmountExpression(expression: EntrySpec.fixtureLunchAmount)
        }

        if self == .time || self == .calendarPopover { draft.date = EntrySpec.fixtureCalendarSelection }
        let synced = self == .ccy || self == .rate
            ? SyncedExchangeRates(date: today, fetchedAt: today, cnyPerUnit: ["CAD": Decimal(string: "5.1012")!]) : nil
        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: draft, now: today, synced: synced)
        model.fixtureTopCategories = top
        model.fixtureDayLabel = dayLabel
        model.fixtureRepeatDay = repeatDay
        model.routeShowsBalance = self == .move
        if self == .aa { model.fixtureSplitNames = ["我", "林", "周"] }
        if self == .time || self == .calendarPopover { model.drawer = .calendar }
        if self == .guess { model.suggestion = CategoryGuesser.guess(draft.purpose, nature: .expense, date: today, in: ledger) }
        if self == .cats || self == .manage {
            model.categoryPanel = true
            model.expandedCategory = "购物"
            model.managingCategories = self == .manage
        }
        if self == .nocat { model.needsCategory = true }
        if self == .more { model.drawer = .more }
        if self == .account { model.drawer = .source }
        if self == .purpose { model.drawer = .purpose }
        if self == .ccy { model.drawer = .currency }
        if self == .rate { model.drawer = .rate }
        return model
    }
}

struct EntryFixtureScreen: View {
    let mode: EntryFixture
    var theme: ColorScheme? = nil
    @State private var model: EntrySheetViewModel?
    @State private var retained: EntrySheetViewModel?

    var body: some View {
        ZStack {
            EntryFixtureLedger()
                .accessibilityHidden(model != nil)
            if let model {
                EntrySheetOverlay(model: model) {
                    retained = model
                    self.model = nil
                }
                .id(model.id)
            } else if let retained {
                VStack {
                    Spacer()
                    Button("记一笔") {
                        let next = mode.makeModel()
                        next.restoreFixtureDraft(retained)
                        model = next
                    }
                    .dsText(DS.Font.tTitle).foregroundStyle(DS.Color.onAccent)
                    .padding(.horizontal, DS.Space.s28)
                    .frame(minHeight: DS.Size.tapMin)
                    .dsPill(DS.Color.accent)
                    .buttonStyle(EntryTactileButtonStyle())
                    .padding(.bottom, DS.Space.s16)
                }
            }
        }
        .preferredColorScheme(theme)
        .onAppear { if model == nil && retained == nil { model = mode.makeModel() } }
    }
}

private struct EntryFixtureLedger: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            HStack {
                Text("账本").dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                Spacer()
                DS.Icon.search.view(size: DS.Size.icon, color: DS.Color.ink3)
            }
            .frame(minHeight: DS.Size.tapMin)
            DSDayHeader(title: "今天", total: Money.text(EntrySpec.fixtureBreakfast))
            DSListRow(icon: .catFood, name: "早餐", amount: Money.text(EntrySpec.fixtureBreakfast, currency: false), separator: false)
            DSDayHeader(title: "昨天", total: Money.text(EntrySpec.fixtureCoffee + EntrySpec.fixtureMetro))
            DSListRow(icon: .catCoffee, name: "咖啡", amount: Money.text(EntrySpec.fixtureCoffee, currency: false), separator: false)
            DSListRow(icon: .catTransport, name: "地铁", amount: Money.text(EntrySpec.fixtureMetro, currency: false))
            Spacer()
        }
        .padding(.horizontal, DS.Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.bg.ignoresSafeArea())
    }
}

#Preview("支出 · 浅色") { EntryFixtureScreen(mode: .expense, theme: .light) }
#Preview("分类 · 深色") { EntryFixtureScreen(mode: .cats, theme: .dark) }
#endif
