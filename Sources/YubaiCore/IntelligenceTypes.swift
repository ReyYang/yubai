import Foundation

/// Backend kinds selectable by preferences + weight state.
public enum IntelligenceBackendKind: String, Codable, Sendable, CaseIterable {
    case rulesOnly
    case localDownloaded
    case cloudOptional
    case appleFMOptional
}

/// One categorization suggestion. Amount / nature / account must never be changed by backends.
public struct CategorySuggestion: Equatable, Sendable {
    public var index: Int
    public var category: String
    public init(index: Int, category: String) {
        self.index = index
        self.category = category
    }
}

public struct CategorizeItem: Equatable, Sendable {
    public var index: Int
    public var purpose: String
    public var direction: String
    public init(index: Int, purpose: String, direction: String) {
        self.index = index
        self.purpose = purpose
        self.direction = direction
    }
}

public struct InsightFactPack: Equatable, Sendable {
    /// Pre-formatted fact sentences from local Finance.review / templates. Models may polish only.
    public var factLines: [String]
    /// Amount strings that must appear unchanged if the model invents numbers.
    public var protectedAmountTexts: [String]
    public var valuesHint: String
    public init(factLines: [String], protectedAmountTexts: [String] = [], valuesHint: String = "") {
        self.factLines = factLines
        self.protectedAmountTexts = protectedAmountTexts
        self.valuesHint = valuesHint
    }
}

public struct IntelligenceCapabilities: Equatable, Sendable {
    public var categorize: Bool
    public var reflectPurchase: Bool
    public var narrateInsights: Bool
    public var expandSearch: Bool
    public init(categorize: Bool, reflectPurchase: Bool, narrateInsights: Bool, expandSearch: Bool) {
        self.categorize = categorize
        self.reflectPurchase = reflectPurchase
        self.narrateInsights = narrateInsights
        self.expandSearch = expandSearch
    }
    public static let none = IntelligenceCapabilities(categorize: false, reflectPurchase: false, narrateInsights: false, expandSearch: false)
    public static let full = IntelligenceCapabilities(categorize: true, reflectPurchase: true, narrateInsights: true, expandSearch: true)
}

/// Shared task interface for rules / local GGUF / optional cloud / optional Apple FM.
public protocol IntelligenceBackend: Sendable {
    var kind: IntelligenceBackendKind { get }
    var capabilities: IntelligenceCapabilities { get }
    func categorize(batch: [CategorizeItem], allowedCategories: [String]) async throws -> [CategorySuggestion]
    func reflectPurchase(title: String, purpose: String, values: String, assessmentTitle: String) async throws -> String
    func narrateInsights(facts: InsightFactPack) async throws -> String
    func expandSearchQuery(_ query: String) async throws -> [String]
}

/// On-device GGUF completion (implemented by `YubaiLocalLLM` / llama.cpp). Core stays free of the XCFramework link.
public protocol LocalGGUFInference: Sendable {
    func complete(system: String, user: String, temperature: Float, maxTokens: Int) async throws -> String
}

/// Resolves which backend to use.
/// Interim reliability order: **healthy local only when explicitly enabled** → optional cloud → optional Apple FM → rules.
/// Unhealthy / disabled local never blocks cloud when cloud is on (Working AI > local-first purity).
public struct IntelligenceRouting: Equatable, Sendable {
    public var kind: IntelligenceBackendKind
    public var reason: String
    public init(kind: IntelligenceBackendKind, reason: String) {
        self.kind = kind
        self.reason = reason
    }

    public static func resolve(
        preferences: Preferences,
        localWeightReady: Bool,
        appleFMAvailable: Bool,
        localInferenceHealthy: Bool = true
    ) -> IntelligenceRouting {
        guard preferences.localAIEnabled else {
            return IntelligenceRouting(kind: .rulesOnly, reason: "智能辅助已关闭；使用规则与模板。")
        }
        // Local only when user opted in, weights verified, and runtime gate says safe.
        if preferences.downloadedModelEnabled, localWeightReady, localInferenceHealthy {
            return IntelligenceRouting(kind: .localDownloaded, reason: "本机模型已就绪且运行门控通过。")
        }
        if preferences.cloudAIEnabled {
            if preferences.downloadedModelEnabled, localWeightReady, !localInferenceHealthy {
                return IntelligenceRouting(kind: .cloudOptional, reason: "本机模型不安全可用；改走云端增强。")
            }
            if preferences.downloadedModelEnabled, !localWeightReady {
                return IntelligenceRouting(kind: .cloudOptional, reason: "本机模型未就绪；改走云端增强。")
            }
            return IntelligenceRouting(kind: .cloudOptional, reason: "云端增强已开启。")
        }
        if preferences.appleSystemModelEnabled, appleFMAvailable {
            return IntelligenceRouting(kind: .appleFMOptional, reason: "系统 Apple 模型可用且用户已允许（非主路径）。")
        }
        if preferences.downloadedModelEnabled, localWeightReady, !localInferenceHealthy {
            return IntelligenceRouting(kind: .rulesOnly, reason: "本机模型不可靠；已降级为规则 / 模板（可开启云端增强）。")
        }
        if preferences.downloadedModelEnabled, !localWeightReady {
            return IntelligenceRouting(kind: .rulesOnly, reason: "未启用可用模型；降级为规则 / 模板 / 子串搜索。")
        }
        return IntelligenceRouting(kind: .rulesOnly, reason: "无可用增强后端；使用规则 / 模板。")
    }
}

/// Strip or reject model output that invents amounts. UI must prefer template numbers.
public enum InsightNarrationGuard {
    /// Returns polished text only if every protected amount still appears (when non-empty protection list).
    /// Otherwise returns nil so caller falls back to templates.
    public static func accept(_ text: String, protecting amounts: [String]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for amount in amounts where !amount.isEmpty {
            if !trimmed.contains(amount) { return nil }
        }
        return trimmed
    }
}

/// Substring search union after query expansion. Never touches amounts.
public enum SemanticSearchSupport {
    public static func matchEntries(
        query: String,
        expandedTerms: [String],
        entries: [(id: UUID, title: String, note: String, category: String)]
    ) -> [UUID] {
        let terms = ([query] + expandedTerms)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for entry in entries {
            let hay = entry.title + " " + entry.note + " " + entry.category
            if terms.contains(where: { hay.localizedCaseInsensitiveContains($0) }) {
                if seen.insert(entry.id).inserted { ordered.append(entry.id) }
            }
        }
        return ordered
    }
}
