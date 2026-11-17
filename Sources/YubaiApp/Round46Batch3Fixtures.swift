#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static func seedBatch3Questions(for id: UUID) {
        guard id == galleryID(460300) else { return }
        let now = Dates.now
        let rows: [[String: Any]] = [["t": "降噪耳机 1,899，能买吗", "d": Dates.addDays(-1, to: now).timeIntervalSince1970],
                                   ["t": "这个月钱去哪了", "d": Dates.addDays(-3, to: now).timeIntervalSince1970]]
        UserDefaults.standard.set(rows, forKey: "yubai.recentQuestions." + id.uuidString)
    }
    static let batch3Scripts: Set<String> = ["v46-b3-book", "v46-b3-empty", "v46-b3-where-empty", "v46-b3-budget-empty", "v46-b3-save-empty", "v46-b3-share", "v46-b3-reserve", "v46-b3-hard"]
    static func batch3Ledger(_ script: String, now: Date) throws -> Ledger {
        let today = Dates.day(now)
        let month = Dates.calendar.dateInterval(of: .month, for: now)!.start
        var ledger = Ledger(); ledger.id = galleryID(460300); ledger.updatedAt = now
        ledger.preferences.onboardingComplete = true; ledger.preferences.profileColdStartDone = true
        ledger.preferences.cloudAIEnabled = true; ledger.preferences.appearance = galleryAppearance ?? "light"
        ledger.cycleAnchor = .calendarMonth
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now); ledger.lastSubcategoryBatchDay = Dates.text(now)
        if script == "v46-b3-empty" { try ledger.validate(); return ledger }
        var bank = Account(name: "招行储蓄卡", kind: .bank, balance: 1_000_000, at: Dates.addMonths(-4, to: month)); bank.id = galleryID(460301)
        ledger.accounts = [bank]; ledger.fixedSavings = script == "v46-b3-save-empty" ? 0 : 300_000
        if script == "v46-b3-save-empty" { seedKnownHomeBudget(&ledger, now: now); try ledger.validate(); return ledger }
        ledger.savingRule = .fixed(200_000)
        func add(_ id: Int, title: String, cents: Int64, at: Date, category: String, subcategory: String? = nil, nature: Nature = .expense) {
            var entry = Entry(date: at, amount: cents, nature: nature, accountID: bank.id, title: title, category: category)
            entry.id = galleryID(id); entry.recordedAt = now; entry.subcategory = subcategory; entry.subcategoryUserEdited = true
            ledger.entries.append(entry)
        }
        if script == "v46-b3-where-empty" {
            for index in 0..<12 { add(460310 + index, title: "午饭", cents: 2800, at: today, category: "餐饮") }
            try ledger.validate(); return ledger
        }
        var batch = ImportBatch(filename: "招商银行信用卡账单.csv", importedCount: 4, duplicateCount: 0, skippedCount: 0)
        batch.id = galleryID(460302); batch.needsOrganization = false
        ledger.imports = [batch]
        add(460310, title: "云上艾珀（贵州）技术有限公司 · 快捷支付", cents: 6800, at: Dates.addDays(-1, to: today), category: Classification.pendingCategory)
        ledger.entries[0].batchID = batch.id; ledger.entries[0].source = "招商银行信用卡账单"; ledger.entries[0].sourceRow = 2
        ledger.entries[0].note = "交易对方 云上艾珀（贵州）技术有限公司\n商品 快捷支付-连续包年"
        try QuickCapture.remember(merchant: ledger.entries[0].title, category: "会员订阅", income: false, in: &ledger)
        add(460311, title: "没细记", cents: 41_200, at: today, category: Classification.pendingCategory)
        ledger.entries[1].spreadFrom = Dates.addDays(-2, to: today)
        add(460312, title: "财付通 · 扫码付款", cents: 2300, at: Dates.addDays(-2, to: today), category: Classification.pendingCategory)
        add(460313, title: "支付宝 · 转账", cents: 20_000, at: Dates.addDays(-3, to: today), category: Classification.pendingCategory)
        add(460314, title: "晚饭", cents: 4500, at: today, category: "餐饮", subcategory: "晚餐")
        add(460315, title: "地铁", cents: 950, at: today, category: "交通", subcategory: "公共交通")
        add(460316, title: "山姆会员商店", cents: 18_640, at: Dates.addDays(-1, to: today), category: "购物")
        add(460317, title: "山姆会员商店", cents: 29_800, at: Dates.addMonths(-1, to: today), category: "购物")
        add(460318, title: "山姆会员店 · 加油", cents: 12_800, at: Dates.addMonths(-2, to: today), category: "交通")
        for offset in 1...3 {
            let start = Dates.addMonths(-offset, to: month)
            add(460320 + offset * 3, title: "工资", cents: 800_000, at: start, category: "工资奖金", nature: .income)
            add(460321 + offset * 3, title: "公司楼下午饭", cents: 62_400, at: start, category: "餐饮", subcategory: "午餐")
            add(460322 + offset * 3, title: "打车", cents: 9200, at: start, category: "交通", subcategory: "打车")
            add(460350 + offset, title: "外卖", cents: 18_000, at: start, category: "餐饮", subcategory: "外卖")
            add(460360 + offset, title: "日常用品", cents: 190_000, at: start, category: "购物")
        }
        for index in 0..<9 { add(460370 + index, title: "公司楼下午饭", cents: 2800, at: month, category: "餐饮", subcategory: "午餐") }
        add(460380, title: "外卖", cents: 9600, at: today, category: "餐饮", subcategory: "外卖")
        add(460381, title: "打车", cents: 13_200, at: today, category: "交通", subcategory: "打车")
        let names = ["健身房", "视频会员", "音乐会员", "云盘"]
        let amounts: [Int64] = [19_900, 2500, 5000, 1500]
        for index in names.indices {
            var plan = Plan(title: names[index], amount: amounts[index], dueDate: Dates.addDays(index + 1, to: today), frequency: .monthly, category: "会员订阅")
            plan.id = galleryID(460390 + index); plan.accountID = bank.id
            ledger.plans.append(plan)
        }
        add(460395, title: "健身房 · 私教课", cents: 5000, at: Dates.addMonths(-1, to: month), category: "娱乐")
        var due = WishItem(title: "降噪耳机", amount: 189_900, purpose: "通勤地铁太吵")
        due.id = galleryID(460400); due.createdAt = Dates.addDays(-7, to: today); due.coolUntil = today
        var camera = WishItem(title: "相机", amount: 860_000); camera.id = galleryID(460401); camera.createdAt = now; camera.coolUntil = Dates.addDays(7, to: today)
        var coat = WishItem(title: "大衣", amount: 120_000); coat.id = galleryID(460402); coat.createdAt = Dates.addDays(-5, to: today); coat.coolUntil = Dates.addDays(2, to: today)
        var coffee = WishItem(title: "咖啡机", amount: 248_000); coffee.id = galleryID(460403); coffee.createdAt = Dates.addDays(-12, to: today)
        var dropped = WishItem(title: "音箱", amount: 129_900); dropped.id = galleryID(460404); dropped.status = .dropped; dropped.droppedAt = Dates.addDays(-1, to: today)
        ledger.wishlist = [due, camera, coat, coffee, dropped]
        var takeaway = ProfileArea(title: "外卖", match: AreaMatch(categories: ["餐饮"], keywords: ["外卖"]), note: "每周最多 3 次", softLimit: SoftLimit(perWeekCount: 3))
        takeaway.id = galleryID(460410)
        ledger.profile.restrain = [takeaway, ProfileArea(title: "打车", match: AreaMatch(categories: ["交通"], keywords: ["打车"]))]
        ledger.profile.generous = [ProfileArea(title: "书"), ProfileArea(title: "和朋友吃饭")]
        ledger.profile.principles = ["超过 2,000 等 48 小时", "为每天用得上的东西花钱"]
        let memories = ["每周五晚上常和同事吃饭，一次 90 左右", "电费夏天会到 200 以上", "想在春节前换手机，预算 5,000", "云上艾珀是视频会员，分到会员订阅"]
        for index in 0..<14 {
            let text = index < memories.count ? memories[index] : "生活记录 \(index + 1)"
            ledger.memories.append(MemoryNote(id: galleryID(460420 + index), text: text, kind: .life,
                                             source: index < 2 ? .reflection : index == 3 ? .importAnswer : .user, createdAt: Dates.addDays(-index, to: today)))
        }
        ledger.spendingParts = [SpendingPart(id: galleryID(460450), name: "吃饭", amount: 120_000, categories: ["餐饮"]), SpendingPart(id: galleryID(460451), name: "出行", amount: 30_000, categories: ["交通", "旅行"])]
        ledger.partsMode = .amount
        if script == "v46-b3-budget-empty" { ledger.spendingParts = [] }
        if script == "v46-b3-share" {
            ledger.savingRule = .share(20)
            add(460460, title: "住房补贴", cents: 500_000, at: today, category: "工资奖金", nature: .income)
            ledger.entries[ledger.entries.count - 1].intoFixedSavings = true
        }
        if script == "v46-b3-reserve" {
            add(460461, title: "大衣", cents: 120_000, at: today, category: "购物")
            ledger.entries[ledger.entries.count - 1].fromReserve = true
        }
        if script == "v46-b3-hard" {
            ledger.accounts[0].name = galleryLatinTitle
            ledger.entries[0].purpose = galleryLatinTitle + galleryLongTitle
            ledger.entries[0].amount = 123_456_789
            ledger.wishlist[0].title = galleryLongTitle; ledger.wishlist[0].amount = 123_456_789
            ledger.wishlist[1].title = galleryLatinTitle; ledger.wishlist[1].amount = 987_654_321
            ledger.plans[0].title = galleryLongTitle; ledger.plans[0].amount = 123_456_789
            ledger.spendingParts[0].name = galleryLongTitle
            ledger.fixedSavings = 123_456_789
            ledger.memories[0].text = galleryLongTitle
        }
        ledger.butlerSavings = [ButlerSaving(id: "b3-wait", item: "降噪耳机", amount: 189_900, cadence: .once, date: today, undoable: false, waitedHours: 48), ButlerSaving(id: "b3-refund", item: "视频会员", amount: 2500, cadence: .once, date: Dates.addMonths(-2, to: today), undoable: false)]
        ledger.savingHistory = [CycleSaving(cycleStart: Dates.addMonths(-1, to: month), cycleEnd: Dates.addDays(-1, to: month), income: 800_000, target: 200_000, saved: 200_000, unspent: 0, leftoverChoice: .keep)]
        let before = Finance.funds(ledger, now: now).available
        ledger.accounts[0].anchorBalance += (script == "v46-b3-hard" ? 123_456_789 : 156_400) - before
        try ledger.validate(); return ledger
    }

    static func batch3Reply(_ request: ChatRequest, script: String) throws -> ChatMessage? {
        guard batch3Scripts.contains(script), request.purpose == "问余白", let user = request.messages.lastIndex(where: { $0.role == .user }) else { return nil }
        let question = request.messages[user].content ?? ""
        let turn = request.messages.suffix(from: user)
        if let last = turn.last, last.role == .tool, let content = last.content,
           let error = try JSONValue.parse(content)["error"] {
            throw YubaiError.invalid("合成问答工具失败：" + (error["message"]?.stringValue ?? content))
        }
        func has(_ id: String) -> Bool { turn.contains { $0.role == .tool && $0.toolCallID == id } }
        if question.contains("钱去哪了") {
            if has("b3-summary") { return ChatMessage(role: .assistant, content: "先看这几类。") }
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "b3-summary", name: "summarize", arguments: #"{"group_by":"category"}"#)])
        }
        if question.contains("记") {
            if has("b3-entries") { return ChatMessage(role: .assistant, content: "记这两笔？") }
            guard let profile = turn.last(where: { $0.role == .tool && $0.toolCallID == "b3-profile" }) else {
                return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "b3-profile", name: "get_profile")])
            }
            let facts = try JSONValue.parse(profile.content ?? "")
            guard let account = facts["entry_account_hint"]?.stringValue ?? facts["accounts"]?.arrayValue?.first?["id"]?.stringValue,
                  let parsed = facts["parsed_entries"]?.arrayValue, parsed.count >= 2 else { throw YubaiError.invalid("合成补记缺少本机金额。") }
            let rows: [JSONValue] = try parsed.prefix(2).enumerated().map { index, row in
                guard let amount = row["amount"]?["text"]?.stringValue else { throw YubaiError.invalid("合成补记缺少本机金额。") }
                return .object(["title": .string(index == 0 ? "打车" : "和同事吃饭"), "amount": .string(amount), "date": .string(Dates.text(Dates.addDays(-1, to: Dates.now))), "account": .string(account), "nature": .string("expense"), "category": .string(index == 0 ? "交通" : "餐饮")])
            }
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "b3-entries", name: "propose_entry", arguments: try JSONValue.object(["reason": .string("记这两笔？"), "entries": .array(rows)]).jsonText())])
        }
        if has("b3-verdict") { return ChatMessage(role: .assistant, content: "这个月的钱不够，存着的钱够。") }
        if !has("b3-judge") {
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "b3-judge", name: "judge_purchase", arguments: #"{"title":"降噪耳机","amount":"1899","category":"购物"}"#)])
        }
        return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "b3-verdict", name: "submit_verdict", arguments: #"{"verdict":"wait","reason":"降噪耳机，等等再说。","need":"want"}"#)])
    }
}
#endif
