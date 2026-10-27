#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

/// No fixture path or scripted response is available in device / Release builds.
/// A UUID-isolated test ledger AND an explicit script flag are both required.
enum UITestSupport {
    static var keepsUndoReceipt: Bool {
        script != nil && ProcessInfo.processInfo.environment["YUBAI_UI_TEST_KEEP_UNDO"] == "1"
    }
    static let screenshotScripts: Set<String> = [
        "judge-ask", "judge-wait", "judge-buy", "judge-skip", "wishlist-cool",
        "letter-saving", "profile-revisit", "subcategory"
    ]
    /// Scripted replies alone do not imply that a key is configured.
    /// UI tests can explicitly simulate either state without changing Keychain.
    static var configuredKeyOverride: Bool? {
        guard script != nil else { return nil }
        switch ProcessInfo.processInfo.environment["YUBAI_UI_TEST_CONFIGURED_KEY"] {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }
    static var script: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--test-ledger"), args.indices.contains(i + 1),
              UUID(uuidString: args[i + 1]) != nil,
              let name = ProcessInfo.processInfo.environment["YUBAI_UI_TEST_SCRIPT"],
              (screenshotScripts.contains(name) || ["empty", "import", "restrain", "ask", "profile", "memory", "manual", "entries", "bills", "bills-overdue", "bills-auto", "bills-estimated", "bills-clarity", "bills-multiple", "wish-bought", "overview-xl"].contains(name)) else { return nil }
        return name
    }
    static var statementURL: URL? {
        guard script == "import", let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--test-ledger") else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YubaiUITests/" + ProcessInfo.processInfo.arguments[i + 1])
            .appendingPathComponent("合成账单.csv")
    }
    static func prepare(_ repository: LedgerRepository) throws {
        guard let script else { return }
        if let url = statementURL, let encoded = ProcessInfo.processInfo.environment["YUBAI_UI_STATEMENT"],
           let data = Data(base64Encoded: encoded), data.count < 1_000_000 {
            try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        guard !FileManager.default.fileExists(atPath: repository.file.path), script != "empty" else { return }
        let now = Date()
        if screenshotScripts.contains(script) {
            try repository.save(screenshotLedger(script, now: now), reason: "合成截图夹具")
            return
        }
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true; ledger.preferences.cloudAIEnabled = script != "manual" && script != "entries" && !script.hasPrefix("bills")
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.mutedTopics = ["letter"] // Keep scripted flows independent of the weekday.
        let account = Account(name: "合成银行卡", balance: 100_000, at: now)
        ledger.accounts = [account]
        if script == "overview-xl" {
            ledger.entries = [Entry(date: now, amount: 3200, accountID: account.id, title: "合成测试的午饭和日用品以及下周旅行准备", category: "日用")]
        } else if script == "ask" || script == "restrain" {
            ledger.entries = [Entry(date: now, amount: 3200, accountID: account.id, title: "合成咖啡", category: "餐饮")]
        } else if script == "import" {
            ledger.entries = [Entry(date: now.addingTimeInterval(-60), amount: 1600, accountID: account.id, title: "原有午饭", category: "餐饮")]
        } else if script == "entries" {
            ledger.entries = (0..<50).map { Entry(date: now.addingTimeInterval(Double(-$0 * 60)), amount: 3200, accountID: account.id, title: "合成账目 \($0)", category: "餐饮") }
        }
        if script == "restrain" {
            ledger.profile.restrain = [ProfileArea(title: "咖啡", match: AreaMatch(keywords: ["咖啡"]), softLimit: SoftLimit(perMonthAmount: 3000))]
        }
        if script == "wish-bought" {
            let entry = Entry(date: now, amount: 3200, accountID: account.id, title: "合成水壶", category: "日用")
            ledger.entries = [entry]
            var wish = WishItem(title: "合成水壶", amount: entry.amount)
            wish.status = .bought; wish.boughtEntryID = entry.id; wish.followUpAt = Dates.addMonths(1, to: now)
            ledger.wishlist = [wish]
        }
        if script.hasPrefix("bills") {
            var rent = Plan(title: "房租", amount: 30_000, dueDate: Dates.day(now))
            rent.accountID = account.id
            var salary = Plan(title: "工资", amount: 50_000, dueDate: Dates.day(now), frequency: .monthly, inflow: true, category: "工资", nature: .income)
            salary.accountID = account.id; ledger.plans = [rent, salary]
            if script == "bills-overdue" {
                var old = Plan(title: "上月账单", amount: 1000, dueDate: Dates.addMonths(-1, to: Dates.day(now)))
                old.accountID = account.id
                var phone = Plan(title: "话费", amount: 6800, dueDate: Dates.day(now))
                phone.accountID = account.id; ledger.plans += [old, phone]
            }
            if script == "bills-auto" {
                ledger.plans[0].autoPay = true; ledger.plans[0].autoPaySince = Dates.day(now)
                ledger.plans[1].dueDate = Dates.addDays(1, to: Dates.day(now))
            }
            if script == "bills-estimated" {
                var power = Plan(title: "电费", amount: 12_000, dueDate: Dates.day(now))
                power.accountID = account.id; power.estimated = true; ledger.plans = [power]
            }
            if script == "bills-clarity" {
                let month = Dates.calendar.dateInterval(of: .month, for: now)!
                ledger.plans[0].dueDate = month.start
                ledger.plans[1].dueDate = max(month.start, Dates.addDays(-6, to: Dates.day(now)))
                var phone = Plan(title: "话费", amount: 5800, dueDate: Dates.day(month.end.addingTimeInterval(-1)))
                phone.accountID = account.id
                var video = Plan(title: "视频会员", amount: 2500, dueDate: month.start)
                video.accountID = account.id; video.autoPay = true
                ledger.plans += [phone, video]
                var entry = Entry(date: now, amount: video.amount, accountID: account.id, title: video.title)
                entry.planID = video.id; entry.occurrence = video.dueDate; entry.source = "自动扣款"; entry.recordedAt = now
                ledger.entries = [entry]
            }
            if script == "bills-multiple" {
                var plan = Plan(title: "每周订阅", amount: 1000, dueDate: Dates.addDays(-35, to: Dates.day(now)), frequency: .weekly)
                plan.accountID = account.id; plan.installments = 7; ledger.plans = [plan]
            }
        }
        try repository.save(ledger, reason: "合成测试夹具")
    }
    /// Fresh, synthetic data only. Dates follow the simulator clock.
    static func screenshotLedger(_ script: String, now: Date) throws -> Ledger {
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true
        ledger.preferences.cloudAIEnabled = script.hasPrefix("judge-") || script == "profile-revisit"
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.lastSubcategoryBatchDay = Dates.text(now)
        let account = Account(name: "合成银行卡", balance: script == "judge-skip" ? 302_900 : 1_217_900, at: now)
        ledger.accounts = [account]
        switch script {
        case "judge-ask", "judge-wait", "judge-buy":
            ledger.profile.generous = [ProfileArea(title: "运动装备", match: AreaMatch(subcategories: ["购物/运动户外"]), note: "运动装备愿意多花", confirmedAt: now)]
            ledger.memories = [MemoryNote(text: "打算开始徒步，还没去过几次，现在的跑鞋可以先走几次", kind: .plan, source: .chat, createdAt: Dates.addDays(-7, to: now))]
            if script == "judge-buy" {
                ledger.memories = [MemoryNote(text: "想长期徒步，旧跑鞋你也说磨脚了", kind: .plan, source: .chat, createdAt: Dates.addMonths(-1, to: now))]
            }
        case "judge-skip":
            // ¥3,029 less ¥1,750 rent leaves ¥1,279 against a ¥1,899 purchase.
            let month = Dates.calendar.dateInterval(of: .month, for: now)!
            var rent = Plan(title: "房租", amount: 175_000, dueDate: month.end, category: "居住")
            rent.accountID = account.id; ledger.plans = [rent]
        case "wishlist-cool":
            ledger.wishlist = cooldownWishes(now: now)
            let purchaseDate = Dates.addDays(-31, to: now)
            let entry = Entry(date: purchaseDate, amount: 59_900, accountID: account.id, title: "合成机械键盘", category: "购物")
            ledger.entries = [entry]
            var bought = WishItem(title: entry.title, amount: entry.amount, purpose: "每天写东西用")
            bought.createdAt = Dates.addDays(-35, to: now); bought.status = .bought
            bought.boughtEntryID = entry.id; bought.followUpAt = Dates.addDays(30, to: purchaseDate)
            ledger.wishlist.append(bought)
        case "letter-saving":
            // Keep letter unmuted, and create the first letter of this month via Core.
            let weekStart = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: now)!.start
            ledger.wishlist = [droppedWish(title: "合成投影仪", amount: 129_900, at: now.addingTimeInterval(-1)),
                               droppedWish(title: "合成咖啡机", amount: 248_000, at: weekStart.addingTimeInterval(-60))]
            ledger.plans = [("视频会员", Int64(2500)), ("网盘", 1200), ("健身 App", 3000)].enumerated().map { index, item in
                let (title, amount) = item
                let month = Dates.calendar.dateInterval(of: .month, for: now)!.start
                let dueDate = Dates.addDays([3, 12, 24][index] - 1, to: month)
                var plan = Plan(title: title, amount: amount, dueDate: dueDate, frequency: .monthly, category: "娱乐旅行")
                plan.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
                plan.accountID = account.id
                return plan
            }
            if let candidate = WeeklyLetter.candidate(ledger, now: now) { ledger.cards = [candidate.card(now: now)] }
        case "profile-revisit":
            ledger.profile.restrain = [
                ProfileArea(title: "外卖", match: AreaMatch(subcategories: ["餐饮/外卖"]), note: "外卖每周最多 3 次", softLimit: SoftLimit(perWeekCount: 3), confirmedAt: now),
                ProfileArea(title: "数码电器", match: AreaMatch(subcategories: ["购物/数码电器"]), note: "数码电器每月 800", softLimit: SoftLimit(perMonthAmount: 80_000), confirmedAt: now)
            ]
            ledger.profile.generous = ["书", "运动装备", "朋友吃饭"].map { ProfileArea(title: $0, confirmedAt: now) }
            ledger.profile.principles = ["日常用得上才买", "先试再买"]
            ledger.memories = [MemoryNote(text: "合成：最近经常加班", kind: .life, source: .chat, createdAt: Dates.addDays(-5, to: now)),
                               MemoryNote(text: "合成：打算长期徒步", kind: .plan, source: .chat, createdAt: Dates.addDays(-10, to: now)),
                               MemoryNote(text: "合成：喜欢和朋友一起吃饭", kind: .value, source: .chat, createdAt: Dates.addDays(-15, to: now))]
            ledger.entries = (0..<3).map { index in
                classifiedEntry(title: "合成外卖 \(index + 1)", amount: 3200, category: "餐饮", subcategory: "外卖", accountID: account.id, date: now)
            }
            ledger.entries.append(classifiedEntry(title: "合成数码配件", amount: 42_000, category: "购物", subcategory: "数码电器", accountID: account.id, date: now))
        case "subcategory":
            ledger.entries = [
                classifiedEntry(title: "徒步鞋 · 京东", amount: 89_900, category: "购物", subcategory: "运动户外", accountID: account.id, date: now.addingTimeInterval(-1)),
                classifiedEntry(title: "合成充电器", amount: 12_900, category: "购物", subcategory: "数码电器", accountID: account.id, date: now.addingTimeInterval(-60)),
                classifiedEntry(title: "合成收纳盒", amount: 5900, category: "购物", subcategory: "家居家电", accountID: account.id, date: now.addingTimeInterval(-120)),
                Entry(date: now.addingTimeInterval(-180), amount: 19_900, accountID: account.id, title: "合成购物", category: "购物"),
                Entry(date: now.addingTimeInterval(-240), amount: 8900, accountID: account.id, title: "合成日用品", category: "购物")
            ]
            // Existing wishlist purchase link reaches record details without changing navigation.
            if let shoes = ledger.entries.first {
                var wish = WishItem(title: shoes.title, amount: shoes.amount)
                wish.createdAt = shoes.date; wish.status = .bought; wish.boughtEntryID = shoes.id
                ledger.wishlist = [wish]
            }
        default: throw YubaiError.invalid("未知合成截图脚本。")
        }
        try ledger.validate()
        return ledger
    }
    private static func classifiedEntry(title: String, amount: Int64, category: String, subcategory: String, accountID: UUID, date: Date) -> Entry {
        var entry = Entry(date: date, amount: amount, accountID: accountID, title: title, category: category)
        entry.subcategory = subcategory; entry.subcategoryUserEdited = false
        return entry
    }
    private static func droppedWish(title: String, amount: Int64, at date: Date) -> WishItem {
        var wish = WishItem(title: title, amount: amount)
        wish.createdAt = Dates.addDays(-7, to: date); wish.status = .dropped; wish.droppedAt = date
        return wish
    }
    private static func cooldownWishes(now: Date) -> [WishItem] {
        var headphones = WishItem(title: "降噪耳机", amount: 189_900, purpose: "通勤地铁太吵")
        headphones.createdAt = Dates.addDays(-7, to: now); headphones.coolUntil = now.addingTimeInterval(-1)
        var shoes = WishItem(title: "徒步鞋", amount: 89_900)
        shoes.createdAt = Dates.addDays(-1, to: now); shoes.coolUntil = Dates.addDays(2, to: now)
        var coffee = WishItem(title: "咖啡机", amount: 248_000)
        coffee.createdAt = Dates.addDays(-12, to: now)
        return [headphones, shoes, coffee, droppedWish(title: "合成投影仪", amount: 129_900, at: now.addingTimeInterval(-1))]
    }

}

