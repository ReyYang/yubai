import Foundation

public enum ButlerRunTrigger: Equatable, Sendable {
    case weekly, payday(String), spike(String)
}
public enum ButlerCadence {
    public static func weeklyDue(_ ledger: Ledger, now: Date) -> Bool {
        guard MemoryReflection.isDue(ledger: ledger, now: now) else { return false }
        return ledger.butlerAI?.weeklyAt.map { now >= Dates.addDays(7, to: $0) } ?? true
    }
    /// Pure eligibility. Ordinary opens with no due trigger produce no request.
    public static func due(_ ledger: Ledger, now: Date, suggestions: Bool) -> [ButlerRunTrigger] {
        var triggers: [ButlerRunTrigger] = []
        if weeklyDue(ledger, now: now) { triggers.append(.weekly) }
        guard suggestions else { return triggers }
        if let anchor = Finance.anchorPlan(in: ledger, now: now) {
            for income in ledger.activeEntries where income.nature == .income && income.planID == anchor.id && income.date <= now && Dates.day(income.date) == Dates.day(now) {
                let key = anchor.id.uuidString + ":" + Dates.text(income.occurrence ?? income.date)
                if ledger.butlerAI?.paydayRuns[key] == nil, !triggers.contains(.payday(key)) { triggers.append(.payday(key)) }
            }
        }
        for category in doubledCategories(ledger, now: now).sorted() {
            if ledger.butlerAI?.activeSpikes.contains(category) != true { triggers.append(.spike(category)) }
        }
        return triggers
    }
    /// A continuous spike is one episode, including across a calendar-week
    /// boundary. Only a return below double makes a later crossing eligible.
    public static func endedSpikes(_ ledger: Ledger, now: Date) -> Set<String> {
        (ledger.butlerAI?.activeSpikes ?? []).subtracting(doubledCategories(ledger, now: now))
    }
    public static func endSpikes(_ ended: Set<String>, in ledger: inout Ledger) {
        ledger.butlerAI?.activeSpikes.subtract(ended)
    }
    private static func doubledCategories(_ ledger: Ledger, now: Date) -> Set<String> {
        Set(ButlerDigest.build(ledger, now: now).categories.filter {
            $0.usualSumCents > 0 && $0.sumCents >= $0.usualSumCents * 2
        }.map(\.key))
    }
    /// Persist BEFORE sending, including failures. A malformed reply or lost
    /// connection cannot turn ordinary opens into repeated model calls.
    public static func recordAttempt(_ triggers: [ButlerRunTrigger], in ledger: inout Ledger, now: Date) {
        guard !triggers.isEmpty else { return }
        var state = ledger.butlerAI ?? ButlerAIState(); state.lastRunAt = now
        for trigger in triggers {
            switch trigger {
            case .weekly: state.weeklyAt = now
            case .payday(let key): state.paydayRuns[key] = now
            case .spike(let key): state.spikeRuns[key] = now; state.activeSpikes.insert(key)
            }
        }
        ledger.butlerAI = state
    }
}

public enum ButlerIntelligence {
    /// Payday and spike runs use the same transport/model settings as weekly
    /// reflection. Weekly uses MemoryReflection.run(includeButler: true) instead.
    public static func run(ledger: Ledger, transport: any ChatTransport, now: Date) async throws -> [ButlerSuggestion] {
        let digest = ButlerDigest.build(ledger, now: now), redactor = Redactor(ledger: ledger)
        let input = try redactor.value(digest.json()).jsonText()
        let reply = try await transport.send(ChatRequest(messages: [
            ChatMessage(role: .system, content: ButlerSuggestionVerifier.instruction + "\n返回且仅返回 {\"suggestions\":[]}"),
            ChatMessage(role: .user, content: input)
        ], temperature: 0, maxTokens: 8192, thinking: false, purpose: "管家的建议", responseFormat: .object(["type": .string("json_object")]), groupID: UUID(), groupTitle: "管家的建议"))
        try Task.checkCancellation()
        guard reply.role == .assistant, reply.toolCalls?.isEmpty ?? true, let content = reply.content,
              let root = try JSONValue.parse(content).objectValue, Set(root.keys) == ["suggestions"], let rows = root["suggestions"], rows.arrayValue != nil else {
            throw YubaiError.invalid("建议格式无效。")
        }
        return ButlerSuggestionVerifier.parse(redactor.value(rows), digest: digest, ledger: ledger, now: now)
    }
    public static func enqueue(_ suggestions: [ButlerSuggestion], in ledger: inout Ledger, now: Date) {
        var state = ledger.butlerAI ?? ButlerAIState()
        for value in suggestions where ButlerSuggestionVerifier.verify(value, in: ledger, now: now) {
            guard !state.suggestions.contains(where: { $0.topic == value.topic && $0.answeredAt == nil }) else { continue }
            state.suggestions.append(value)
        }
        ledger.butlerAI = state
    }
}
