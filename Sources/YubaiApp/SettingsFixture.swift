import Foundation
import YubaiCore

/// Canvas data for the settings, account and first-open boards. Debug launch arguments only.
enum SettingsFixture: Equatable {
    case main, mainEnd, cycle, recurring, categories, ai, aiKey, aiKeySaved, aiKeyDelete, hub
    case accountAdd, accountEdit, saving, floor, subAdd, subIcon, currency, export
    case onboard(Int)

    static let current: Self? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? { args.firstIndex(of: name).flatMap { args.dropFirst($0 + 1).first } }
        switch value("-YubaiSettingsFixture") {
        case "main": return .main
        case "main-end": return .mainEnd
        case "cycle": return .cycle
        case "recurring": return .recurring
        case "categories": return .categories
        case "ai": return .ai
        case "ai-key": return .aiKey
        case "ai-key-saved": return .aiKeySaved
        case "ai-key-delete": return .aiKeyDelete
        case "hub": return .hub
        default: break
        }
        switch value("-YubaiSettingsMoreFixture") {
        case "account-add": return .accountAdd
        case "account-edit": return .accountEdit
        case "saving": return .saving
        case "floor": return .floor
        case "sub-add": return .subAdd
        case "sub-icon": return .subIcon
        case "currency": return .currency
        case "export": return .export
        default: break
        }
        if let step = value("-YubaiOnboardFixture").flatMap(Int.init), (1...3).contains(step) { return .onboard(step) }
        #endif
        return nil
    }()

    var now: Date { Dates.parse("2026-11-23 12:00:00")! }
    /// A fake key: no request is ever sent from a fixture.
    var apiKey: String? { "sk-test-0000-fixture-3f2a" }
    /// The keychain already holds a key (the 删除密钥 boards).
    var hasSavedKey: Bool { self == .aiKeySaved || self == .aiKeyDelete }
    var storageBytes: Int64 { 126_000_000 }
    var calendarMonth: Date? { self == .recurring ? Dates.parse("2026-12-01") : nil }
    var openCategory: String? { self == .categories ? "购物" : nil }
    var iconSelection: String? { self == .subIcon ? "apple" : nil }
    var savingInput: Int64? { self == .saving ? 500_000 : nil }
    var accountAdd: (name: String, amount: Int64)? { self == .accountAdd ? ("招行储蓄", 3_218_000) : nil }

    #if DEBUG
    struct Seed {
        var ledger: Ledger
        var route: [TabRoute] = []
        var sheet: SettingsSheet?
        var draft = SubscriptionDraft()
        var onboarding: OnboardingDraft?
    }

    private static func date(_ text: String) -> Date { Dates.parse(text)! }

    @MainActor func makeSeed() -> Seed {
        if case .onboard(let step) = self {
            let draft = OnboardingDraft()
            draft.step = step; draft.day = 10; draft.takeHome = 1_850_000; draft.saving = 500_000
            draft.focusSaving = true
            if step == 3 {
                draft.accounts = [
                    OnboardingAccount(type: .debit, name: "招行储蓄", amount: 3_218_000, selected: true),
                    OnboardingAccount(type: .alipay, name: "支付宝", amount: 2_499_960, selected: true),
                    OnboardingAccount(type: .wechat, name: "微信零钱", amount: 124_040, selected: true),
                    OnboardingAccount(type: .credit, name: "信用卡", amount: 321_680, selected: true),
                    OnboardingAccount(type: .cash, name: "现金", amount: nil, selected: false),
                ]
            }
            var ledger = Ledger(); ledger.updatedAt = now
            return Seed(ledger: ledger, onboarding: draft)
        }
        var ledger = Ledger()
        ledger.updatedAt = now
        ledger.preferences.onboardingComplete = true
        ledger.preferences.hideAmounts = ProcessInfo.processInfo.environment["YUBAI_GALLERY_HIDE_AMOUNTS"] == "1"
        let bank = Account(name: "招行储蓄", balance: 3_218_000, at: Self.date("2026-11-20"))
        let alipay = Account(name: "支付宝", kind: .cash, balance: 2_499_960, at: Self.date("2026-11-20"))
        let wechat = Account(name: "微信零钱", kind: .cash, balance: 124_040, at: Self.date("2026-11-20"))
        var credit = Account(name: "招行信用卡", kind: .credit, balance: -321_680, at: Self.date("2026-11-20"))
        credit.creditLimit = 3_000_000; credit.creditStatementDay = 5; credit.creditPaymentDay = 23
        ledger.accounts = [bank, alipay, wechat, credit]
        ledger.categories = [
            YubaiCore.Category("吃饭", subcategories: ["早餐", "午餐", "晚餐", "夜宵"]),
            YubaiCore.Category("购物", subcategories: ["衣服", "数码配件", "日用杂货"]),
            YubaiCore.Category("交通", subcategories: ["地铁", "打车", "共享单车"]),
            YubaiCore.Category("居住", subcategories: ["房租", "水电", "物业"]),
            YubaiCore.Category("买菜", subcategories: ["超市", "菜场"]),
            YubaiCore.Category("娱乐", subcategories: ["电影", "演出", "游戏", "旅行"]),
            YubaiCore.Category("日用", subcategories: ["清洁", "洗护"]),
            YubaiCore.Category("咖啡"), YubaiCore.Category("其他"),
            YubaiCore.Category("工资奖金", income: true), YubaiCore.Category("其他收入", income: true),
        ]
        ledger.preferences.categoryOrder = ledger.categories.filter { !$0.income }.map(\.id)
        try? Payday.configure(day: 10, amount: 1_850_000, accountID: bank.id, in: &ledger, now: now)
        ledger.paydayConfirmSince = nil
        Finance.enablePaydayConfirmation(&ledger, now: now)
        ledger.savingRule = .fixed(500_000)
        ledger.fixedSavings = 0
        ledger.profile.floorAmount = 5_000_000
        let subscriptions: [(String, Int64, Int, UUID, String?)] = [
            ("超级猩猩", 30_000, 15, credit.id, nil), ("腾讯视频", 2_500, 12, alipay.id, nil), ("中国移动", 2_500, 1, wechat.id, nil),
            ("iCloud+", 2_100, 12, credit.id, "icloud"), ("网易云音乐", 1_500, 12, alipay.id, "netease-cloud-music"),
        ]
        for (title, amount, day, account, slug) in subscriptions {
            var plan = Plan(title: title, amount: amount, dueDate: Payday.nominalDate(day: day, inMonthOf: Self.date("2026-10-01")), frequency: .monthly, category: "日用")
            plan.monthlyDay = day; plan.accountID = account; plan.iconSlug = slug
            ledger.plans.append(plan)
        }
        ledger.preferences.billExchangeRates = [
            ManualExchangeRate(currency: .jpy, cnyPerUnit: Decimal(string: "0.0475")!, updatedAt: Self.date("2026-11-25")),
            ManualExchangeRate(currency: .usd, cnyPerUnit: Decimal(string: "7.2410")!, updatedAt: Self.date("2026-11-25")),
            ManualExchangeRate(currency: .hkd, cnyPerUnit: Decimal(string: "0.9302")!, updatedAt: Self.date("2026-11-25")),
        ]
        ledger.preferences.lastBillCurrency = .jpy
        ledger.preferences.cloudAIEnabled = true
        ledger.preferences.assistantTone = .direct
        ledger.preferences.lockEnabled = true
        ledger.preferences.weeklyLetterPush = true
        ledger.preferences.lastBackupAt = Self.date("2026-11-24 09:00")
        var batch = ImportBatch(filename: "招商银行信用卡账单.csv", importedCount: 0, duplicateCount: 0, skippedCount: 0)
        batch.importedAt = Self.date("2026-11-20 10:00"); batch.needsOrganization = false
        ledger.imports = [batch]
        // canvas Settings.dc.html hub: 2 件 / 11.23 / 5 条
        ledger.wishlist = [WishItem(title: "降噪耳机", amount: 129_900), WishItem(title: "羽绒被", amount: 89_900)]
        var letter = ButlerCard(kind: .weeklyLetter, title: "每周来信", body: "", dedupeKey: "letter:2026-11-23")
        letter.createdAt = Self.date("2026-11-23 21:00")
        ledger.cards = [letter]
        ledger.profile.restrain = [ProfileArea(title: "数码", note: "能用就不换"), ProfileArea(title: "外卖")]
        ledger.profile.generous = [ProfileArea(title: "书")]
        ledger.profile.principles = ["大件先冷静三天", "不借钱买东西"]
        ledger.memories = (1...23).map { MemoryNote(text: "记住的事 \($0)", kind: .life, source: .user, createdAt: Self.date("2026-11-01")) }
        // Entries for the export counts: 86 this cycle, 112 last cycle, 1,284 in all.
        func spend(_ count: Int, from start: String, days: Int) {
            for index in 0..<count {
                let day = Dates.addDays(index % days, to: Self.date(start))
                ledger.entries.append(Entry(date: day.addingTimeInterval(43_200), amount: 3_000, accountID: bank.id, title: "午饭", category: "吃饭"))
            }
        }
        spend(86, from: "2026-11-10", days: 14)
        spend(112, from: "2026-10-10", days: 31)
        spend(1_284 - 86 - 112, from: "2025-01-01", days: 600)

        var seed = Seed(ledger: ledger)
        switch self {
        case .main, .mainEnd: seed.route = [.settings]
        case .cycle: seed.route = [.settings]; seed.sheet = .cycle
        case .recurring: seed.route = [.settings, .recurring]
        case .categories: seed.route = [.settings, .categorySettings]
        case .ai: seed.route = [.settings, .aiSettings]
        case .aiKey, .aiKeySaved, .aiKeyDelete: seed.route = [.settings, .aiSettings]; seed.sheet = .apiKey(enabling: false)
        case .accountAdd: seed.route = []; seed.sheet = .accountAdd(.debit, onboarding: false)
        case .accountEdit: seed.route = [.accountDetail(credit.id), .accountEdit(credit.id)]
        case .saving: seed.route = [.settings]; seed.sheet = .saving
        case .floor: seed.route = [.settings]; seed.sheet = .floor
        case .subAdd:
            seed.route = [.settings, .recurring]; seed.sheet = .subAdd
            seed.draft = SubscriptionDraft(name: "Apple One", amount: 6_800, day: 12, yearly: false, slug: "apple")
        case .subIcon:
            seed.route = [.settings, .recurring]; seed.sheet = .subIcon
            seed.draft = SubscriptionDraft(name: "Apple One", amount: 6_800, day: 12, yearly: false, slug: nil)
        case .currency: seed.route = [.settings, .currency]
        case .hub: seed.route = [.settings, .wishesHub]
        case .export: seed.route = [.settings]; seed.sheet = .export
        case .onboard: break
        }
        return seed
    }
    #endif
}
