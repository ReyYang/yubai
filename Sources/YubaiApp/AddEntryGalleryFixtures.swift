#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let addEntryScripts: Set<String> = ["v46-entry", "v46-entry-big", "v46-entry-hard", "v46-entry-receipt"]
    static var addEntryExplicitFinish: Bool {
        script != nil && ProcessInfo.processInfo.environment["YUBAI_UI_TEST_ENTRY_EXPLICIT_FINISH"] == "1"
    }
    static var addEntryReceipt: ReceiptCandidate? {
        guard script == "v46-entry-receipt" else { return nil }
        let text = ["山姆会员商店", Dates.text(Date()), "牛奶、鸡蛋、蔬菜 -96.50 支出", "洗衣液 -59.90 支出", "坚果 -30.00 支出", "合计 186.40"].joined(separator: "\n")
        return ReceiptCandidate(text: text, amounts: ["96.50", "59.90", "30.00"], title: "山姆会员商店", date: Date())
    }
    static func addEntryReceiptReply(_ request: ChatRequest, script: String) throws -> ChatMessage? {
        guard script == "v46-entry-receipt", request.purpose == "拍小票、认截图" else { return nil }
        let rows: [JSONValue] = [("牛奶、鸡蛋、蔬菜", "96.50", "买菜"), ("洗衣液", "59.90", "日用"), ("坚果", "30.00", "买菜")].map {
            .object(["title": .string($0.0), "amount": .string($0.1), "date": .string(Dates.text(Date())), "income": .bool(false), "category": .string($0.2)])
        }
        return .init(role: .assistant, content: try JSONValue.object(["shop": .string("山姆会员商店"), "rows": .array(rows)]).jsonText())
    }
    static func addEntryLedger(_ script: String, now: Date) throws -> Ledger {
        let today = Dates.day(now), hard = script == "v46-entry-hard"
        var ledger = Ledger()
        ledger.id = galleryID(4602); ledger.updatedAt = today
        ledger.preferences.onboardingComplete = true; ledger.preferences.profileColdStartDone = true
        ledger.preferences.appearance = galleryAppearance ?? "light"
        ledger.preferences.cloudAIEnabled = script == "v46-entry-receipt"
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now); ledger.lastSubcategoryBatchDay = Dates.text(now)
        ledger.cycleAnchor = .calendarMonth; ledger.fixedSavings = 500_000; ledger.savingRule = .fixed(300_000)
        ledger.profile.principles = ["超过 1,000 等 48 小时"]
        let names = [hard ? galleryLongTitle : "招行储蓄卡", hard ? galleryLatinTitle : "微信零钱", "支付宝", "现金", "信用卡"]
        let kinds: [AccountKind] = [.bank, .cash, .cash, .cash, .credit]
        let balances: [Int64] = [hard ? 987_654_321 : script == "v46-entry-big" ? 912_400 : 921_400, 186_000, 0, 0, -151_000]
        ledger.accounts = names.indices.map { index in
            var account = Account(name: names[index], kind: kinds[index], balance: balances[index], at: today)
            account.id = galleryID(4620 + index); return account
        }
        let expenseNames = ["餐饮", "购物", "交通", "居住", "日用", "娱乐", "医疗", "美容", "人情", "买菜", "数码", "服饰", "医疗健康", "旅行", "人情往来", "学习", "宠物", "通讯", "其他支出"]
        let symbols = ["fork.knife", "bag", "tram", "house", "basket", "play.circle", "cross.case", "scissors", "heart"]
        ledger.categories = expenseNames.enumerated().map { index, name in
            YubaiCore.Category(name, index < symbols.count ? symbols[index] : "tag", subcategories: name == "餐饮" ? ["早餐", "午餐", "晚餐", "咖啡饮品"] : [])
        } + YubaiCore.Category.defaults.filter { $0.income || $0.system }
        ledger.categories.append(YubaiCore.Category(galleryLongTitle, "tag"))
        ledger.categories.append(YubaiCore.Category(galleryLatinTitle, "tag", income: true))
        ledger.preferences.categoryOrder = expenseNames.map { CategoryNamespace.key($0, income: false) }
        var number = 4650
        func add(_ title: String, _ amount: Int64, _ category: String, _ days: Int) {
            var entry = Entry(date: Dates.addDays(-days, to: now), amount: amount, accountID: ledger.accounts[0].id,
                              title: title, category: category)
            entry.id = galleryID(number); number += 1; entry.recordedAt = entry.date; ledger.entries.append(entry)
        }
        for offset in [1, 2] {
            add("地铁", 800, "交通", offset); add("午饭", 2800, "餐饮", offset); add("咖啡", 3200, "餐饮", offset)
        }
        add("咖啡豆", 12_800, "购物", 3)
        add("剪头发", 6800, "美容", 20); add("剪头发", 6800, "美容", 40); add("剪头发", 6800, "购物", 1)
        if hard { add(galleryLongTitle + galleryLatinTitle, 123_456_789, "餐饮", 1) }
        let parkingTitle = hard ? galleryLatinTitle : "停车", parkingAmount: Int64 = hard ? 123_456_789 : 1200
        add(parkingTitle, parkingAmount, "交通", 1); add(parkingTitle, parkingAmount, "交通", 2)
        let repeats = EntryHistory.repeats(in: ledger, now: now, limit: 1000)
        if let subway = repeats.first(where: { $0.purpose == "地铁" }) { try EntryHistory.setPinned(subway, pinned: true, in: &ledger) }
        if let parking = repeats.first(where: { $0.purpose == parkingTitle }) { try EntryHistory.setHidden(parking, hidden: true, in: &ledger) }
        try ledger.validate(); return ledger
    }
}
#endif
