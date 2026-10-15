import Foundation

/// Deterministic rules / templates. Always available; never invents amounts.
public struct RulesOnlyBackend: IntelligenceBackend {
    public let kind: IntelligenceBackendKind = .rulesOnly
    public let capabilities = IntelligenceCapabilities(
        categorize: true, reflectPurchase: false, narrateInsights: true, expandSearch: true
    )
    public init() {}

    public func categorize(batch: [CategorizeItem], allowedCategories: [String]) async throws -> [CategorySuggestion] {
        let allowed = Set(allowedCategories)
        return batch.compactMap { item in
            let inflow = item.direction.contains("收入")
            let result = Classifier.classify(title: item.purpose, inflow: inflow)
            let category = allowed.contains(result.category) ? result.category : (inflow ? "其他收入" : "其他支出")
            guard allowed.contains(category) else { return nil }
            return CategorySuggestion(index: item.index, category: category)
        }
    }

    public func reflectPurchase(title: String, purpose: String, values: String, assessmentTitle: String) async throws -> String {
        throw YubaiError.invalid("规则路径不提供购买价值生成文案；请查看固定反思问题。")
    }

    public func narrateInsights(facts: InsightFactPack) async throws -> String {
        facts.factLines.joined(separator: " ")
    }

    public func expandSearchQuery(_ query: String) async throws -> [String] {
        []
    }
}

/// Placeholder for llama.cpp + GGUF. Production inference is not wired in this skeleton.
public struct LocalDownloadedBackend: IntelligenceBackend {
    public let kind: IntelligenceBackendKind = .localDownloaded
    public var capabilities: IntelligenceCapabilities {
        ready ? .full : .none
    }
    public var ready: Bool
    /// Optional inject for tests / mock local path without linking llama.cpp.
    public var delegate: (any IntelligenceBackend)?

    public init(ready: Bool, delegate: (any IntelligenceBackend)? = nil) {
        self.ready = ready
        self.delegate = delegate
    }

    public func categorize(batch: [CategorizeItem], allowedCategories: [String]) async throws -> [CategorySuggestion] {
        guard ready else { throw YubaiError.invalid("本机模型尚未就绪。") }
        if let delegate { return try await delegate.categorize(batch: batch, allowedCategories: allowedCategories) }
        throw YubaiError.invalid("本机 GGUF 推理尚未接入（骨架占位）。请使用 mock 台架或规则路径。")
    }

    public func reflectPurchase(title: String, purpose: String, values: String, assessmentTitle: String) async throws -> String {
        guard ready else { throw YubaiError.invalid("本机模型尚未就绪。") }
        if let delegate { return try await delegate.reflectPurchase(title: title, purpose: purpose, values: values, assessmentTitle: assessmentTitle) }
        throw YubaiError.invalid("本机 GGUF 推理尚未接入（骨架占位）。")
    }

    public func narrateInsights(facts: InsightFactPack) async throws -> String {
        guard ready else { throw YubaiError.invalid("本机模型尚未就绪。") }
        if let delegate { return try await delegate.narrateInsights(facts: facts) }
        throw YubaiError.invalid("本机 GGUF 推理尚未接入（骨架占位）。")
    }

    public func expandSearchQuery(_ query: String) async throws -> [String] {
        guard ready else { throw YubaiError.invalid("本机模型尚未就绪。") }
        if let delegate { return try await delegate.expandSearchQuery(query) }
        throw YubaiError.invalid("本机 GGUF 推理尚未接入（骨架占位）。")
    }
}

/// Optional cloud path. Default off; endpoint is placeholder until ticket 01 converges.
public struct CloudOptionalBackend: IntelligenceBackend {
    public let kind: IntelligenceBackendKind = .cloudOptional
    public var enabled: Bool
    public var endpoint: URL?
    public var delegate: (any IntelligenceBackend)?

    public var capabilities: IntelligenceCapabilities {
        enabled ? .full : .none
    }

    public init(enabled: Bool, endpoint: URL? = nil, delegate: (any IntelligenceBackend)? = nil) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.delegate = delegate
    }

    public func categorize(batch: [CategorizeItem], allowedCategories: [String]) async throws -> [CategorySuggestion] {
        try ensureEnabled()
        if let delegate { return try await delegate.categorize(batch: batch, allowedCategories: allowedCategories) }
        throw YubaiError.invalid("云端后端尚未配置真实服务（接口预留）。")
    }

    public func reflectPurchase(title: String, purpose: String, values: String, assessmentTitle: String) async throws -> String {
        try ensureEnabled()
        if let delegate { return try await delegate.reflectPurchase(title: title, purpose: purpose, values: values, assessmentTitle: assessmentTitle) }
        throw YubaiError.invalid("云端后端尚未配置真实服务（接口预留）。")
    }

    public func narrateInsights(facts: InsightFactPack) async throws -> String {
        try ensureEnabled()
        if let delegate { return try await delegate.narrateInsights(facts: facts) }
        throw YubaiError.invalid("云端后端尚未配置真实服务（接口预留）。")
    }

    public func expandSearchQuery(_ query: String) async throws -> [String] {
        try ensureEnabled()
        if let delegate { return try await delegate.expandSearchQuery(query) }
        throw YubaiError.invalid("云端后端尚未配置真实服务（接口预留）。")
    }

    private func ensureEnabled() throws {
        guard enabled else { throw YubaiError.invalid("云端增强未开启。") }
    }
}