struct UITestTransport: ChatTransport {
    let script: String
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        if script.hasPrefix("judge-") { return try purchaseReply(request) }
        if script == "profile-revisit", request.purpose == "消费观对话" {
            let reply = profileReply(request)
            if reply.toolCalls == nil, request.messages.contains(where: { $0.role == .assistant && $0.toolCalls == nil }),
               let delay = Double(ProcessInfo.processInfo.environment["YUBAI_UI_PROFILE_REPLY_DELAY"] ?? ""), delay > 0 {
                try await Task.sleep(for: .seconds(min(delay, 5)))
            }
            return reply
        }
        if script == "memory" {
            if request.messages.last?.role == .tool { return ChatMessage(role: .assistant, content: "记下了这个计划。") }
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "remember-plan", name: "remember",
                arguments: #"{"text":"年底前想换电脑","kind":"plan"}"#)])
        }
        if request.purpose == "管家卡片与来信" || request.purpose == "导入短评" {
            return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) // Use the real local templates.
        }
        if script == "import", request.purpose == "导入整理" {
            let payload = try JSONValue.parse(request.messages.last?.content ?? "")
            let batch = payload["batch"]?.arrayValue ?? []
            guard let incoming = batch.first(where: { $0["inflow"] == .bool(true) }), let id = incoming["id"]?.stringValue else {
                throw YubaiError.invalid("合成导入夹具缺少来款。")
            }
            let rows: [JSONValue] = batch.compactMap { row in
                guard let key = row["id"]?.stringValue, key != id else { return nil }
                return .object(["entry": .string(key), "category": .string("餐饮"), "nature": .string("expense"), "confident": .bool(true)])
            }
            let question: JSONValue = .object(["text": .string("这笔来款是什么用途？"), "entry_ids": .array([.string(id)]), "options": .array([
                .object(["title": .string("日常收入"), "items": .array([
                    .object(["kind": .string("set_nature"), "entry": .string(id), "nature": .string("income")]),
                    .object(["kind": .string("set_category"), "entry": .string(id), "category": .string("其他收入")])])]),
                .object(["title": .string("先留没写用途"), "items": .array([
                    .object(["kind": .string("set_purpose"), "entry": .string(id), "text": .string("待核对来款")])])])])])
            let result = JSONValue.object(["rows": .array(rows), "items": .array([]), "series": .array([]), "questions": .array([question])])
            return ChatMessage(role: .assistant, content: try result.jsonText())
        }
        if script == "ask" {
            if request.messages.last?.role != .tool {
                return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "coffee-total", name: "summarize",
                    arguments: #"{"nature":"spending","keyword":"咖啡","group_by":"category"}"#)])
            }
            // The agent has executed the real read tool. Quote its amount, never a fabricated answer.
            let result = try JSONValue.parse(request.messages.last?.content ?? "")
            guard let amount = result["spending"]?["text"]?.stringValue else { throw YubaiError.invalid("合成问答缺少汇总。") }
            return ChatMessage(role: .assistant, content: "咖啡共花了 " + amount + "。")
        }
        throw YubaiError.invalid("这条 UI 测试没有配置此请求；不会访问网络。")
    }
    private func purchaseReply(_ request: ChatRequest) throws -> ChatMessage {
        // Route background wording through the existing local-template path.
        guard request.purpose != "管家卡片与来信" else { return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) }
        let lastUserIndex = request.messages.lastIndex { $0.role == .user } ?? request.messages.startIndex
        let turn = request.messages.suffix(from: lastUserIndex)
        let judged = turn.contains { $0.role == .tool && $0.toolCallID == "judge-purchase" }
        let submitted = turn.contains { $0.role == .tool && $0.toolCallID == "purchase-verdict" }
        if let last = turn.last, last.role == .tool, let content = last.content,
           let error = try JSONValue.parse(content)["error"] {
            throw YubaiError.invalid("合成购买工具失败：" + (error["message"]?.stringValue ?? content))
        }
        if submitted { return ChatMessage(role: .assistant, content: "已给出结论。") }
        if !judged {
            let skip: Bool = script == "judge-skip"
            var fields: [String: JSONValue] = ["title": .string(skip ? "降噪耳机" : "徒步鞋"),
                "amount": .string(skip ? "1899" : "899"), "category": .string("购物"),
                "subcategory": .string(skip ? "数码电器" : "运动户外")]
            if skip {
                let rentDate = Dates.calendar.dateInterval(of: .month, for: Date())!.end
                fields["date"] = .string(Dates.text(rentDate))
            }
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "judge-purchase", name: "judge_purchase", arguments: try JSONValue.object(fields).jsonText())])
        }
        let direct = request.messages.last { $0.role == .user }?.content?.contains("直接给结论") == true
        if script == "judge-ask", !direct, request.messages.filter({ $0.role == .user }).count == 1 {
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "purchase-questions", name: "ask_purchase_questions", arguments:
                #"{"questions":[{"text":"最近三个月徒步过几次？","options":["还没怎么去","一两次","每月都去"]},{"text":"现在的鞋里，有能先穿着走的吗？","options":["有双跑鞋","没有合适的"]},{"text":"先穿现有的走三次，还会觉得非换不可吗？","options":["会，旧鞋磨脚","说不好"]}]}"#)])
        }
        let verdict: String
        let reason: String
        switch script {
        case "judge-buy": verdict = "buy"; reason = "旧跑鞋你也说磨脚了。"
        case "judge-skip":
            verdict = "skip"
            let result = try JSONValue.parse(turn.last { $0.toolCallID == "judge-purchase" }?.content ?? "")
            let due = result["affordability"]?["upcoming_payments"]?.arrayValue?.first?["date"]?.stringValue.flatMap(Dates.parse)
            let month = due.map { Dates.calendar.component(.month, from: $0) } ?? 11
            reason = "买了以后到 \(month)月1日交房租前还差 620 元。"
        default: verdict = "wait"; reason = "你最近三个月还没去徒步，现在的跑鞋可以先走几次。"
        }
        let judgment = try JSONValue.parse(turn.last { $0.toolCallID == "judge-purchase" }?.content ?? "")
        let memories: JSONValue? = judgment["memories"]
        let ids: [String] = ["plan", "value", "life"].flatMap { kind in
            (memories?[kind]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
        }
        let args: JSONValue = .object(["verdict": .string(verdict), "reason": .string(reason),
            "need": .string(verdict == "buy" ? "need" : "want"), "memory_ids": .array(ids.map(JSONValue.string))])
        return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "purchase-verdict", name: "submit_verdict", arguments: try args.jsonText())])
    }
    private func profileReply(_ request: ChatRequest) -> ChatMessage {
        let lastUserIndex = request.messages.lastIndex { $0.role == .user } ?? request.messages.startIndex
        let turn = request.messages.suffix(from: lastUserIndex)
        if !turn.contains(where: { $0.role == .tool && $0.toolCallID == "revisit-profile" }) {
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "revisit-profile", name: "get_profile")])
        }
        if request.messages.contains(where: { $0.role == .assistant && $0.toolCalls == nil }) {
            return ChatMessage(role: .assistant, content: "外卖这周已经 3 次了，加班的日子想怎么安排？")
        }
        return ChatMessage(role: .assistant, content: "你现在写着想克制外卖和数码，愿意在书、运动装备和朋友吃饭上多花。想改哪里？")
    }

}
#endif
