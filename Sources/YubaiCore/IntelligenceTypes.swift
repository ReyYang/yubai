import Foundation

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
