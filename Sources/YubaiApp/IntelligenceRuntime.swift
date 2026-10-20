import Foundation
import YubaiCore

/// Cloud assistance is optional; local calculations remain available without it.
@MainActor
enum IntelligenceRuntime {
    static func backend(for preferences: Preferences) -> CloudBackend? {
        CloudBackend.configured(enabled: preferences.cloudAIEnabled)
    }

    static func backend(for ledger: Ledger) -> CloudBackend? {
        CloudBackend.configured(enabled: ledger.preferences.cloudAIEnabled, redactor: Redactor(ledger: ledger))
    }

    static func availabilityText(for preferences: Preferences) -> String {
        guard preferences.cloudAIEnabled else {
            return "云端智能已关闭；使用本机计算结果。"
        }
        guard backend(for: preferences) != nil else {
            return "未配置 DeepSeek 密钥；使用本机计算结果。"
        }
        return "云端智能 · DeepSeek；请求失败时保留本机计算结果。"
    }
}

struct ActiveImportTransport: ChatTransport {
    let client: DeepSeekClient
    let isCurrent: @MainActor @Sendable () -> Bool
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        guard await isCurrent() else { throw CancellationError() }
        return try await client.send(request)
    }
}

@MainActor extension AppStore {
    func organizePendingImports() async {
        guard !locked, loadFailure == nil || isDemo, current.preferences.cloudAIEnabled else { return }
        let ids = current.imports.filter { $0.needsOrganization == true && $0.undoneAt == nil }.map(\.id)
        for id in ids {
            guard !Task.isCancelled else { return }
            await organizeImport(id)
        }
    }
    func organizeImport(_ batchID: UUID) async {
        guard organizingBatchID == nil, !locked,
              let batch = current.imports.first(where: { $0.id == batchID }), batch.needsOrganization == true,
              batch.undoneAt == nil, current.preferences.cloudAIEnabled,
              let client = DeepSeekClient.configured(redactor: Redactor(ledger: current)) else { return }
        let before = current; let wasDemo = isDemo
        organizingBatchID = batchID; organizationErrors[batchID] = nil
        defer { organizingBatchID = nil }
        do {
            let ids = before.activeEntries.filter { $0.batchID == batchID && !$0.userEdited }.map(\.id)
            let transport = ActiveImportTransport(client: client) {
                self.current == before && self.isDemo == wasDemo && !self.locked && APIKeyStore.shared.configuration() == client.configuration
            }
            let result = try await ImportOrganizer(transport: transport).organize(ledger: before, entryIDs: ids)
            try Task.checkCancellation()
            guard current == before, isDemo == wasDemo, !locked else {
                organizationErrors[batchID] = "账本已更新，本次整理未写入。可以点「现在整理」再试。"; return
            }
            if apply(result.changeSet, label: "导入整理", finishing: { ledger in
                result.finish(batchID: batchID, before: before, in: &ledger)
            }), !result.skipped.isEmpty { toast = "整理完成；" + result.skipped.joined(separator: "；") }
        } catch is CancellationError { }
        catch { organizationErrors[batchID] = "记录已保存，整理暂未完成。联网后可再试。" }
    }
    func answerImportQuestion(_ question: ImportQuestion, batchID: UUID, option: Int) {
        guard let change = question.answer(option, in: current) else { return }
        let before = current
        apply(change, label: "回答整理问题") { ledger in
            if let i = ledger.imports.firstIndex(where: { $0.id == batchID }) {
                ledger.imports[i].organization?.questions.removeAll { $0.id == question.id }
            }
            for i in ledger.cards.indices where ledger.cards[i].importQuestion?.id == question.id { ledger.cards[i].dismissedAt = Date() }
            ImportOrganization.recordUndo(batchID: batchID, before: before, in: &ledger)
        }
    }
    func describeImportQuestion(_ question: ImportQuestion, batchID: UUID, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80 else { return }
        // Free text records the user's purpose. It does not guess the nature of money.
        let answer = ImportQuestion(text: question.text, entryIDs: question.entryIDs,
            options: [ImportAnswer(title: "都不是", items: question.entryIDs.map { .setPurpose(entry: $0, text: clean) })])
        var matched = answer; matched.id = question.id
        answerImportQuestion(matched, batchID: batchID, option: 0)
    }
    func undoImport(_ batchID: UUID) {
        update("整批撤销", preservingUpdatedAt: true) { ledger in BillImporter.undo(batchID: batchID, in: &ledger) }
    }
}

@MainActor extension AppStore {
    func refreshButler() async {
        guard !locked, loadFailure == nil || isDemo, organizingBatchID == nil, current.preferences.onboardingComplete else { return }
        let before = current; let wasDemo = isDemo; let now = Date()
        var candidates = ButlerCards.detect(before, now: now)
        if let letter = WeeklyLetter.candidate(before, now: now) { candidates.append(letter) }
        guard !candidates.isEmpty else { return }
        let client = before.preferences.cloudAIEnabled ? DeepSeekClient.configured(redactor: Redactor(ledger: before)) : nil
        let transport: (any ChatTransport)? = client.map { client in ActiveImportTransport(client: client) {
            self.current == before && self.isDemo == wasDemo && !self.locked && APIKeyStore.shared.configuration() == client.configuration
        } }
        let worded = await ButlerWording.word(candidates, ledger: before, transport: transport)
        guard !Task.isCancelled, current == before, isDemo == wasDemo, !locked, organizingBatchID == nil else { return }
        var next = before
        guard ButlerCards.refresh(&next, candidates: worded, now: now) else { return }
        update("更新管家卡片", recordUndo: false) { $0.cards = next.cards }
    }
    func dismissCard(_ id: UUID) {
        guard current.cards.contains(where: { $0.id == id && $0.dismissedAt == nil }) else { return }
        update("收起管家卡片") { ledger in
            if let i = ledger.cards.firstIndex(where: { $0.id == id }) { ledger.cards[i].dismissedAt = Date() }
        }
    }
    func muteCard(_ id: UUID) {
        update("以后不再提这个话题") { ButlerCards.mute(id, in: &$0, now: Date()) }
    }
    func cardFeedback(_ value: CardFeedback, id: UUID) {
        update("记下卡片反馈") { ButlerCards.feedback(value, cardID: id, in: &$0, now: Date()) }
    }
    func performCardAction(_ card: ButlerCard) {
        switch card.action ?? .openEvidence {
        case .openEvidence: sheet = .cardEvidence(card.id)
        case .reconcileAccount(let id): sheet = .reconcile(id)
        case .confirmChangeSet(let id): sheet = .cardProposal(id)
        case .answerQuestion: sheet = .cardQuestion(card.id)
        case .openWish(let id): sheet = .wishlist(id)
        }
    }
}
