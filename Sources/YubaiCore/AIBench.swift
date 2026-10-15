import Foundation

/// Synthetic / desensitized bench fixtures for phase-1 AI tasks.
public struct AIBenchFixture: Codable, Equatable, Sendable {
    public var categorize: [CategorizeCase]
    public var purchase: [PurchaseCase]
    public var insight: [InsightCase]
    public var search: [SearchCase]

    public struct CategorizeCase: Codable, Equatable, Sendable {
        public var id: String
        public var purpose: String
        public var direction: String
        public var expectedCategory: String
    }

    public struct PurchaseCase: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var purpose: String
        public var values: String
        public var assessmentTitle: String
        /// Substrings that must appear; response must not contain bare currency amounts like ¥12.00 rewriting.
        public var mustContain: [String]
        public var mustNotMatchAmountPattern: Bool
    }

    public struct InsightCase: Codable, Equatable, Sendable {
        public var id: String
        public var factLines: [String]
        public var protectedAmountTexts: [String]
        public var valuesHint: String
    }

    public struct SearchCase: Codable, Equatable, Sendable {
        public var id: String
        public var query: String
        public var corpus: [CorpusEntry]
        public var expectedTitleSubstrings: [String]
    }

    public struct CorpusEntry: Codable, Equatable, Sendable {
        public var title: String
        public var note: String
        public var category: String
    }
}

public struct AIBenchScore: Equatable, Sendable {
    public var backend: String
    public var categorizePass: Int
    public var categorizeTotal: Int
    public var purchasePass: Int
    public var purchaseTotal: Int
    public var insightPass: Int
    public var insightTotal: Int
    public var searchPass: Int
    public var searchTotal: Int

    public var totalPass: Int { categorizePass + purchasePass + insightPass + searchPass }
    public var totalCases: Int { categorizeTotal + purchaseTotal + insightTotal + searchTotal }
    public var passRate: Double { totalCases == 0 ? 0 : Double(totalPass) / Double(totalCases) }

    public var summary: String {
        String(
            format: "[%@] 通过 %d/%d（%.0f%%）· 归类 %d/%d · 购买 %d/%d · 洞察 %d/%d · 搜索 %d/%d",
            backend, totalPass, totalCases, passRate * 100,
            categorizePass, categorizeTotal,
            purchasePass, purchaseTotal,
            insightPass, insightTotal,
            searchPass, searchTotal
        )
    }
}

public enum AIBenchRunner {
    public static func loadFixture(from url: URL) throws -> AIBenchFixture {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AIBenchFixture.self, from: data)
    }

    public static func loadBundledFixture(named name: String = "ai-bench-samples", bundle: Bundle = .module) throws -> AIBenchFixture {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw YubaiError.invalid("找不到评测夹具 \(name).json")
        }
        return try loadFixture(from: url)
    }

    public static func run(fixture: AIBenchFixture, backend: any IntelligenceBackend) async -> AIBenchScore {
        let allowedNames = Category.defaults.map(\.name)

        var catPass = 0
        for sample in fixture.categorize {
            let batch = [CategorizeItem(index: 0, purpose: sample.purpose, direction: sample.direction)]
            do {
                let suggestions = try await backend.categorize(batch: batch, allowedCategories: allowedNames)
                if suggestions.first?.category == sample.expectedCategory { catPass += 1 }
            } catch {
                // count as fail
            }
        }

        var purchasePass = 0
        for sample in fixture.purchase {
            do {
                let text = try await backend.reflectPurchase(
                    title: sample.title,
                    purpose: sample.purpose,
                    values: sample.values,
                    assessmentTitle: sample.assessmentTitle
                )
                let okContains = sample.mustContain.allSatisfy { text.localizedCaseInsensitiveContains($0) }
                let amountOk: Bool = {
                    guard sample.mustNotMatchAmountPattern else { return true }
                    // Reject newly invented ¥ amounts (program owns numbers).
                    return text.range(of: #"¥\s*\d"#, options: .regularExpression) == nil
                        && text.range(of: #"\d+\.\d{2}\s*元"#, options: .regularExpression) == nil
                }()
                if okContains && amountOk { purchasePass += 1 }
            } catch {}
        }

        var insightPass = 0
        for sample in fixture.insight {
            do {
                let text = try await backend.narrateInsights(
                    InsightFactPack(
                        factLines: sample.factLines,
                        protectedAmountTexts: sample.protectedAmountTexts,
                        valuesHint: sample.valuesHint
                    )
                )
                if InsightNarrationGuard.accept(text, protecting: sample.protectedAmountTexts) != nil {
                    insightPass += 1
                }
            } catch {}
        }

        var searchPass = 0
        for sample in fixture.search {
            do {
                let expanded = try await backend.expandSearchQuery(sample.query)
                let corpus: [(id: UUID, title: String, note: String, category: String)] = sample.corpus.map {
                    (UUID(), $0.title, $0.note, $0.category)
                }
                let ids = SemanticSearchSupport.matchEntries(
                    query: sample.query,
                    expandedTerms: expanded,
                    entries: corpus
                )
                let matchedTitles = corpus.filter { ids.contains($0.id) }.map(\.title)
                let ok = sample.expectedTitleSubstrings.allSatisfy { expected in
                    matchedTitles.contains { $0.localizedCaseInsensitiveContains(expected) }
                }
                if ok { searchPass += 1 }
            } catch {}
        }

        return AIBenchScore(
            backend: String(describing: type(of: backend)) + "/\(backend.kind.rawValue)",
            categorizePass: catPass,
            categorizeTotal: fixture.categorize.count,
            purchasePass: purchasePass,
            purchaseTotal: fixture.purchase.count,
            insightPass: insightPass,
            insightTotal: fixture.insight.count,
            searchPass: searchPass,
            searchTotal: fixture.search.count
        )
    }
}
