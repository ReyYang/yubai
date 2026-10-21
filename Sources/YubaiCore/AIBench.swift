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

    /// Load a fixture from a caller-provided bundle (e.g. test target `Bundle.module` + Fixtures).
    public static func loadBundledFixture(named name: String = "ai-bench-samples", bundle: Bundle) throws -> AIBenchFixture {
        let url =
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        guard let url else {
            throw YubaiError.invalid("找不到评测夹具 \(name).json")
        }
        return try loadFixture(from: url)
    }

    public static func run(fixture: AIBenchFixture, backend: CloudBackend) async -> AIBenchScore {
        var catPass = 0
        for sample in fixture.categorize {
            var ledger = Ledger(); ledger.accounts = [Account(name: "评测账户")]
            let entry = Entry(date: Dates.parse("2026-10-01")!, amount: 1000,
                              nature: sample.direction == "收入" ? .income : .expense,
                              accountID: ledger.accounts[0].id, title: sample.purpose, category: "待整理")
            ledger.entries = [entry]
            do {
                let result = try await ImportOrganizer(transport: backend).organize(ledger: ledger, entryIDs: [entry.id])
                if !result.changeSet.items.isEmpty { try result.changeSet.apply(to: &ledger) }
                if ledger.entries[0].category == sample.expectedCategory { catPass += 1 }
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
                    return !ModelAmountGuard.containsInventedAmount(text)
                }()
                if okContains && amountOk { purchasePass += 1 }
            } catch {}
        }

        var insightPass = 0
        for sample in fixture.insight {
            do {
                let text = try await backend.narrateInsights(
                    facts: InsightFactPack(
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
            backend: backend.client.configuration.diagnosticsLabel,
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

/// Seed cases for the shared financial assistant; scripted calls support offline regression.
public struct AssistantEvalCase: Codable, Sendable {
    public struct ScriptedCall: Codable, Sendable {
        public var name: String
        public var args: JSONValue
    }
    public var id: String
    public var question: String
    public var expectedTools: [String]
    public var expectedNumbers: [String]
    public var scriptedCalls: [ScriptedCall]
    public var expectedChangeKinds: [String]?
    public var expectRefusal: Bool?
    private enum CodingKeys: String, CodingKey {
        case id, question
        case expectedTools = "expected_tools", expectedNumbers = "expected_numbers", scriptedCalls = "scripted_calls"
        case expectedChangeKinds = "expected_change_kinds", expectRefusal = "expect_refusal"
    }
}

public struct AssistantEvalResult: Sendable {
    public let id: String
    public let reply: AssistantReply
    public let passed: Bool
}

extension AIBenchRunner {
    public static func loadAssistantEval(bundle: Bundle) throws -> [AssistantEvalCase] {
        let url = bundle.url(forResource: "assistant-eval", withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "assistant-eval", withExtension: "json")
        guard let url else { throw YubaiError.invalid("找不到assistant-eval.json。") }
        return try JSONDecoder().decode([AssistantEvalCase].self, from: Data(contentsOf: url))
    }

    public static func runAssistantCase(_ sample: AssistantEvalCase, transport: any ChatTransport,
                                        context: ToolContext) async throws -> AssistantEvalResult {
        let parsed = EntryAmountParser.entries(in: sample.question)
        let local = ToolContext(ledger: context.ledger, now: context.now, confirmedEntryAmount: context.confirmedEntryAmount,
            parsedEntryAmounts: parsed.isEmpty ? context.parsedEntryAmounts : parsed.map(\.amount),
            parsedEntries: parsed.isEmpty ? context.parsedEntries : parsed, entryAccountHint: context.entryAccountHint,
            memoryCharacterBudget: context.memoryCharacterBudget)
        let reply = try await AskYubai.answer(sample.question, transport: transport, context: local)
        let names = Set(reply.toolTrace.map(\.name))
        let kinds = reply.proposedChangeSets.flatMap(\.items).map { item -> String in
            if case .setCategory = item { return "set_category" }
            if case .addEntry = item { return "add_entry" }
            if case .profile = item { return "profile" }; return "other"
        }
        let expectedChanges = sample.expectedChangeKinds.map { $0 == kinds } ?? true
        let refused = sample.expectRefusal != true || (reply.proposedChangeSets.isEmpty && reply.text.contains("不能"))
        return AssistantEvalResult(id: sample.id, reply: reply,
            passed: sample.expectedTools.allSatisfy { names.contains($0) }
                && sample.expectedNumbers.allSatisfy { reply.text.contains($0) } && reply.unverifiedAmounts.isEmpty && expectedChanges && refused)
    }
}