/// Heuristic mock used by AI bench and Settings “实验” path. Not production quality.
public struct MockLocalBackend: IntelligenceBackend {
    public let kind: IntelligenceBackendKind = .localDownloaded
    public let capabilities = IntelligenceCapabilities.full
    public init() {}

    public func categorize(batch: [CategorizeItem], allowedCategories: [String]) async throws -> [CategorySuggestion] {
        let allowed = Set(allowedCategories)
        return batch.compactMap { item in
            let inflow = item.direction.contains("收入")
            let guessed = Self.guessCategory(purpose: item.purpose, inflow: inflow)
            let category = allowed.contains(guessed) ? guessed : (inflow ? "其他收入" : "其他支出")
            guard allowed.contains(category) else { return nil }
            return CategorySuggestion(index: item.index, category: category)
        }
    }

    public func reflectPurchase(title: String, purpose: String, values: String, assessmentTitle: String) async throws -> String {
        let focus = purpose.isEmpty ? title : purpose
        return "从使用价值看，可以先确认「\(String(focus.prefix(40)))」是否有更便宜或已有的替代，并对照你重视的事（\(String(values.prefix(40)))）。资金结论以程序判断「\(assessmentTitle)」为准，本建议不构成决定。"
    }

    public func narrateInsights(facts: InsightFactPack) async throws -> String {
        let base = facts.factLines.joined(separator: " ")
        let polish = "可以对照自己最近的重心，看这些线索是否仍符合预期。"
        return base.isEmpty ? polish : base + " " + polish
    }

    public func expandSearchQuery(_ query: String) async throws -> [String] {
        Self.expand(query)
    }

    public static func guessCategory(purpose: String, inflow: Bool) -> String {
        let text = purpose.lowercased()
        if inflow {
            if text.contains("工资") || text.contains("薪") { return "工资奖金" }
            if text.contains("稿") || text.contains("兼职") { return "兼职劳务" }
            return "其他收入"
        }
        let map: [(String, [String])] = [
            ("餐饮", ["咖啡", "奶茶", "外卖", "午饭", "晚餐", "餐厅", "食堂", "瑞幸", "星巴克", "肯德基"]),
            ("交通", ["地铁", "公交", "滴滴", "打车", "高铁", "停车", "加油"]),
            ("居住", ["房租", "物业", "电费", "水费", "燃气", "宽带"]),
            ("日用购物", ["超市", "淘宝", "京东", "拼多多", "日用品", "纸巾"]),
            ("娱乐旅行", ["电影", "游戏", "酒店", "机票", "演唱会"]),
            ("学习工作", ["课程", "教材", "书店", "会员开发", "github"]),
            ("医疗健康", ["医院", "药", "体检", "牙科"]),
            ("人情家庭", ["礼物", "红包人情", "家用"])
        ]
        for (category, words) in map {
            if words.contains(where: { text.contains($0.lowercased()) }) { return category }
        }
        return "其他支出"
    }

    public static func expand(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var extra: [String] = []
        let synonyms: [(String, [String])] = [
            ("咖啡", ["星巴克", "瑞幸", "咖啡店"]),
            ("外卖", ["美团外卖", "饿了么", "外卖订单"]),
            ("地铁", ["轨道交通", "一卡通", "乘车"]),
            ("房租", ["租金", "房东"]),
            ("超市", ["盒马", "永辉", "生鲜"]),
            ("打车", ["滴滴", "网约车"]),
            ("电影", ["影城", "电影院"])
        ]
        for (key, words) in synonyms {
            if q.localizedCaseInsensitiveContains(key) || words.contains(where: { q.localizedCaseInsensitiveContains($0) }) {
                extra.append(key)
                extra.append(contentsOf: words)
            }
        }
        return Array(Set(extra.filter { !$0.isEmpty && $0.caseInsensitiveCompare(q) != .orderedSame })).sorted()
    }
}

/// Cloud mock: slightly different expansions; still never mutates amounts.
public struct MockCloudBackend: IntelligenceBackend {
    public let kind: IntelligenceBackendKind = .cloudOptional
    public let capabilities = IntelligenceCapabilities.full
    private let local = MockLocalBackend()
    public init() {}

    public func categorize(batch: [CategorizeItem], allowedCategories: [String]) async throws -> [CategorySuggestion] {
        try await local.categorize(batch: batch, allowedCategories: allowedCategories)
    }

    public func reflectPurchase(title: String, purpose: String, values: String, assessmentTitle: String) async throws -> String {
        let text = try await local.reflectPurchase(title: title, purpose: purpose, values: values, assessmentTitle: assessmentTitle)
        return text + "（云端 mock，未外发真实账单。）"
    }

    public func narrateInsights(facts: InsightFactPack) async throws -> String {
        try await local.narrateInsights(facts: facts)
    }

    public func expandSearchQuery(_ query: String) async throws -> [String] {
        var terms = try await local.expandSearchQuery(query)
        if query.localizedCaseInsensitiveContains("咖啡") { terms.append("拿铁") }
        return Array(Set(terms)).sorted()
    }
}
