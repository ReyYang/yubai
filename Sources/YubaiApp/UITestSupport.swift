#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

/// No fixture path or scripted response is available in device / Release builds.
/// A UUID-isolated test ledger AND an explicit script flag are both required.
enum UITestSupport {
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
              ["empty", "import", "restrain", "ask", "profile", "memory", "manual", "entries", "bills", "bills-overdue", "bills-auto", "bills-estimated", "wish-bought"].contains(name) else { return nil }
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
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true; ledger.preferences.cloudAIEnabled = script != "manual" && script != "entries" && !script.hasPrefix("bills")
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.mutedTopics = ["letter"] // Keep scripted flows independent of the weekday.
        let account = Account(name: "合成银行卡", balance: 100_000, at: now)
        ledger.accounts = [account]
        if script == "ask" || script == "restrain" {
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
        }
        try repository.save(ledger, reason: "合成测试夹具")
    }
}

struct UITestTransport: ChatTransport {
    let script: String
    func send(_ request: ChatRequest) async throws -> ChatMessage {
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
}
#endif
