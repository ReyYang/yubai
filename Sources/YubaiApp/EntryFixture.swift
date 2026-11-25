#if DEBUG
import SwiftUI
import YubaiCore

enum EntryFixture: String, CaseIterable {
    case expense, aa, income, transfer, move, deposit, large, foreign, fixed, time, cats
    case subcategoryAdd = "flow-subcat-add"
    case calendar = "flow-calendar"
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
    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: name).flatMap { args.dropFirst($0 + 1).first }
    }

    @MainActor func makeModel() -> EntrySheetViewModel {
        let today = date("2026-11-23 14:20:00")
        let bank = Account(name: "招行储蓄", kind: .bank, balance: 3_018_000, at: today)
        let credit = Account(name: "招行信用卡", kind: .credit, balance: -321_680, at: today)
        let wallet = Account(name: "支付宝", kind: .cash, balance: 462_000, at: today)
        let funds = Account(name: "基金账户", kind: .investment, balance: 400_000, at: today)
        var ledger = Ledger()
        ledger.accounts = [bank, credit, wallet, funds]
        ledger.fixedSavings = 842_000
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
        ledger.preferences.categoryOrder = ledger.categories.map(\.id)
        ledger.entries = [
            Entry(date: today, amount: 2_200, accountID: bank.id, title: "早餐", category: "吃饭"),
            Entry(date: date("2026-11-22 16:14:00"), amount: 2_900, accountID: wallet.id, title: "咖啡", category: "咖啡"),
            Entry(date: date("2026-11-22 13:10:00"), amount: 350, accountID: wallet.id, title: "地铁", category: "交通")
        ]
        var draft = EntrySheetDraft()
        draft.date = today
        draft.accountID = bank.id
        var result = EntryResult(title: "记下后还能花", value: "¥6,226.40", note: "吃饭剩 1,194.00")
        var top = ["吃饭", "咖啡", "交通", "买菜"]
        var dayLabel: String?
        var repeatDay: Int?

        switch self {
        case .expense, .time, .calendar, .guess:
            draft.expression = EntryAmountExpression(expression: "42.00")
            draft.purpose = "午饭"
            if self != .guess { draft.category = "吃饭"; draft.subcategory = "午餐" }
        case .cats, .subcategoryAdd:
            draft.expression = EntryAmountExpression(expression: "42.00")
            draft.purpose = "午饭"
            draft.category = "购物"
            draft.subcategory = "衣服"
        case .aa:
            draft.expression = EntryAmountExpression(expression: "78.00")
            draft.purpose = "电影票 · IMAX"
            draft.category = "娱乐"
            draft.subcategory = "电影"
            draft.accountID = credit.id
            draft.date = date("2026-11-22 14:20:00")
            dayLabel = "11月22日"
            draft.exception = .split
            draft.personalShare = "26.00"
            result = EntryResult(title: "记下后还能花", value: "¥6,190.40", note: "待收回 52.00")
            top = ["娱乐", "吃饭", "咖啡", "交通"]
        case .income:
            draft.type = .income
            draft.expression = EntryAmountExpression(expression: "18500.00")
            draft.purpose = "工资"
            draft.category = "工资"
            draft.date = date("2026-12-09 14:20:00")
            draft.incomeNextCycle = true
            top = ["工资", "奖金", "退款", "其他"]
            result = EntryResult(title: "12.10 起计入", value: "+18,500.00", note: "本期不变")
        case .transfer, .move, .deposit:
            draft.type = self == .deposit ? .deposit : .transfer
            draft.destinationID = self == .deposit ? funds.id : self == .transfer ? credit.id : wallet.id
            draft.expression = EntryAmountExpression(expression: self == .deposit ? "1000.00" : self == .transfer ? "3216.80" : "2000.00")
            draft.purpose = self == .deposit ? "基金定投" : self == .transfer ? "还信用卡" : "转到支付宝"
            result = EntryResult(title: "还能花", value: "不变")
            if self == .deposit {
                draft.repeatMonthly = true
                repeatDay = 15
                result.note = "本期已攒下 5,000.00"
            }
        case .large:
            draft.expression = EntryAmountExpression(expression: "6999.00")
            draft.purpose = "换手机"
            draft.category = "购物"
            draft.subcategory = "数码"
            draft.accountID = credit.id
            draft.exception = .reserve
            top = ["购物", "吃饭", "娱乐", "买菜"]
            result = EntryResult(title: "还能花", value: "不变", note: "机动余钱 → 1,421.00")
        case .fixed:
            draft.expression = EntryAmountExpression(expression: "58.00")
            draft.purpose = "手机话费"
            draft.category = "日用"
            draft.subcategory = "话费"
            draft.repeatMonthly = true
            repeatDay = 23
            top = ["日用", "吃饭", "交通", "购物"]
            result = EntryResult(title: "记下后还能花", value: "¥6,210.40", note: "下期起期初预扣 58.00")
        case .foreign, .longJPY:
            draft.expression = EntryAmountExpression(expression: self == .longJPY ? "1234567.89" : "3280")
            draft.purpose = "出差 · 便利店"
            draft.category = "吃饭"
            draft.subcategory = "便利店"
            draft.currency = .jpy
            draft.exchangeRate = "0.0475"
            draft.accountID = credit.id
            draft.exception = .reimbursement
            result = self == .longJPY
                ? EntryResult(title: "缺口", value: "¥52,373.57", note: "暂扣 58,641.97", warning: true)
                : EntryResult(title: "记下后还能花", value: "¥6,112.60", note: "暂扣 155.80")
        case .empty:
            result = EntryResult(title: "本月还能花", value: "¥6,268.40")
        }

        let model = EntrySheetViewModel(fixtureLedger: ledger, draft: draft, now: today, result: result)
        model.fixtureTopCategories = top
        model.fixtureDayLabel = dayLabel
        model.fixtureRepeatDay = repeatDay
        model.routeShowsBalance = self == .move
        if self == .aa { model.fixtureSplitNames = ["我", "林", "周"] }
        if self == .time { model.drawer = .time }
        if self == .calendar { model.drawer = .calendar }
        if self == .guess { model.suggestion = CategoryGuesser.guess(draft.purpose, nature: .expense, date: today, in: ledger) }
        if self == .cats || self == .subcategoryAdd {
            model.categoryPanel = self == .cats
            model.drawer = .subcategory
            model.autoFocusSubcategory = false
            model.inputText = self == .cats ? "运动鞋" : ""
        }
        return model
    }

    private func date(_ text: String) -> Date {
        guard let value = Dates.parse(text) else { preconditionFailure("Invalid entry fixture date: " + text) }
        return value
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
            DSDayHeader(title: "今天", total: "¥22.00")
            DSListRow(icon: .catFood, name: "早餐", amount: "22.00", separator: false)
            DSDayHeader(title: "昨天", total: "¥32.50")
            DSListRow(icon: .catCoffee, name: "咖啡", amount: "29.00", separator: false)
            DSListRow(icon: .catTransport, name: "地铁", amount: "3.50")
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
